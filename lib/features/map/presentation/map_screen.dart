import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../stores/data/dummy_store_locations.dart';
import '../../stores/domain/store_location.dart';
import 'store_preview_card.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.config, this.initialMapError});

  final AppConfig config;
  final Object? initialMapError;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _initialCameraPosition = CameraPosition(
    target: LatLng(37.5326, 127.0068),
    zoom: 12,
  );

  final Completer<GoogleMapController> _controller = Completer();
  StoreLocation? _selectedStore;
  bool _isMapReady = false;
  String _cameraStatus = '카메라 이동 대기 중';
  CameraPosition _lastCameraPosition = _initialCameraPosition;
  Object? _mapError;

  @override
  void initState() {
    super.initState();
    _mapError = widget.initialMapError;
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
    if (!widget.config.hasGoogleMapsApiKey) {
      return const MissingApiKeyView();
    }

    if (_mapError != null) {
      return MapErrorView(error: _mapError!);
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GoogleMap(
            initialCameraPosition: _initialCameraPosition,
            markers: _markers,
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

  Set<Marker> get _markers {
    return dummyStoreLocations.map((store) {
      return Marker(
        markerId: MarkerId(store.id),
        position: LatLng(store.latitude, store.longitude),
        infoWindow: InfoWindow(title: store.name),
        onTap: () {
          setState(() {
            _selectedStore = store;
          });
        },
      );
    }).toSet();
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

class MissingApiKeyView extends StatelessWidget {
  const MissingApiKeyView({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
            '지도 화면이 표시됩니다. 현재는 더미 매장 데이터만 확인합니다.',
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: dummyStoreLocations.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final store = dummyStoreLocations[index];

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
