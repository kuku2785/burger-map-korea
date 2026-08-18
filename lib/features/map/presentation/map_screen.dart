import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../stores/data/itaewon_store_locations.dart';
import '../../stores/data/staging_store_locations_loader.dart';
import '../../stores/data/supabase_store_locations_loader.dart';
import '../../stores/domain/store_location.dart';
import 'store_preview_card.dart';

typedef StagingStoreLoader = Future<List<StoreLocation>> Function();
typedef SupabaseStoreLoader = Future<List<StoreLocation>> Function();

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.config,
    this.initialMapError,
    this.stagingStoreLoader,
    this.supabaseStoreLoader,
  });

  final AppConfig config;
  final Object? initialMapError;
  final StagingStoreLoader? stagingStoreLoader;
  final SupabaseStoreLoader? supabaseStoreLoader;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _pilotCameraPosition = CameraPosition(
    target: LatLng(37.53415, 126.99007),
    zoom: 16,
  );

  final Completer<GoogleMapController> _controller = Completer();
  StoreLocation? _selectedStore;
  bool _isMapReady = false;
  String _cameraStatus = '카메라 이동 대기 중';
  CameraPosition _initialCameraPosition = _pilotCameraPosition;
  CameraPosition _lastCameraPosition = _pilotCameraPosition;
  List<StoreLocation>? _stores;
  Object? _storeLoadError;
  Object? _mapError;

  @override
  void initState() {
    super.initState();
    _mapError = widget.initialMapError;
    switch (widget.config.effectiveStoreDataMode) {
      case StoreDataMode.pilot:
        _stores = itaewonStoreLocations;
      case StoreDataMode.staging:
        _loadStagingStores();
      case StoreDataMode.supabase:
        if (widget.config.hasSupabaseConfiguration) {
          _loadSupabaseStores();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('버거맵 코리아'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text('기술 검증 · ${widget.config.environmentLabel}'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.config.usesSupabaseStoreData &&
        !widget.config.hasSupabaseConfiguration) {
      return MissingSupabaseConfigView(config: widget.config);
    }

    if (_storeLoadError != null) {
      if (widget.config.usesSupabaseStoreData) {
        return StoreDataErrorView(onRetry: _loadSupabaseStores);
      }
      return MapErrorView(error: _storeLoadError!);
    }

    final stores = _stores;
    if (stores == null) {
      return const StoreDataLoadingView();
    }

    if (widget.config.usesSupabaseStoreData && stores.isEmpty) {
      return const StoreDataEmptyView();
    }

    if (!widget.config.hasGoogleMapsApiKey) {
      return MissingApiKeyView(stores: stores);
    }

    if (_mapError != null) {
      return MapErrorView(error: _mapError!);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            markers: buildStoreMarkers(stores, (store) {
              setState(() {
                _selectedStore = store;
              });
            }),
            onMapCreated: _handleMapCreated,
            onTap: (_) {
              setState(() {
                _selectedStore = null;
              });
            },
            onCameraMoveStarted: () {
              setState(() {
                _cameraStatus = '카메라 이동 중';
              });
            },
            onCameraMove: (position) {
              _lastCameraPosition = position;
            },
            onCameraIdle: () {
              setState(() {
                _cameraStatus = '카메라 이동 완료';
              });
            },
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
          ),
        ),
        if (!_isMapReady) const _MapLoadingOverlay(),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: _CameraStatusCard(
            status: _cameraStatus,
            cameraPosition: _lastCameraPosition,
          ),
        ),
        if (_selectedStore != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: StorePreviewCard(store: _selectedStore!),
          ),
      ],
    );
  }

  Future<void> _loadStagingStores() async {
    try {
      final loader = widget.stagingStoreLoader;
      final stores = loader == null
          ? await loadYongsanStagingStoreLocations()
          : await loader();
      if (!mounted) {
        return;
      }
      final cameraPosition = cameraPositionForStores(stores);
      setState(() {
        _stores = stores;
        _initialCameraPosition = cameraPosition;
        _lastCameraPosition = cameraPosition;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _storeLoadError = error;
      });
    }
  }

  Future<void> _loadSupabaseStores() async {
    if (_storeLoadError != null || _stores != null) {
      setState(() {
        _storeLoadError = null;
        _stores = null;
        _selectedStore = null;
      });
    }

    try {
      final loader = widget.supabaseStoreLoader;
      if (loader == null) {
        throw const SupabaseStoreLoadException();
      }
      final stores = await loader();
      if (!mounted) {
        return;
      }
      final cameraPosition = cameraPositionForStores(stores);
      setState(() {
        _stores = stores;
        _initialCameraPosition = cameraPosition;
        _lastCameraPosition = cameraPosition;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _storeLoadError = const SupabaseStoreLoadException();
      });
    }
  }

  void _handleMapCreated(GoogleMapController controller) {
    if (!_controller.isCompleted) {
      _controller.complete(controller);
    }

    setState(() {
      _isMapReady = true;
      _cameraStatus = '지도 로딩 완료';
    });
  }
}

