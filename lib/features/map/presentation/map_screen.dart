import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../favorites/data/shared_preferences_favorite_store_ids_store.dart';
import '../../favorites/domain/favorite_store_ids_store.dart';
import '../../location/data/geolocator_current_location_service.dart';
import '../../location/domain/current_location_service.dart';
import '../../stores/data/external_uri_launcher.dart';
import '../../stores/data/itaewon_store_locations.dart';
import '../../stores/data/staging_store_locations_loader.dart';
import '../../stores/data/supabase_store_locations_loader.dart';
import '../../stores/domain/burger_style.dart';
import '../../stores/domain/store_location.dart';
import '../../stores/domain/store_search.dart';
import '../../stores/presentation/store_detail_screen.dart';
import 'store_preview_card.dart';

typedef StagingStoreLoader = Future<List<StoreLocation>> Function();
typedef SupabaseStoreLoader = Future<List<StoreLocation>> Function();
typedef StoreCameraMover = Future<void> Function(StoreLocation store);
typedef MapZoomMover = Future<void> Function(double zoom);
typedef CurrentLocationCameraMover =
    Future<void> Function(LatLng location, double zoom);
typedef ClusterCameraMover =
    Future<void> Function(LatLngBounds bounds, double padding);
typedef StoreMapSurfaceBuilder =
    Widget Function(Set<Marker> markers, ValueChanged<LatLng> onMapTap);

const storeSearchFieldKey = ValueKey<String>('store-search-field');
const storeSearchClearButtonKey = ValueKey<String>('store-search-clear-button');
const storeSearchResultsKey = ValueKey<String>('store-search-results');
const burgerStyleAllFilterKey = ValueKey<String>('burger-style-filter-all');
const favoritesOnlyFilterKey = ValueKey<String>('favorites-only-filter');
const mapZoomInButtonKey = ValueKey<String>('map-zoom-in-button');
const mapZoomOutButtonKey = ValueKey<String>('map-zoom-out-button');
const currentLocationButtonKey = ValueKey<String>('current-location-button');
const storeDataReadyStatusKey = ValueKey<String>('store-data-ready-status');
const minimumMapZoom = 3.0;
const maximumMapZoom = 20.0;
const mapZoomStep = 1.0;
const currentLocationZoom = 16.0;
const clusterBoundsPadding = 72.0;
const storeMarkerClusterManagerId = ClusterManagerId('public-store-markers');

