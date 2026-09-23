import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../info/presentation/app_info_screen.dart';
import '../../favorites/application/favorite_store_ids_controller.dart';
import '../../favorites/data/shared_preferences_favorite_store_ids_store.dart';
import '../../favorites/domain/favorite_store_ids_store.dart';
import '../../location/application/current_location_controller.dart';
import '../../location/data/geolocator_current_location_service.dart';
import '../../location/domain/current_location_service.dart';
import '../../menu/domain/menu_repository.dart';
import '../../stores/application/public_store_controller.dart';
import '../../stores/data/external_uri_launcher.dart';
import '../../stores/data/itaewon_store_locations.dart';
import '../../stores/data/staging_store_locations_loader.dart';
import '../../stores/data/supabase_store_locations_loader.dart';
import '../../stores/domain/burger_style.dart';
import '../../stores/domain/store_distance.dart';
import '../../stores/domain/store_location.dart';
import '../../stores/domain/store_search.dart';
import '../../stores/domain/store_region.dart';
import '../../stores/presentation/region_selection_screen.dart';
import '../../stores/presentation/store_detail_screen.dart';
import 'store_preview_card.dart';
import 'store_list_panel.dart';

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
typedef CurrentLocationClock = DateTime Function();

const storeSearchFieldKey = ValueKey<String>('store-search-field');
const explorerMapTabKey = ValueKey<String>('explorer-map-tab');
const explorerListTabKey = ValueKey<String>('explorer-list-tab');
const storeSearchClearButtonKey = ValueKey<String>('store-search-clear-button');
const storeSearchResultsKey = ValueKey<String>('store-search-results');
const burgerStyleAllFilterKey = ValueKey<String>('burger-style-filter-all');
const favoritesOnlyFilterKey = ValueKey<String>('favorites-only-filter');
const regionFilterButtonKey = ValueKey<String>('region-filter-button');
const favoritesRetryButtonKey = ValueKey<String>('favorites-retry-button');
const favoritesSaveRetryButtonKey = ValueKey<String>(
  'favorites-save-retry-button',
);
const storeDataRefreshButtonKey = ValueKey<String>('store-data-refresh-button');
const storeDataRefreshingViewKey = ValueKey<String>(
  'store-data-refreshing-view',
);
const nearbySortFilterKey = ValueKey<String>('nearby-sort-filter');
const mapZoomInButtonKey = ValueKey<String>('map-zoom-in-button');
const mapZoomOutButtonKey = ValueKey<String>('map-zoom-out-button');
const currentLocationButtonKey = ValueKey<String>('current-location-button');
const appInfoButtonKey = ValueKey<String>('app-info-button');
const logoutButtonKey = ValueKey<String>('logout-button');
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
    this.storeLoadTimeout = defaultSupabaseStoreLoadTimeout,
    this.storeRefreshInterval = defaultPublicStoreRefreshInterval,
    this.storeClock,
    this.storeRefreshScheduler,
    this.currentLocationClock,
    this.maximumCurrentLocationAge = const Duration(minutes: 2),
    this.currentLocationTimeout = const Duration(seconds: 10),
    this.mapCameraTimeout = const Duration(seconds: 10),
    this.onSignOut,
    this.menuRepository,
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
  final Duration storeLoadTimeout;
  final Duration storeRefreshInterval;
  final PublicStoreClock? storeClock;
  final PublicStoreRefreshScheduler? storeRefreshScheduler;
  final CurrentLocationClock? currentLocationClock;
  final Duration maximumCurrentLocationAge;
  final Duration currentLocationTimeout;
  final Duration mapCameraTimeout;
  final Future<void> Function()? onSignOut;
  final MenuRepository? menuRepository;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const _pilotCameraPosition = CameraPosition(
    target: LatLng(37.53415, 126.99007),
    zoom: 16,
  );

  GoogleMapController? _mapController;
  Completer<void> _cameraInterruption = Completer<void>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  late final FavoriteStoreIdsController _favoritesController;
  late final PublicStoreController? _publicStoresController;
  late final CurrentLocationService _currentLocationService;
  late final ClusterManager _storeMarkerClusterManager;
  StoreLocation? _selectedStore;
  BurgerStyle? _selectedBurgerStyle;
  bool _allStoresSelected = false;
  StoreRegionFilter? _selectedRegionFilter;
  bool _regionPickerOpen = false;
  // View projection of the existing store owner, never an independent cache.
  final _regionSnapshots = ValueNotifier<List<StoreLocation>?>(null);
  int _nearbySelectionGeneration = 0;
  late final CurrentLocationController _locationController;
  bool _restoreLocationOnResume = false;
  bool _restoreNearbyOnResume = false;
  int _locationUiGeneration = 0;
  CurrentLocation? get _currentLocation => _locationController.location;
  String _searchQuery = '';
  bool _favoritesOnly = false;
  bool _nearbySortEnabled = false;
  bool get _isMapReady => _mapController != null;
  bool _isChangingZoom = false;
  bool _isMovingToCluster = false;
  bool get _isRequestingCurrentLocation => _locationController.loading;
  bool _isCurrentLocationEnabled = false;
  String _cameraStatus = '카메라 이동 대기 중';
  CameraPosition _initialCameraPosition = _pilotCameraPosition;
  CameraPosition _lastCameraPosition = _pilotCameraPosition;
  List<StoreLocation>? _stores;
  Object? _storeLoadError;
  Object? _mapError;
  bool _hasLoadedStores = false;
  bool _enteredBackground = false;
  bool _showList = false;

  List<StoreLocation> get _filteredStores {
    final filtered = filterStoreLocations(
      _visiblePublicStores ?? const <StoreLocation>[],
      _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
      regionFilter: _selectedRegionFilter,
    );
    final location = _freshCurrentLocation;
    return _nearbySortEnabled && location != null
        ? sortStoreLocationsByDistance(
            filtered,
            fromLatitude: location.latitude,
            fromLongitude: location.longitude,
          )
        : filtered;
  }

  Set<String> get _favoriteStoreIds => _favoritesController.storeIds;
  bool get _favoritesLoaded => _favoritesController.isReady;
  DateTime get _locationNow =>
      (widget.currentLocationClock ?? DateTime.now)().toUtc();
  CurrentLocation? get _freshCurrentLocation {
    final location = _currentLocation;
    return location != null &&
            location.isFreshAt(_locationNow, widget.maximumCurrentLocationAge)
        ? location
        : null;
  }

  List<StoreLocation>? get _visiblePublicStores {
    final controller = _publicStoresController;
    return controller == null ? _stores : controller.stores;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storeMarkerClusterManager = ClusterManager(
      clusterManagerId: storeMarkerClusterManagerId,
      onClusterTap: _handleClusterTap,
    );
    widget.onClusterManagerReady?.call(_storeMarkerClusterManager);
    _favoritesController = FavoriteStoreIdsController(
      widget.favoriteStoreIdsStore ?? SharedPreferencesFavoriteStoreIdsStore(),
    )..addListener(_handleFavoritesChanged);
    _currentLocationService =
        widget.currentLocationService ?? GeolocatorCurrentLocationService();
    _locationController = CurrentLocationController(
      _currentLocationService,
      clock: widget.currentLocationClock,
      maximumAge: widget.maximumCurrentLocationAge,
      requestTimeout: widget.currentLocationTimeout,
    )..addListener(_handleLocationChanged);
    _publicStoresController = _createPublicStoresController()
      ?..addListener(_handlePublicStoresChanged);
    _mapError = widget.initialMapError;
    unawaited(_favoritesController.initialize());
    _initializeStores();
  }

  void _initializeStores() {
    if (kReleaseMode) {
      if (widget.config.hasSupabaseConfiguration) {
        unawaited(_publicStoresController?.initialize());
      }
      return;
    }

    switch (widget.config.effectiveStoreDataMode) {
      case StoreDataMode.pilot:
        _applyLoadedStores(itaewonStoreLocations);
      case StoreDataMode.staging:
        _loadStagingStores();
      case StoreDataMode.supabase:
        if (widget.config.hasSupabaseConfiguration) {
          unawaited(_publicStoresController?.initialize());
        }
    }
  }

  PublicStoreController? _createPublicStoresController() {
    if (!widget.config.usesSupabaseStoreData ||
        !widget.config.hasSupabaseConfiguration) {
      return null;
    }
    return PublicStoreController(
      () {
        final loader = widget.supabaseStoreLoader;
        if (loader == null) {
          throw const SupabaseStoreLoadException();
        }
        return loader();
      },
      requestTimeout: widget.storeLoadTimeout,
      refreshInterval: widget.storeRefreshInterval,
      clock: widget.storeClock,
      scheduler: widget.storeRefreshScheduler,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _publicStoresController;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (!_enteredBackground) {
          _enteredBackground = true;
          _interruptCameraMoves();
          controller?.enterBackground();
          _restoreLocationOnResume =
              _currentLocation != null ||
              _isRequestingCurrentLocation ||
              _nearbySortEnabled;
          _restoreNearbyOnResume = _nearbySortEnabled;
          ++_locationUiGeneration;
          _locationController.enterBackground();
        }
      case AppLifecycleState.resumed:
        if (_enteredBackground) {
          _enteredBackground = false;
          unawaited(controller?.enterForeground());
          _locationController.enterForeground();
          unawaited(_revalidateLocationAfterResume());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraInterruption.complete();
    _mapController = null;
    ++_locationUiGeneration;
    _locationController
      ..removeListener(_handleLocationChanged)
      ..dispose();
    _publicStoresController
      ?..removeListener(_handlePublicStoresChanged)
      ..dispose();
    _favoritesController
      ..removeListener(_handleFavoritesChanged)
      ..dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _listScrollController.dispose();
    _regionSnapshots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '버거맵 코리아',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.onSignOut != null)
            IconButton(
              key: logoutButtonKey,
              tooltip: '로그아웃',
              icon: const Icon(Icons.logout),
              onPressed: _confirmSignOut,
            ),
          IconButton(
            key: appInfoButtonKey,
            tooltip: '정보·지원',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AppInfoScreen(
                  supportUrl: widget.config.supportUrl,
                  privacyPolicyUrl: widget.config.privacyPolicyUrl,
                  operatorName: widget.config.operatorName,
                ),
              ),
            ),
          ),
          if (_publicStoresController?.loadState == PublicStoreLoadState.ready)
            IconButton(
              key: storeDataRefreshButtonKey,
              onPressed: _loadSupabaseStores,
              tooltip: '공개 매장 새로고침',
              icon: const Icon(Icons.refresh),
            ),
          if (widget.config.showsDevelopmentDiagnostics)
            Padding(
              padding: EdgeInsets.only(
                right: _publicStoresController == null ? 12 : 4,
              ),
              child: Center(
                child:
                    MediaQuery.sizeOf(context).width < 600 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20
                    ? Tooltip(
                        message: '기술 검증 · ${widget.config.environmentLabel}',
                        child: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.science_outlined),
                        ),
                      )
                    : Chip(
                        label: Text(
                          '기술 검증 · ${widget.config.environmentLabel}',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_favoritesController.loadState ==
                    FavoriteStoreIdsLoadState.loadError ||
                _favoritesController.hasSaveErrors)
              _buildFavoritesFailureNotice(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '용산구 우선',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: _viewTab(
                      false,
                      explorerMapTabKey,
                      '지도',
                      Icons.map_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _viewTab(true, explorerListTabKey, '목록', Icons.list),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Keep the native surface mounted across data refreshes and
                  // view changes. An invalid snapshot always supplies no markers.
                  Offstage(
                    offstage: _showList || _visiblePublicStores == null,
                    child: TickerMode(
                      enabled: !_showList && _visiblePublicStores != null,
                      child: _buildPersistentMap(),
                    ),
                  ),
                  _buildBody(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSignOut() async {
    final signOut = widget.onSignOut;
    if (signOut == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('이 기기에서 로그아웃할까요? 즐겨찾기는 그대로 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed == true) await signOut();
  }

  Widget _viewTab(bool list, Key key, String label, IconData icon) {
    return Semantics(
      selected: _showList == list,
      child: OutlinedButton.icon(
        key: key,
        onPressed: () {
          _searchFocusNode.unfocus();
          setState(() => _showList = list);
        },
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          backgroundColor: _showList == list
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  Widget _buildFavoritesFailureNotice() {
    final loadFailed =
        _favoritesController.loadState == FavoriteStoreIdsLoadState.loadError;
    return Semantics(
      liveRegion: true,
      child: MaterialBanner(
        content: Text(
          loadFailed
              ? '즐겨찾기를 불러오지 못했습니다. 저장된 목록은 변경하지 않았습니다.'
              : '즐겨찾기 변경을 저장하지 못했습니다. 이전 저장 상태를 유지합니다.',
        ),
        actions: [
          TextButton(
            key: loadFailed
                ? favoritesRetryButtonKey
                : favoritesSaveRetryButtonKey,
            onPressed: _favoritesController.isSavingAny
                ? null
                : loadFailed
                ? _favoritesController.retry
                : _favoritesController.retryFailedSaves,
            child: Text(loadFailed ? '다시 시도' : '다시 저장'),
          ),
        ],
      ),
    );
  }

  Widget _buildPersistentMap() {
    if (!_hasLoadedStores ||
        !widget.config.hasGoogleMapsApiKey ||
        _mapError != null) {
      return const SizedBox.shrink();
    }
    final markers = buildStoreMarkers(_filteredStores, _selectStore);
    final builder = widget.mapSurfaceBuilder;
    if (builder != null) {
      return builder(markers, _handleMapTap);
    }
    return GoogleMap(
      initialCameraPosition: _initialCameraPosition,
      markers: markers,
      clusterManagers: <ClusterManager>{_storeMarkerClusterManager},
      onMapCreated: _handleMapCreated,
      onTap: _handleMapTap,
      onCameraMoveStarted: () {
        if (mounted) setState(() => _cameraStatus = '카메라 이동 중');
      },
      onCameraMove: (position) {
        if (mounted) _lastCameraPosition = position;
      },
      onCameraIdle: () {
        if (mounted) setState(() => _cameraStatus = '카메라 이동 완료');
      },
      myLocationEnabled: _isCurrentLocationEnabled,
      myLocationButtonEnabled: false,
      mapToolbarEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (widget.config.usesSupabaseStoreData &&
        !widget.config.hasSupabaseConfiguration) {
      return const MissingSupabaseConfigView();
    }

    final publicStoresController = _publicStoresController;
    if (publicStoresController != null) {
      switch (publicStoresController.loadState) {
        case PublicStoreLoadState.initialLoading:
          return _scrollableStatus(const StoreDataLoadingView());
        case PublicStoreLoadState.refreshing:
          return _scrollableStatus(const StoreDataRefreshingView());
        case PublicStoreLoadState.error:
          return _scrollableStatus(
            StoreDataErrorView(onRetry: _loadSupabaseStores),
          );
        case PublicStoreLoadState.empty:
          return _scrollableStatus(
            StoreDataEmptyView(onRefresh: _loadSupabaseStores),
          );
        case PublicStoreLoadState.ready:
          break;
      }
    }

    if (_storeLoadError != null) {
      return MapErrorView(
        error: _storeLoadError!,
        showDiagnostics: widget.config.showsDevelopmentDiagnostics,
      );
    }

    final stores = _visiblePublicStores;
    if (stores == null) {
      return const StoreDataLoadingView();
    }

    final visibleStores = _filteredStores;
    if (_showList) {
      return StoreListPanel(
        controller: _listScrollController,
        searchPanel: _buildSearchPanel(
          stores,
          visibleStores,
          showResults: false,
        ),
        stores: visibleStores,
        favoriteIds: _favoriteStoreIds,
        favoritesReady: _favoritesLoaded,
        emptyMessage:
            _favoritesOnly &&
                normalizeStoreSearchText(_searchQuery).isEmpty &&
                _selectedBurgerStyle == null &&
                _selectedRegionFilter == null
            ? '즐겨찾기한 공개 매장이 없습니다.'
            : '검색 결과가 없습니다.',
        onReset: _resetCriteria,
        onOpen: _openStoreDetails,
        onShowOnMap: _showStoreOnMap,
      );
    }

    if (!widget.config.hasGoogleMapsApiKey) {
      return widget.config.showsDevelopmentDiagnostics
          ? MissingApiKeyView(stores: stores)
          : const MapErrorView(error: 'map unavailable');
    }

    if (_mapError != null) {
      return MapErrorView(error: _mapError!, showDiagnostics: false);
    }

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
        if (!_isMapReady && mapSurfaceBuilder == null)
          const IgnorePointer(child: _MapLoadingOverlay()),
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
              _buildSearchPanel(stores, visibleStores),
              if (widget.config.showsDevelopmentDiagnostics &&
                  normalizeStoreSearchText(_searchQuery).isEmpty &&
                  _selectedBurgerStyle == null &&
                  _selectedRegionFilter == null &&
                  !_allStoresSelected &&
                  !_favoritesOnly &&
                  !_nearbySortEnabled) ...[
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

  Widget _buildSearchPanel(
    List<StoreLocation> stores,
    List<StoreLocation> results, {
    bool showResults = true,
  }) {
    return _StoreSearchPanel(
      controller: _searchController,
      focusNode: _searchFocusNode,
      query: _searchQuery,
      results: results,
      availableStyles: availableBurgerStyles(stores),
      selectedBurgerStyle: _selectedBurgerStyle,
      allStoresSelected: _allStoresSelected,
      selectedRegion: _selectedRegionFilter,
      unknownRegionCount: stores.where((store) => store.region == null).length,
      onRegionPressed: _showRegionSelection,
      favoritesOnly: _favoritesOnly,
      favoritesLoaded: _favoritesLoaded,
      nearbySortEnabled: _nearbySortEnabled,
      locationNotice: _currentLocation == null
          ? null
          : _currentLocation!.hasWideAccuracy
          ? '위치 오차가 커서 가까운 순이 정확하지 않을 수 있습니다.'
          : _currentLocation!.isApproximate
          ? '대략적인 위치 기준입니다. 가까운 매장 간 순서는 다를 수 있습니다.'
          : _currentLocation!.precision == CurrentLocationPrecision.unknown
          ? '위치 정확도를 확인할 수 없습니다. 가까운 순은 참고용입니다.'
          : null,
      hasCurrentLocation: _currentLocation != null,
      isRequestingCurrentLocation: _isRequestingCurrentLocation,
      onChanged: _handleSearchChanged,
      onClear: _clearSearch,
      onSelected: _selectSearchResult,
      onBurgerStyleSelected: _handleBurgerStyleChanged,
      onAllStoresChanged: _handleAllStoresChanged,
      onFavoritesOnlyChanged: _handleFavoritesOnlyChanged,
      onNearbySortChanged: _handleNearbySortChanged,
      showResults: showResults,
    );
  }

  Widget _scrollableStatus(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: child,
        ),
      ),
    );
  }

  void _resetCriteria({bool showAll = false}) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchQuery = '';
      _selectedBurgerStyle = null;
      _allStoresSelected = showAll;
      _selectedRegionFilter = null;
      _favoritesOnly = false;
      _nearbySortEnabled = false;
      _nearbySelectionGeneration++;
      _restoreNearbyOnResume = false;
      _selectedStore = null;
    });
  }

  void _handleAllStoresChanged(bool selected) {
    if (selected) {
      _resetCriteria(showAll: true);
    } else {
      setState(() => _allStoresSelected = false);
    }
  }

  Future<void> _showRegionSelection() async {
    if (_regionPickerOpen || !mounted) return;
    _regionPickerOpen = true;
    _searchFocusNode.unfocus();
    try {
      final result = await Navigator.of(context).push<RegionSelectionResult>(
        MaterialPageRoute<RegionSelectionResult>(
          builder: (_) => RegionSelectionScreen(
            storesListenable: _regionSnapshots,
            initialSelection: _selectedRegionFilter,
          ),
        ),
      );
      if (!mounted || result == null) return;
      setState(() {
        _selectedRegionFilter = result.selection;
        _allStoresSelected = false;
        if (_selectedStore != null &&
            !_filteredStores.any((store) => store.id == _selectedStore!.id)) {
          _selectedStore = null;
        }
      });
    } finally {
      _regionPickerOpen = false;
    }
  }

  Future<void> _showStoreOnMap(StoreLocation store) async {
    setState(() => _showList = false);
    await _selectSearchResult(store);
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

  Future<void> _loadSupabaseStores() {
    return _publicStoresController?.refresh() ?? Future<void>.value();
  }

  void _handlePublicStoresChanged() {
    if (!mounted) {
      return;
    }
    final stores = _publicStoresController?.stores;
    if (stores == null) {
      _regionSnapshots.value = null;
      setState(() {
        _selectedStore = null;
      });
      return;
    }
    _applyLoadedStores(stores);
  }

  void _handleFavoritesChanged() {
    if (!mounted) {
      return;
    }
    final visibleStoreIds = _visibleStoreIds(
      query: _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesLoaded && _favoritesOnly,
    );
    setState(() {
      if (!_favoritesLoaded) {
        _favoritesOnly = false;
      }
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _selectStore(StoreLocation store) {
    if (!mounted) return;
    // A queued native marker callback may refer to an earlier snapshot.
    for (final current in _filteredStores) {
      if (current.id == store.id) {
        setState(() => _selectedStore = current);
        return;
      }
    }
  }

  void _handleMapTap(LatLng _) {
    if (!mounted) return;
    setState(() {
      _selectedStore = null;
    });
  }

  void _handleSearchChanged(String query) {
    final visibleStoreIds = _visibleStoreIds(
      query: query,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
    );

    setState(() {
      _searchQuery = query;
      if (normalizeStoreSearchText(query).isNotEmpty) {
        _allStoresSelected = false;
      }
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _handleBurgerStyleChanged(BurgerStyle? burgerStyle) {
    final visibleStoreIds = _visibleStoreIds(
      query: _searchQuery,
      burgerStyle: burgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: _favoritesOnly,
    );

    setState(() {
      _selectedBurgerStyle = burgerStyle;
      _allStoresSelected = false;
      if (_selectedStore != null &&
          !visibleStoreIds.contains(_selectedStore!.id)) {
        _selectedStore = null;
      }
    });
  }

  void _handleFavoritesOnlyChanged(bool favoritesOnly) {
    if (!_favoritesLoaded) {
      return;
    }
    final visibleStoreIds = _visibleStoreIds(
      query: _searchQuery,
      burgerStyle: _selectedBurgerStyle,
      favoriteStoreIds: _favoriteStoreIds,
      favoritesOnly: favoritesOnly,
    );

    setState(() {
      _favoritesOnly = favoritesOnly;
      if (favoritesOnly) _allStoresSelected = false;
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
    if (!mounted ||
        _enteredBackground ||
        !_visibleStoreIds(
          query: _searchQuery,
          burgerStyle: _selectedBurgerStyle,
          favoriteStoreIds: _favoriteStoreIds,
          favoritesOnly: _favoritesOnly,
        ).contains(store.id)) {
      return;
    }
    _searchFocusNode.unfocus();
    _selectStore(store);

    try {
      final storeCameraMover = widget.storeCameraMover;
      if (storeCameraMover != null) {
        await _moveCamera(() => storeCameraMover(store));
        return;
      }
      final controller = _mapController;
      if (controller == null) {
        return;
      }
      await _moveCamera(
        () => controller.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(store.latitude, store.longitude),
            16,
          ),
        ),
      );
    } on Object {
      _showMapMovementError();
    }
  }

  void _showMapMovementError() {
    if (!mounted || _enteredBackground) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('지도를 이동하지 못했습니다. 목록에서 매장 상세를 볼 수 있습니다.')),
    );
  }

  Future<void> _handleClusterTap(Cluster cluster) async {
    if (!mounted || _enteredBackground || _isMovingToCluster) {
      return;
    }
    final visibleIds = _filteredStores
        .map((store) => MarkerId(store.id))
        .toSet();
    if (cluster.markerIds.isEmpty ||
        !visibleIds.containsAll(cluster.markerIds)) {
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
        await _moveCamera(
          () => clusterCameraMover(cluster.bounds, clusterBoundsPadding),
        );
        return;
      }
      final controller = _mapController;
      if (controller == null) {
        return;
      }
      await _moveCamera(
        () => controller.animateCamera(
          CameraUpdate.newLatLngBounds(cluster.bounds, clusterBoundsPadding),
        ),
      );
    } on Object {
      _showMapMovementError();
    } finally {
      _isMovingToCluster = false;
    }
  }

  void _handleLocationChanged() {
    if (!mounted) return;
    final enabled = _locationController.location != null && !_enteredBackground;
    final changed = enabled != _isCurrentLocationEnabled;
    setState(() {
      _isCurrentLocationEnabled = enabled;
      if (!enabled && !_locationController.loading) _nearbySortEnabled = false;
    });
    if (changed) widget.onMyLocationEnabledChanged?.call(enabled);
  }

  Future<CurrentLocation?> _requestCurrentLocation() => _resolveCurrentLocation(
    moveCamera: true,
    requestPermissionIfDenied: true,
  );

  Future<CurrentLocation?> _resolveCurrentLocation({
    required bool moveCamera,
    required bool requestPermissionIfDenied,
  }) async {
    if (!mounted || _enteredBackground || _isRequestingCurrentLocation) {
      return null;
    }
    final generation = ++_locationUiGeneration;
    final location = await _locationController.request(
      allowPermissionPrompt: requestPermissionIfDenied,
    );
    if (!mounted || _enteredBackground || generation != _locationUiGeneration) {
      return null;
    }
    if (location == null) {
      final failure = _locationController.failure;
      _showCurrentLocationMessage(switch (failure) {
        CurrentLocationFailure.serviceDisabled =>
          '위치 서비스가 꺼져 있습니다. 기기 설정에서 위치 서비스를 켠 뒤 다시 시도해 주세요.',
        CurrentLocationFailure.deniedForever =>
          '현재 위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해 주세요.',
        CurrentLocationFailure.denied =>
          '현재 위치 권한이 허용되지 않았습니다. 필요할 때 다시 요청할 수 있습니다.',
        _ => '현재 위치를 가져오지 못했습니다. 잠시 후 다시 시도해 주세요.',
      }, showSettingsAction: failure == CurrentLocationFailure.deniedForever);
      return null;
    }
    if (!moveCamera) return location;
    try {
      final target = LatLng(location.latitude, location.longitude);
      final mover = widget.currentLocationCameraMover;
      if (mover != null) {
        await _moveCamera(
          () => mover(target, currentLocationZoom),
          timeout: widget.currentLocationTimeout,
        );
      } else if (_mapController case final controller?) {
        if (!mounted ||
            _enteredBackground ||
            generation != _locationUiGeneration) {
          return null;
        }
        await _moveCamera(
          () => controller.animateCamera(
            CameraUpdate.newLatLngZoom(target, currentLocationZoom),
          ),
          timeout: widget.currentLocationTimeout,
        );
      }
    } on Object {
      if (mounted &&
          !_enteredBackground &&
          generation == _locationUiGeneration) {
        _showCurrentLocationMessage('현재 위치로 지도를 이동하지 못했습니다. 잠시 후 다시 시도해 주세요.');
      }
    }
    return mounted && !_enteredBackground && generation == _locationUiGeneration
        ? _locationController.location
        : null;
  }

  Future<void> _handleNearbySortChanged(bool enabled) async {
    if (!mounted || _enteredBackground) return;
    final generation = ++_nearbySelectionGeneration;
    if (!enabled) {
      setState(() => _nearbySortEnabled = false);
      return;
    }
    final location = _freshCurrentLocation ?? await _requestCurrentLocation();
    if (!mounted ||
        _enteredBackground ||
        generation != _nearbySelectionGeneration ||
        location == null ||
        _locationController.location == null) {
      return;
    }
    setState(() {
      _nearbySortEnabled = true;
      _allStoresSelected = false;
    });
  }

  Future<void> _revalidateLocationAfterResume() async {
    if (!_restoreLocationOnResume) return;
    final restoreNearby = _restoreNearbyOnResume;
    final generation = _nearbySelectionGeneration;
    _restoreLocationOnResume = false;
    _restoreNearbyOnResume = false;
    final location = await _resolveCurrentLocation(
      moveCamera: false,
      requestPermissionIfDenied: false,
    );
    if (mounted &&
        !_enteredBackground &&
        generation == _nearbySelectionGeneration &&
        location != null &&
        restoreNearby) {
      setState(() => _nearbySortEnabled = true);
    }
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
    if (!mounted || _enteredBackground || _isChangingZoom) {
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
        if (!await _moveCamera(() => mapZoomMover(targetZoom.toDouble()))) {
          return;
        }
      } else {
        final controller = _mapController;
        if (controller == null) {
          return;
        }
        if (!await _moveCamera(
          () => controller.animateCamera(
            CameraUpdate.zoomTo(targetZoom.toDouble()),
          ),
        )) {
          return;
        }
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
    } on Object {
      _showMapMovementError();
    } finally {
      if (mounted) {
        setState(() {
          _isChangingZoom = false;
        });
      }
    }
  }

  void _interruptCameraMoves() {
    _cameraInterruption.complete();
    _cameraInterruption = Completer<void>();
  }

  Future<bool> _moveCamera(
    Future<void> Function() move, {
    Duration? timeout,
  }) async {
    if (!mounted || _enteredBackground) return false;
    final interruption = _cameraInterruption;
    // End our wait on lifecycle changes; the native operation may still finish.
    // Racing before timeout also cancels its timer when the screen is disposed.
    await Future.any<void>([
      Future<void>.sync(move),
      interruption.future,
    ]).timeout(timeout ?? widget.mapCameraTimeout);
    return mounted && !_enteredBackground && !interruption.isCompleted;
  }

  Future<void> _openStoreDetails(StoreLocation store) async {
    final externalUriLauncher = widget.externalUriLauncher;
    final publicStoresController = _publicStoresController;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => externalUriLauncher == null
            ? StoreDetailScreen(
                store: store,
                menuRepository: widget.menuRepository,
                isFavorite: _favoriteStoreIds.contains(store.id),
                onFavoriteChanged: (isFavorite) =>
                    _setStoreFavorite(store, isFavorite),
                favoriteState: _favoritesController,
                isFavoriteProvider: () =>
                    _favoritesController.storeIds.contains(store.id),
                canChangeFavoriteProvider: () =>
                    _favoritesController.isReady &&
                    !_favoritesController.isSaving(store.id),
                publicStoreState: publicStoresController,
                storeProvider: publicStoresController == null
                    ? null
                    : () => publicStoresController.storeById(store.id),
                unavailableMessageProvider: _publicStoreUnavailableMessage,
              )
            : StoreDetailScreen(
                store: store,
                menuRepository: widget.menuRepository,
                externalUriLauncher: externalUriLauncher,
                isFavorite: _favoriteStoreIds.contains(store.id),
                onFavoriteChanged: (isFavorite) =>
                    _setStoreFavorite(store, isFavorite),
                favoriteState: _favoritesController,
                isFavoriteProvider: () =>
                    _favoritesController.storeIds.contains(store.id),
                canChangeFavoriteProvider: () =>
                    _favoritesController.isReady &&
                    !_favoritesController.isSaving(store.id),
                publicStoreState: publicStoresController,
                storeProvider: publicStoresController == null
                    ? null
                    : () => publicStoresController.storeById(store.id),
                unavailableMessageProvider: _publicStoreUnavailableMessage,
              ),
      ),
    );
  }

  Future<void> _setStoreFavorite(StoreLocation store, bool isFavorite) async {
    await _favoritesController.setFavorite(store.id, isFavorite);
  }

  String _publicStoreUnavailableMessage() {
    return switch (_publicStoresController?.loadState) {
      PublicStoreLoadState.initialLoading ||
      PublicStoreLoadState.refreshing => '매장 정보를 새로 확인하고 있습니다.',
      PublicStoreLoadState.error => '매장 정보를 불러오지 못했습니다. 지도에서 다시 시도해 주세요.',
      _ => '이 매장은 더 이상 공개 목록에서 제공되지 않습니다.',
    };
  }

  void _applyLoadedStores(List<StoreLocation> stores) {
    final cameraPosition = cameraPositionForStores(stores);
    final selectedStoreId = _selectedStore?.id;
    StoreLocation? selectedStore;
    for (final store in stores) {
      if (store.id == selectedStoreId) {
        selectedStore = store;
        break;
      }
    }
    setState(() {
      if (_publicStoresController == null) {
        _stores = stores;
      }
      _selectedBurgerStyle = validBurgerStyleSelection(
        _selectedBurgerStyle,
        stores,
      );
      _selectedStore = selectedStore;
      if (_selectedStore != null &&
          !_filteredStores.any((store) => store.id == _selectedStore!.id)) {
        _selectedStore = null;
      }
      if (!_hasLoadedStores && stores.isNotEmpty) {
        _initialCameraPosition = cameraPosition;
        _lastCameraPosition = cameraPosition;
        _hasLoadedStores = true;
      }
    });
    _regionSnapshots.value = stores;
  }

  Set<String> _visibleStoreIds({
    required String query,
    required BurgerStyle? burgerStyle,
    required Set<String> favoriteStoreIds,
    required bool favoritesOnly,
  }) {
    return filterStoreLocations(
      _visiblePublicStores ?? const <StoreLocation>[],
      query,
      burgerStyle: burgerStyle,
      favoriteStoreIds: favoriteStoreIds,
      favoritesOnly: favoritesOnly,
      regionFilter: _selectedRegionFilter,
    ).map((store) => store.id).toSet();
  }

  void _handleMapCreated(GoogleMapController controller) {
    if (!mounted) return;
    if (identical(_mapController, controller)) return;
    _interruptCameraMoves();

    setState(() {
      _mapController = controller;
      // Controller creation does not establish successful tile authentication.
      _cameraStatus = '지도 컨트롤 준비됨';
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
    required this.allStoresSelected,
    required this.selectedRegion,
    required this.unknownRegionCount,
    required this.onRegionPressed,
    required this.favoritesOnly,
    required this.favoritesLoaded,
    required this.nearbySortEnabled,
    required this.hasCurrentLocation,
    required this.isRequestingCurrentLocation,
    required this.onChanged,
    required this.onClear,
    required this.onSelected,
    required this.onBurgerStyleSelected,
    required this.onAllStoresChanged,
    required this.onFavoritesOnlyChanged,
    required this.onNearbySortChanged,
    this.locationNotice,
    this.showResults = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final List<StoreLocation> results;
  final List<BurgerStyle> availableStyles;
  final BurgerStyle? selectedBurgerStyle;
  final bool allStoresSelected;
  final StoreRegionFilter? selectedRegion;
  final int unknownRegionCount;
  final VoidCallback onRegionPressed;
  final bool favoritesOnly;
  final bool favoritesLoaded;
  final bool nearbySortEnabled;
  final bool hasCurrentLocation;
  final bool isRequestingCurrentLocation;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<StoreLocation> onSelected;
  final ValueChanged<BurgerStyle?> onBurgerStyleSelected;
  final ValueChanged<bool> onAllStoresChanged;
  final ValueChanged<bool> onFavoritesOnlyChanged;
  final ValueChanged<bool> onNearbySortChanged;
  final bool showResults;
  final String? locationNotice;

  @override
  Widget build(BuildContext context) {
    final hasQuery = normalizeStoreSearchText(query).isNotEmpty;
    final textScaler = MediaQuery.textScalerOf(context);
    // Keep both controls at least 48dp high, while letting 200% text scale
    // increase their height instead of clipping labels or typed search text.
    final searchHeight = math.max(48.0, textScaler.scale(16) + 32);
    final filtersHeight = math.max(48.0, textScaler.scale(16) + 28);
    final hasActiveCriteria =
        allStoresSelected ||
        hasQuery ||
        selectedBurgerStyle != null ||
        selectedRegion != null ||
        favoritesOnly ||
        nearbySortEnabled;
    final emptyResultsMessage =
        favoritesOnly &&
            !hasQuery &&
            selectedBurgerStyle == null &&
            selectedRegion == null
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
          elevation: 2,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          color: Theme.of(context).colorScheme.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '매장명 또는 주소 검색',
                child: SizedBox(
                  height: searchHeight,
                  child: TextField(
                    key: storeSearchFieldKey,
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hint: const ExcludeSemantics(child: Text('매장명 또는 주소 검색')),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
              const Divider(height: 1),
              SizedBox(
                height: filtersHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: availableStyles.length + 4,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
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

                    if (index == 1) {
                      return Semantics(
                        button: true,
                        selected: selectedRegion != null,
                        label: selectedRegion == null
                            ? '지역 선택'
                            : '지역 선택, ${selectedRegion!.pathLabel}',
                        onTap: onRegionPressed,
                        child: ExcludeSemantics(
                          child: FilterChip(
                            key: regionFilterButtonKey,
                            avatar: const Icon(
                              Icons.location_city_outlined,
                              size: 18,
                            ),
                            label: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                selectedRegion?.label ?? '지역',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            selected: selectedRegion != null,
                            onSelected: (_) => onRegionPressed(),
                          ),
                        ),
                      );
                    }

                    if (index == 2) {
                      final label = isRequestingCurrentLocation
                          ? '가까운 순 정렬, 현재 위치를 확인하는 중입니다.'
                          : hasCurrentLocation
                          ? '가까운 순 정렬'
                          : '가까운 순 정렬, 현재 위치가 필요합니다.';
                      return Semantics(
                        button: true,
                        enabled: !isRequestingCurrentLocation,
                        selected: nearbySortEnabled,
                        label: label,
                        onTap: isRequestingCurrentLocation
                            ? null
                            : () => onNearbySortChanged(!nearbySortEnabled),
                        child: ExcludeSemantics(
                          child: FilterChip(
                            key: nearbySortFilterKey,
                            avatar: const Icon(Icons.near_me, size: 18),
                            label: const Text('가까운 순'),
                            selected: nearbySortEnabled,
                            onSelected: isRequestingCurrentLocation
                                ? null
                                : onNearbySortChanged,
                          ),
                        ),
                      );
                    }

                    final style = index == 3
                        ? null
                        : availableStyles[index - 4];
                    final label = style?.displayLabel ?? '전체';
                    final isSelected = style == null
                        ? allStoresSelected
                        : style == selectedBurgerStyle;
                    void select(bool selected) {
                      if (style == null) {
                        onAllStoresChanged(selected);
                      } else {
                        onBurgerStyleSelected(selected ? style : null);
                      }
                    }

                    return Semantics(
                      button: true,
                      selected: isSelected,
                      label: style == null ? '공개 매장 전체 보기' : '버거 스타일 $label 필터',
                      onTap: () => select(!isSelected),
                      child: ExcludeSemantics(
                        child: ChoiceChip(
                          key: style == null
                              ? burgerStyleAllFilterKey
                              : burgerStyleFilterKey(style),
                          label: Text(label),
                          selected: isSelected,
                          onSelected: select,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (locationNotice != null)
          Semantics(liveRegion: true, child: Text(locationNotice!)),
        if (selectedRegion != null && unknownRegionCount > 0)
          Semantics(
            liveRegion: true,
            child: Text('지역 미확정 $unknownRegionCount곳은 전체에서 확인할 수 있습니다.'),
          ),
        if (showResults && hasActiveCriteria) ...[
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

    return SingleChildScrollView(
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
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
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
  const StoreDataEmptyView({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

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
            const SizedBox(height: 16),
            FilledButton.icon(
              key: storeDataRefreshButtonKey,
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('새로고침'),
            ),
          ],
        ),
      ),
    );
  }
}

class StoreDataRefreshingView extends StatelessWidget {
  const StoreDataRefreshingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: storeDataRefreshingViewKey,
      child: _LiveRegionMessage(
        message: '공개 매장 정보를 새로 확인하고 있습니다.',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('공개 매장 정보를 새로 확인하고 있습니다.'),
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
                Expanded(child: Text(status)),
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