Set<Marker> buildStoreMarkers(
  List<StoreLocation> stores,
  ValueChanged<StoreLocation> onSelected,
) {
  return stores.map((store) {
    return Marker(
      markerId: MarkerId(store.id),
      position: LatLng(store.latitude, store.longitude),
      infoWindow: InfoWindow(title: store.name),
      onTap: () => onSelected(store),
    );
  }).toSet();
}

CameraPosition cameraPositionForStores(List<StoreLocation> stores) {
  if (stores.isEmpty) {
    return _MapScreenState._pilotCameraPosition;
  }
  final minimumLatitude = stores
      .map((store) => store.latitude)
      .reduce(math.min);
  final maximumLatitude = stores
      .map((store) => store.latitude)
      .reduce(math.max);
  final minimumLongitude = stores
      .map((store) => store.longitude)
      .reduce(math.min);
  final maximumLongitude = stores
      .map((store) => store.longitude)
      .reduce(math.max);
  final span = math.max(
    maximumLatitude - minimumLatitude,
    maximumLongitude - minimumLongitude,
  );
  final zoom = switch (span) {
    > 0.06 => 11.5,
    > 0.035 => 12.5,
    > 0.02 => 13.5,
    _ => 14.5,
  };
  return CameraPosition(
    target: LatLng(
      (minimumLatitude + maximumLatitude) / 2,
      (minimumLongitude + maximumLongitude) / 2,
    ),
    zoom: zoom,
  );
}

class MissingApiKeyView extends StatelessWidget {
  const MissingApiKeyView({super.key, this.stores});

  final List<StoreLocation>? stores;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleStores = stores ?? itaewonStoreLocations;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.key_off_outlined, size: 44, color: colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Google Maps API 키가 설정되지 않았습니다',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text(
            'GOOGLE_MAPS_API_KEY를 Dart define과 네이티브 설정에 주입하면 '
            '지도 화면이 표시됩니다. 현재는 이태원 검수 매장 데이터만 확인합니다.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: visibleStores.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final store = visibleStores[index];

                return ListTile(
                  leading: const Icon(Icons.lunch_dining_outlined),
                  title: Text(store.name),
                  subtitle: Text('${store.address}\n${store.burgerStyle}'),
                  isThreeLine: true,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class StoreDataLoadingView extends StatelessWidget {
  const StoreDataLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class MissingSupabaseConfigView extends StatelessWidget {
  const MissingSupabaseConfigView({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final missingVariables = <String>[
      if (!config.hasSupabaseUrl) 'SUPABASE_URL',
      if (!config.hasSupabasePublishableKey) 'SUPABASE_PUBLISHABLE_KEY',
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Supabase 공개 설정이 필요합니다.',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '누락된 설정: ${missingVariables.join(', ')}',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class StoreDataEmptyView extends StatelessWidget {
  const StoreDataEmptyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '현재 공개된 매장이 없습니다.',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class StoreDataErrorView extends StatelessWidget {
  const StoreDataErrorView({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              '공개 매장 정보를 불러오지 못했습니다.',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLoadingOverlay extends StatelessWidget {
  const _MapLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x66FFFFFF),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class MapErrorView extends StatelessWidget {
  const MapErrorView({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('지도를 불러오지 못했습니다.\n$error'),
      ),
    );
  }
}

class _CameraStatusCard extends StatelessWidget {
  const _CameraStatusCard({required this.status, required this.cameraPosition});

  final String status;
  final CameraPosition cameraPosition;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.videocam_outlined),
                const SizedBox(width: 10),
                Text(status),
              ],
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 6),
              Text(
                'debug center: '
                '${cameraPosition.target.latitude.toStringAsFixed(4)}, '
                '${cameraPosition.target.longitude.toStringAsFixed(4)} · '
                'zoom ${cameraPosition.zoom.toStringAsFixed(1)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