ValueKey<String> burgerStyleFilterKey(BurgerStyle style) {
  return ValueKey<String>('burger-style-filter-${style.code}');
}

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    required this.config,
    this.initialMapError,
    this.stagingStoreLoader,
    this.supabaseStoreLoader,
    this.storeCameraMover,
    this.mapZoomMover,
    this.currentLocationCameraMover,
    this.currentLocationService,
    this.onMyLocationEnabledChanged,
    this.clusterCameraMover,
    this.onClusterManagerReady,
    this.mapSurfaceBuilder,
    this.externalUriLauncher,
    this.favoriteStoreIdsStore,
  });

  final AppConfig config;
  final Object? initialMapError;
  final StagingStoreLoader? stagingStoreLoader;
  final SupabaseStoreLoader? supabaseStoreLoader;
  final StoreCameraMover? storeCameraMover;
  final MapZoomMover? mapZoomMover;
  final CurrentLocationCameraMover? currentLocationCameraMover;
  final CurrentLocationService? currentLocationService;
  final ValueChanged<bool>? onMyLocationEnabledChanged;
  final ClusterCameraMover? clusterCameraMover;
  final ValueChanged<ClusterManager>? onClusterManagerReady;
  final StoreMapSurfaceBuilder? mapSurfaceBuilder;
  final ExternalUriLauncher? externalUriLauncher;
  final FavoriteStoreIdsStore? favoriteStoreIdsStore;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _pilotCameraPosition = CameraPosition(
    target: LatLng(37.53415, 126.99007),
    zoom: 16,
  );

  final Completer<GoogleMapController> _controller = Completer();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final FavoriteStoreIdsStore _favoriteStoreIdsStore;
  late final CurrentLocationService _currentLocationService;
  late final ClusterManager _storeMarkerClusterManager;
  StoreLocation? _selectedStore;
  BurgerStyle? _selectedBurgerStyle;
  Set<String> _favoriteStoreIds = const <String>{};
  String _searchQuery = '';
  bool _favoritesOnly = false;
  bool _favoritesLoaded = false;
  bool _isMapReady = false;
  bool _isChangingZoom = false;
  bool _isMovingToCluster = false;
  bool _isRequestingCurrentLocation = false;
  bool _isCurrentLocationEnabled = false;
  String _cameraStatus = '카메라 이동 대기 중';
  CameraPosition _initialCameraPosition = _pilotCameraPosition;
  CameraPosition _lastCameraPosition = _pilotCameraPosition;
  List<StoreLocation>? _stores;
  Object? _storeLoadError;
  Object? _mapError;

  @override
  void initState() {
    super.initState();
    _storeMarkerClusterManager = ClusterManager(
      clusterManagerId: storeMarkerClusterManagerId,
      onClusterTap: _handleClusterTap,
    );
    widget.onClusterManagerReady?.call(_storeMarkerClusterManager);
    _favoriteStoreIdsStore =
        widget.favoriteStoreIdsStore ??
        SharedPreferencesFavoriteStoreIdsStore();
    _currentLocationService =
        widget.currentLocationService ??
        const GeolocatorCurrentLocationService();
    _mapError = widget.initialMapError;
    _loadFavoriteStoreIds();
    _initializeStores();
  }

  void _initializeStores() {
    if (kReleaseMode) {
      if (widget.config.hasSupabaseConfiguration) {
        _loadSupabaseStores();
      }
      return;
    }

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
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('버거맵 코리아'),
        actions: widget.config.showsDevelopmentDiagnostics
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Chip(
                      label: Text('기술 검증 · ${widget.config.environmentLabel}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ]
            : null,
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.config.usesSupabaseStoreData &&
        !widget.config.hasSupabaseConfiguration) {
      return const MissingSupabaseConfigView();
    }

    if (_storeLoadError != null) {
      if (widget.config.usesSupabaseStoreData) {
        return StoreDataErrorView(onRetry: _loadSupabaseStores);
      }
      return MapErrorView(
        error: _storeLoadError!,
        showDiagnostics: widget.config.showsDevelopmentDiagnostics,
      );
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
      return MapErrorView(
        error: _mapError!,
        showDiagnostics: widget.config.showsDevelopmentDiagnostics,
      );
    }

    final availableStyles = availableBurgerStyles(stores);
    final visibleStores = filterStoreLocations(
      stores,
      _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
    );
    final markers = buildStoreMarkers(visibleStores, _selectStore);
    final mapSurfaceBuilder = widget.mapSurfaceBuilder;
    final currentZoom = _lastCameraPosition.zoom.clamp(
      minimumMapZoom,
      maximumMapZoom,
    );
    final canChangeZoom =
        !_isChangingZoom && (_isMapReady || widget.mapZoomMover != null);
    final canRequestCurrentLocation =
        !_isRequestingCurrentLocation &&
        (_isMapReady || widget.currentLocationCameraMover != null);

    return Stack(
      children: [
        Positioned.fill(
          child: mapSurfaceBuilder == null
              ? GoogleMap(
                  initialCameraPosition: _initialCameraPosition,
                  markers: markers,
                  clusterManagers: <ClusterManager>{_storeMarkerClusterManager},
                  onMapCreated: _handleMapCreated,
                  onTap: _handleMapTap,
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
                  myLocationEnabled: _isCurrentLocationEnabled,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                  zoomControlsEnabled: false,
                )
              : mapSurfaceBuilder(markers, _handleMapTap),
        ),
        if (!_isMapReady && mapSurfaceBuilder == null)
          const _MapLoadingOverlay(),
        if (_isMapReady || mapSurfaceBuilder != null)
          Positioned(
            left: 0,
            top: 0,
            child: _ScreenReaderStatus(
              key: storeDataReadyStatusKey,
              message: '공개 매장 ${stores.length}개를 불러왔습니다.',
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _StoreSearchPanel(
                controller: _searchController,
                focusNode: _searchFocusNode,
                query: _searchQuery,
                results: visibleStores,
                availableStyles: availableStyles,
                selectedBurgerStyle: _selectedBurgerStyle,
                favoritesOnly: _favoritesOnly,
                favoritesLoaded: _favoritesLoaded,
                onChanged: _handleSearchChanged,
                onClear: _clearSearch,
                onSelected: _selectSearchResult,
                onBurgerStyleSelected: _handleBurgerStyleChanged,
                onFavoritesOnlyChanged: _handleFavoritesOnlyChanged,
              ),
              if (widget.config.showsDevelopmentDiagnostics &&
                  normalizeStoreSearchText(_searchQuery).isEmpty &&
                  _selectedBurgerStyle == null &&
                  !_favoritesOnly) ...[
                const SizedBox(height: 8),
                _CameraStatusCard(
                  status: _cameraStatus,
                  cameraPosition: _lastCameraPosition,
                ),
              ],
            ],
          ),
        ),
        if (_selectedStore == null)
          Positioned(
            right: 16,
            bottom: 16,
            child: _MapActionControls(
              currentZoom: currentZoom.toDouble(),
              onZoomIn: canChangeZoom && currentZoom < maximumMapZoom
                  ? () => _changeMapZoom(mapZoomStep)
                  : null,
              onZoomOut: canChangeZoom && currentZoom > minimumMapZoom
                  ? () => _changeMapZoom(-mapZoomStep)
                  : null,
              onCurrentLocation: canRequestCurrentLocation
                  ? _requestCurrentLocation
                  : null,
              isRequestingCurrentLocation: _isRequestingCurrentLocation,
            ),
          )
        else
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MapActionControls(
                  currentZoom: currentZoom.toDouble(),
                  onZoomIn: canChangeZoom && currentZoom < maximumMapZoom
                      ? () => _changeMapZoom(mapZoomStep)
                      : null,
                  onZoomOut: canChangeZoom && currentZoom > minimumMapZoom
                      ? () => _changeMapZoom(-mapZoomStep)
                      : null,
                  onCurrentLocation: canRequestCurrentLocation
                      ? _requestCurrentLocation
                      : null,
                  isRequestingCurrentLocation: _isRequestingCurrentLocation,
                ),
                const SizedBox(height: 8),
                StorePreviewCard(
                  store: _selectedStore!,
                  onViewDetails: () => _openStoreDetails(_selectedStore!),
                ),
              ],
            ),
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
      _applyLoadedStores(stores);
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
      _applyLoadedStores(stores);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _storeLoadError = const SupabaseStoreLoadException();
      });
    }
  }

  Future<void> _loadFavoriteStoreIds() async {
    try {
      final storeIds = await _favoriteStoreIdsStore.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _favoriteStoreIds = storeIds;
        _favoritesLoaded = true;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _favoriteStoreIds = const <String>{};
        _favoritesLoaded = true;
      });
    }
  }

  void _selectStore(StoreLocation store) {
    setState(() {
      _selectedStore = store;
    });
  }

  void _handleMapTap(LatLng _) {
    setState(() {
      _selectedStore = null;
    });
  }

  void _handleSearchChanged(String query) {
    final stores = _stores ?? const <StoreLocation>[];
    final visibleStoreIds = filterStoreLocations(
      stores,
      query,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
    ).map((store) => store.id).toSet();

    setState(() {
      _searchQuery = query;
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _handleBurgerStyleChanged(BurgerStyle? burgerStyle) {
    final stores = _stores ?? const <StoreLocation>[];
    final visibleStoreIds = filterStoreLocations(
      stores,
      _searchQuery,
      burgerStyle: burgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
    ).map((store) => store.id).toSet();

    setState(() {
      _selectedBurgerStyle = burgerStyle;
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _handleFavoritesOnlyChanged(bool favoritesOnly) {
    final stores = _stores ?? const <StoreLocation>[];
    final visibleStoreIds = filterStoreLocations(
      stores,
      _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: favoritesOnly,
    ).map((store) => store.id).toSet();

    setState(() {
      _favoritesOnly = favoritesOnly;
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _handleSearchChanged('');
  }

  Future<void> _selectSearchResult(StoreLocation store) async {
    _searchFocusNode.unfocus();
    _selectStore(store);

    final storeCameraMover = widget.storeCameraMover;
    if (storeCameraMover != null) {
      await storeCameraMover(store);
      return;
    }
    if (!_controller.isCompleted) {
      return;
    }

    final controller = await _controller.future;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(store.latitude, store.longitude), 16),
    );
  }

  Future<void> _handleClusterTap(Cluster cluster) async {
    if (!mounted || _isMovingToCluster) {
      return;
    }

    _isMovingToCluster = true;
    if (_selectedStore != null) {
      setState(() {
        _selectedStore = null;
      });
    }

    try {
      final clusterCameraMover = widget.clusterCameraMover;
      if (clusterCameraMover != null) {
        await clusterCameraMover(cluster.bounds, clusterBoundsPadding);
        return;
      }
      if (!_controller.isCompleted || !mounted) {
        return;
      }

      final controller = await _controller.future;
      if (!mounted) {
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(cluster.bounds, clusterBoundsPadding),
      );
    } on Object {
      // Cluster camera movement is best-effort during map lifecycle changes.
    } finally {
      _isMovingToCluster = false;
    }
  }

  Future<void> _requestCurrentLocation() async {
    if (!mounted || _isRequestingCurrentLocation) {
      return;
    }

    setState(() {
      _isRequestingCurrentLocation = true;
    });

    try {
      final serviceEnabled = await _currentLocationService
          .isLocationServiceEnabled();
      if (!mounted) {
        return;
      }
      if (!serviceEnabled) {
        _disableCurrentLocation();
        _showCurrentLocationMessage(
          '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치 서비스를 켠 뒤 다시 시도해 주세요.',
        );
        return;
      }

      var permission = await _currentLocationService.checkPermission();
      if (!mounted) {
        return;
      }
      if (permission == LocationPermissionStatus.denied) {
        permission = await _currentLocationService.requestPermission();
        if (!mounted) {
          return;
        }
      }

      if (!_hasLocationPermission(permission)) {
        _disableCurrentLocation();
        _showCurrentLocationMessage(
          permission == LocationPermissionStatus.deniedForever
              ? '현재 위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해 주세요.'
              : '현재 위치 권한이 허용되지 않았습니다. 필요할 때 다시 요청할 수 있습니다.',
          showSettingsAction:
              permission == LocationPermissionStatus.deniedForever,
        );
        return;
      }

      _setCurrentLocationEnabled(true);
      final location = await _currentLocationService.getCurrentLocation();
      if (!mounted) {
        return;
      }

      final target = LatLng(location.latitude, location.longitude);
      final currentLocationCameraMover = widget.currentLocationCameraMover;
      if (currentLocationCameraMover != null) {
        await currentLocationCameraMover(target, currentLocationZoom);
        return;
      }
      if (!_controller.isCompleted) {
        return;
      }

      final controller = await _controller.future;
      if (!mounted) {
        return;
      }
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(target, currentLocationZoom),
      );
    } on Object {
      if (mounted) {
        _showCurrentLocationMessage('현재 위치를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequestingCurrentLocation = false;
        });
      }
    }
  }

  bool _hasLocationPermission(LocationPermissionStatus permission) {
    return permission == LocationPermissionStatus.whileInUse ||
        permission == LocationPermissionStatus.always;
  }

  void _disableCurrentLocation() {
    _setCurrentLocationEnabled(false);
  }

  void _setCurrentLocationEnabled(bool enabled) {
    if (_isCurrentLocationEnabled == enabled) {
      return;
    }
    setState(() {
      _isCurrentLocationEnabled = enabled;
    });
    widget.onMyLocationEnabledChanged?.call(enabled);
  }

  void _showCurrentLocationMessage(
    String message, {
    bool showSettingsAction = false,
  }) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: showSettingsAction
            ? SnackBarAction(
                label: '설정 열기',
                onPressed: _openLocationAppSettings,
              )
            : null,
      ),
    );
  }

  Future<void> _openLocationAppSettings() async {
    try {
      final opened = await _currentLocationService.openAppSettings();
      if (!opened && mounted) {
        _showCurrentLocationMessage('설정 화면을 열 수 없습니다.');
      }
    } on Object {
      if (mounted) {
        _showCurrentLocationMessage('설정 화면을 열 수 없습니다.');
      }
    }
  }

  Future<void> _changeMapZoom(double delta) async {
    if (_isChangingZoom) {
      return;
    }

    final currentZoom = _lastCameraPosition.zoom.clamp(
      minimumMapZoom,
      maximumMapZoom,
    );
    final targetZoom = (currentZoom + delta).clamp(
      minimumMapZoom,
      maximumMapZoom,
    );
    if (targetZoom == currentZoom) {
      return;
    }

    setState(() {
      _isChangingZoom = true;
    });
    try {
      final mapZoomMover = widget.mapZoomMover;
      if (mapZoomMover != null) {
        await mapZoomMover(targetZoom.toDouble());
      } else {
        if (!_controller.isCompleted) {
          return;
        }
        final controller = await _controller.future;
        await controller.animateCamera(
          CameraUpdate.zoomTo(targetZoom.toDouble()),
        );
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _lastCameraPosition = CameraPosition(
          target: _lastCameraPosition.target,
          zoom: targetZoom.toDouble(),
          tilt: _lastCameraPosition.tilt,
          bearing: _lastCameraPosition.bearing,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isChangingZoom = false;
        });
      }
    }
  }

  Future<void> _openStoreDetails(StoreLocation store) async {
    final externalUriLauncher = widget.externalUriLauncher;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => externalUriLauncher == null
            ? StoreDetailScreen(
                store: store,
                isFavorite: _favoriteStoreIds.contains(store.id),
                onFavoriteChanged: (isFavorite) =>
                    _setStoreFavorite(store, isFavorite),
              )
            : StoreDetailScreen(
                store: store,
                externalUriLauncher: externalUriLauncher,
                isFavorite: _favoriteStoreIds.contains(store.id),
                onFavoriteChanged: (isFavorite) =>
                    _setStoreFavorite(store, isFavorite),
              ),
      ),
    );
  }

  Future<void> _setStoreFavorite(StoreLocation store, bool isFavorite) async {
    final nextStoreIds = Set<String>.of(_favoriteStoreIds);
    if (isFavorite) {
      nextStoreIds.add(store.id);
    } else {
      nextStoreIds.remove(store.id);
    }
    await _favoriteStoreIdsStore.save(nextStoreIds);
    if (!mounted) {
      return;
    }

    final visibleStoreIds = filterStoreLocations(
      _stores ?? const <StoreLocation>[],
      _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: nextStoreIds,
      favoritesOnly: _favoritesOnly,
    ).map((item) => item.id).toSet();
    setState(() {
      _favoriteStoreIds = Set<String>.unmodifiable(nextStoreIds);
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _applyLoadedStores(List<StoreLocation> stores) {
    final cameraPosition = cameraPositionForStores(stores);
    setState(() {
      _stores = stores;
      _selectedBurgerStyle = validBurgerStyleSelection(
        _selectedBurgerStyle,
        stores,
      );
      _initialCameraPosition = cameraPosition;
      _lastCameraPosition = cameraPosition;
    });
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

class _StoreSearchPanel extends StatelessWidget {
  const _StoreSearchPanel({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.results,
    required this.availableStyles,
    required this.selectedBurgerStyle,
    required this.favoritesOnly,
    required this.favoritesLoaded,
    required this.onChanged,
    required this.onClear,
    required this.onSelected,
    required this.onBurgerStyleSelected,
    required this.onFavoritesOnlyChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final List<StoreLocation> results;
  final List<BurgerStyle> availableStyles;
  final BurgerStyle? selectedBurgerStyle;
  final bool favoritesOnly;
  final bool favoritesLoaded;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<StoreLocation> onSelected;
  final ValueChanged<BurgerStyle?> onBurgerStyleSelected;
  final ValueChanged<bool> onFavoritesOnlyChanged;

  @override
  Widget build(BuildContext context) {
    final hasQuery = normalizeStoreSearchText(query).isNotEmpty;
    final hasActiveCriteria =
        hasQuery || selectedBurgerStyle != null || favoritesOnly;
    final emptyResultsMessage =
        favoritesOnly && !hasQuery && selectedBurgerStyle == null
        ? '즐겨찾기한 매장이 없습니다.'
        : '검색 결과가 없습니다.';
    final maximumResultsHeight = math.min(
      220.0,
      math.max(96.0, MediaQuery.sizeOf(context).height * 0.28),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            label: '매장명 또는 주소 검색',
            child: TextField(
              key: storeSearchFieldKey,
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                label: const ExcludeSemantics(child: Text('매장 검색')),
                hint: const ExcludeSemantics(child: Text('매장명 또는 주소')),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: hasQuery
                    ? IconButton(
                        key: storeSearchClearButtonKey,
                        onPressed: onClear,
                        tooltip: '검색어 지우기',
                        icon: const Icon(Icons.clear),
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surface,
          child: SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              itemCount: availableStyles.length + 2,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Semantics(
                    button: true,
                    enabled: favoritesLoaded,
                    selected: favoritesOnly,
                    label: '즐겨찾기 매장만 보기',
                    onTap: favoritesLoaded
                        ? () => onFavoritesOnlyChanged(!favoritesOnly)
                        : null,
                    child: ExcludeSemantics(
                      child: FilterChip(
                        key: favoritesOnlyFilterKey,
                        avatar: Icon(
                          favoritesOnly ? Icons.star : Icons.star_border,
                          size: 18,
                        ),
                        label: const Text('즐겨찾기'),
                        selected: favoritesOnly,
                        onSelected: favoritesLoaded
                            ? onFavoritesOnlyChanged
                            : null,
                      ),
                    ),
                  );
                }

                final style = index == 1 ? null : availableStyles[index - 2];
                final label = style?.displayLabel ?? '전체';
                final isSelected = style == selectedBurgerStyle;

                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: '버거 스타일 $label 필터',
                  onTap: () => onBurgerStyleSelected(style),
                  child: ExcludeSemantics(
                    child: ChoiceChip(
                      key: style == null
                          ? burgerStyleAllFilterKey
                          : burgerStyleFilterKey(style),
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (_) => onBurgerStyleSelected(style),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (hasActiveCriteria) ...[
          const SizedBox(height: 8),
          Material(
            key: storeSearchResultsKey,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(context).colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maximumResultsHeight),
              child: results.isEmpty
                  ? _LiveRegionMessage(
                      message: emptyResultsMessage,
                      child: SizedBox(
                        height: 64,
                        child: Center(child: Text(emptyResultsMessage)),
                      ),
                    )
                  : Semantics(
                      container: true,
                      explicitChildNodes: true,
                      liveRegion: true,
                      label: '검색 결과 ${results.length}개',
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: results.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final store = results[index];
                          return ListTile(
                            key: ValueKey<String>(
                              'store-search-result-${store.id}',
                            ),
                            minTileHeight: 56,
                            title: Text(
                              store.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              store.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => onSelected(store),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MapActionControls extends StatelessWidget {
  const _MapActionControls({
    required this.currentZoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCurrentLocation,
    required this.isRequestingCurrentLocation,
  });

  final double currentZoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onCurrentLocation;
  final bool isRequestingCurrentLocation;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _CurrentLocationButton(
          key: currentLocationButtonKey,
          isLoading: isRequestingCurrentLocation,
          onPressed: onCurrentLocation,
        ),
        const SizedBox(height: 8),
        _MapZoomControls(
          currentZoom: currentZoom,
          onZoomIn: onZoomIn,
          onZoomOut: onZoomOut,
        ),
      ],
    );
  }
}

class _CurrentLocationButton extends StatelessWidget {
  const _CurrentLocationButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final label = isLoading ? '현재 위치를 찾는 중입니다.' : '현재 위치로 이동';
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surface,
          child: IconButton(
            onPressed: onPressed,
            tooltip: label,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ),
    );
  }
}

class _MapZoomControls extends StatelessWidget {
  const _MapZoomControls({
    required this.currentZoom,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final double currentZoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapZoomButton(
            key: mapZoomInButtonKey,
            label: '지도 확대',
            icon: Icons.add,
            onPressed: currentZoom < maximumMapZoom ? onZoomIn : null,
          ),
          const SizedBox(width: 36, child: Divider(height: 1)),
          _MapZoomButton(
            key: mapZoomOutButtonKey,
            label: '지도 축소',
            icon: Icons.remove,
            onPressed: currentZoom > minimumMapZoom ? onZoomOut : null,
          ),
        ],
      ),
    );
  }
}

class _MapZoomButton extends StatelessWidget {
  const _MapZoomButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      onTap: onPressed,
      child: ExcludeSemantics(
        child: IconButton(
          onPressed: onPressed,
          tooltip: label,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          icon: Icon(icon),
        ),
      ),
    );
  }
}

class _LiveRegionMessage extends StatelessWidget {
  const _LiveRegionMessage({required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: ExcludeSemantics(child: child),
    );
  }
}

class _ScreenReaderStatus extends StatelessWidget {
  const _ScreenReaderStatus({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        container: true,
        liveRegion: true,
        label: message,
        child: const SizedBox(width: 1, height: 1),
      ),
    );
  }
}

Set<Marker> buildStoreMarkers(
  List<StoreLocation> stores,
  ValueChanged<StoreLocation> onSelected,
) {
  return stores.map((store) {
    return Marker(
      markerId: MarkerId(store.id),
      clusterManagerId: storeMarkerClusterManagerId,
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
                  subtitle: Text(
                    '${store.address}\n'
                    '${BurgerStyle.parse(store.burgerStyle).displayLabel}',
                  ),
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
    return const Center(
      child: _LiveRegionMessage(
        message: '공개 매장을 불러오는 중입니다.',
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class MissingSupabaseConfigView extends StatelessWidget {
  const MissingSupabaseConfigView({super.key});

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
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            _LiveRegionMessage(
              message: '서비스 설정을 확인할 수 없습니다.',
              child: Text(
                '서비스 설정을 확인할 수 없습니다.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
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
            _LiveRegionMessage(
              message: '현재 공개된 매장이 없습니다.',
              child: Text(
                '현재 공개된 매장이 없습니다.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
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
            _LiveRegionMessage(
              message: '공개 매장 정보를 불러오지 못했습니다.',
              child: Text(
                '공개 매장 정보를 불러오지 못했습니다.',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
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
      child: Center(
        child: _LiveRegionMessage(
          message: '지도를 불러오는 중입니다.',
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class MapErrorView extends StatelessWidget {
  const MapErrorView({
    super.key,
    required this.error,
    this.showDiagnostics = false,
  });

  final Object error;
  final bool showDiagnostics;

  @override
  Widget build(BuildContext context) {
    final message = showDiagnostics
        ? '지도를 불러오지 못했습니다.\n$error'
        : '지도를 불러오지 못했습니다.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _LiveRegionMessage(message: message, child: Text(message)),
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
