import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/data/external_uri_launcher.dart';
import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/staging_fixture.dart';

List<StoreLocation> buildSyntheticPublic25Stores() {
  const styles = <String>[
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'classic',
    'smash',
    'chicken',
    'chicken',
    'other',
    'other',
    'other',
    'unclassified',
    'unclassified',
    'unclassified',
    'unclassified',
    'unclassified',
  ];

  return List<StoreLocation>.generate(25, (index) {
    final number = index + 1;
    return StoreLocation(
      id: 'public-$number',
      name: 'Public Burger $number',
      address: 'Seoul Yongsan Test-road $number',
      latitude: 37.50 + index * 0.001,
      longitude: 126.90 + index * 0.001,
      burgerStyle: styles[index],
      verificationStatus: 'verified',
    );
  });
}

void main() {
  final searchableStores = <StoreLocation>[
    StoreLocation(
      id: 'alpha',
      name: 'Alpha Burger',
      address: 'Seoul Yongsan Alpha-ro 1',
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: 'smash',
      verificationStatus: 'verified',
    ),
    StoreLocation(
      id: 'beta',
      name: 'Beta Kitchen',
      address: 'Seoul Itaewon Burger-gil 2',
      latitude: 37.54,
      longitude: 127.0,
      burgerStyle: 'classic',
      verificationStatus: 'verified',
    ),
    StoreLocation(
      id: 'gamma',
      name: 'Gamma Grill',
      address: 'Seoul Hangang-daero 3',
      latitude: 37.52,
      longitude: 126.98,
      burgerStyle: '미분류',
      verificationStatus: 'verified',
    ),
  ];

  Widget testApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );
  }

  Future<void> pumpSearchableMap(
    WidgetTester tester, {
    required SupabaseStoreLoader loader,
    required StoreMapSurfaceBuilder mapSurfaceBuilder,
    StoreCameraMover? storeCameraMover,
    MapZoomMover? mapZoomMover,
    CurrentLocationCameraMover? currentLocationCameraMover,
    CurrentLocationService? currentLocationService,
    ValueChanged<bool>? onMyLocationEnabledChanged,
    ClusterCameraMover? clusterCameraMover,
    ValueChanged<ClusterManager>? onClusterManagerReady,
    ExternalUriLauncher? externalUriLauncher,
    FavoriteStoreIdsStore? favoriteStoreIdsStore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: loader,
          mapSurfaceBuilder: mapSurfaceBuilder,
          storeCameraMover: storeCameraMover,
          mapZoomMover: mapZoomMover,
          currentLocationCameraMover: currentLocationCameraMover,
          currentLocationService: currentLocationService,
          onMyLocationEnabledChanged: onMyLocationEnabledChanged,
          clusterCameraMover: clusterCameraMover,
          onClusterManagerReady: onClusterManagerReady,
          externalUriLauncher: externalUriLauncher,
          favoriteStoreIdsStore:
              favoriteStoreIdsStore ?? _MemoryFavoriteStoreIdsStore(),
        ),
      ),
    );
    await tester.pump();
  }

  test('all public store markers share the cluster manager', () {
    final markers = buildStoreMarkers(buildSyntheticPublic25Stores(), (_) {});

    expect(markers, hasLength(25));
    expect(markers.map((marker) => marker.clusterManagerId).toSet(), {
      storeMarkerClusterManagerId,
    });
  });

  test('empty visible stores create no clustered markers', () {
    final markers = buildStoreMarkers(const <StoreLocation>[], (_) {});

    expect(markers, isEmpty);
  });

  testWidgets(
    'current location requests permission only after a tap and moves the camera when allowed',
    (tester) async {
      final locationService = _FakeCurrentLocationService(
        checkedPermission: LocationPermissionStatus.denied,
        requestedPermission: LocationPermissionStatus.whileInUse,
        location: const CurrentLocation(latitude: 37.531, longitude: 126.991),
      );
      final cameraMoves = <(LatLng, double)>[];
      final myLocationEnabledChanges = <bool>[];

      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        currentLocationCameraMover: (location, zoom) async {
          cameraMoves.add((location, zoom));
        },
        onMyLocationEnabledChanged: myLocationEnabledChanges.add,
      );

      expect(locationService.checkPermissionCalls, 0);
      expect(locationService.requestPermissionCalls, 0);
      expect(locationService.currentLocationCalls, 0);

      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pumpAndSettle();

      expect(locationService.checkPermissionCalls, 1);
      expect(locationService.requestPermissionCalls, 1);
      expect(locationService.currentLocationCalls, 1);
      expect(cameraMoves, [
        (const LatLng(37.531, 126.991), currentLocationZoom),
      ]);
      expect(myLocationEnabledChanges, [true]);
    },
  );

  testWidgets(
    'denied current location permission shows guidance without moving',
    (tester) async {
      final locationService = _FakeCurrentLocationService(
        checkedPermission: LocationPermissionStatus.denied,
        requestedPermission: LocationPermissionStatus.denied,
      );
      var cameraMoveCalls = 0;

      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        currentLocationCameraMover: (location, zoom) async {
          cameraMoveCalls += 1;
        },
      );

      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('현재 위치 권한이 허용되지 않았습니다'), findsOneWidget);
      expect(cameraMoveCalls, 0);
      expect(locationService.currentLocationCalls, 0);
    },
  );

  testWidgets('permanently denied location permission offers app settings', (
    tester,
  ) async {
    final locationService = _FakeCurrentLocationService(
      checkedPermission: LocationPermissionStatus.deniedForever,
    );

    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: locationService,
      currentLocationCameraMover: (location, zoom) async {},
    );

    await tester.tap(find.byKey(currentLocationButtonKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('영구적으로 거부되었습니다'), findsOneWidget);
    expect(find.text('설정 열기'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pump();
    expect(locationService.openAppSettingsCalls, 1);
    expect(locationService.requestPermissionCalls, 0);
  });

  testWidgets(
    'disabled location services show guidance without requesting permission',
    (tester) async {
      final locationService = _FakeCurrentLocationService(
        serviceEnabled: false,
      );

      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        currentLocationCameraMover: (location, zoom) async {},
      );

      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('위치 서비스가 꺼져 있습니다'), findsOneWidget);
      expect(locationService.checkPermissionCalls, 0);
      expect(locationService.currentLocationCalls, 0);
    },
  );

  testWidgets(
    'current location errors keep the map available and show guidance',
    (tester) async {
      final locationService = _FakeCurrentLocationService(
        checkedPermission: LocationPermissionStatus.whileInUse,
        currentLocationError: StateError('synthetic location failure'),
      );
      var cameraMoveCalls = 0;

      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        currentLocationCameraMover: (location, zoom) async {
          cameraMoveCalls += 1;
        },
      );

      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('현재 위치를 가져오지 못했습니다'), findsOneWidget);
      expect(cameraMoveCalls, 0);
      expect(find.byKey(storeSearchFieldKey), findsOneWidget);
    },
  );

  testWidgets(
    'current location button prevents repeat taps and exposes its state',
    (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      final locationCompleter = Completer<CurrentLocation>();
      final locationService = _FakeCurrentLocationService(
        checkedPermission: LocationPermissionStatus.whileInUse,
        currentLocationHandler: () => locationCompleter.future,
      );

      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        currentLocationCameraMover: (location, zoom) async {},
      );

      final button = find.byKey(currentLocationButtonKey);
      final readyNode = tester.getSemantics(find.bySemanticsLabel('현재 위치로 이동'));
      expect(readyNode.flagsCollection.isButton, isTrue);
      expect(readyNode.flagsCollection.isEnabled, Tristate.isTrue);

      await tester.tap(button);
      await tester.pump();
      expect(find.bySemanticsLabel('현재 위치를 찾는 중입니다.'), findsOne);
      final loadingNode = tester.getSemantics(
        find.bySemanticsLabel('현재 위치를 찾는 중입니다.'),
      );
      expect(loadingNode.flagsCollection.isEnabled, Tristate.isFalse);

      await tester.tap(button);
      await tester.pump();
      expect(locationService.currentLocationCalls, 1);

      locationCompleter.complete(
        const CurrentLocation(latitude: 37.531, longitude: 126.991),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('현재 위치로 이동'), findsOne);
      semanticsHandle.dispose();
    },
  );

  testWidgets(
    'cluster tap fits bounds, closes preview, and ignores repeat taps',
    (tester) async {
      Set<Marker> markers = const <Marker>{};
      ClusterManager? clusterManager;
      LatLngBounds? movedBounds;
      double? movedPadding;
      var moveCalls = 0;
      final moveCompleter = Completer<void>();
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (nextMarkers, onMapTap) {
          markers = nextMarkers;
          return const ColoredBox(color: Colors.white);
        },
        clusterCameraMover: (bounds, padding) {
          moveCalls += 1;
          movedBounds = bounds;
          movedPadding = padding;
          return moveCompleter.future;
        },
        onClusterManagerReady: (manager) {
          clusterManager = manager;
        },
      );

      expect(clusterManager?.onClusterTap, isNotNull);
      markers
          .firstWhere((marker) => marker.markerId.value == 'beta')
          .onTap
          ?.call();
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsOneWidget);

      final bounds = LatLngBounds(
        southwest: const LatLng(37.52, 126.98),
        northeast: const LatLng(37.54, 127),
      );
      final cluster = Cluster(
        storeMarkerClusterManagerId,
        const <MarkerId>[MarkerId('alpha'), MarkerId('beta')],
        position: const LatLng(37.53, 126.99),
        bounds: bounds,
      );

      clusterManager!.onClusterTap!.call(cluster);
      await tester.pump();

      expect(movedBounds, bounds);
      expect(movedPadding, clusterBoundsPadding);
      expect(find.byType(StorePreviewCard), findsNothing);

      clusterManager!.onClusterTap!.call(cluster);
      await tester.pump();
      expect(moveCalls, 1);

      moveCompleter.complete();
      await tester.pump();
    },
  );

  testWidgets('does not show preview card when no store is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapScreen(
          config: AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
          ),
        ),
      ),
    );

    expect(find.byType(StorePreviewCard), findsNothing);
    expect(find.text('Google Maps API 키가 설정되지 않았습니다'), findsOneWidget);
  });

  testWidgets('shows store name, address, and burger style in preview card', (
    tester,
  ) async {
    final store = itaewonStoreLocations.first;

    await tester.pumpWidget(
      testApp(StorePreviewCard(store: store, onViewDetails: () {})),
    );

    expect(find.text('검수 데이터'), findsNothing);
    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(find.text(store.burgerStyle), findsOneWidget);
    expect(find.byKey(storePreviewDetailsButtonKey), findsOneWidget);
  });

  testWidgets('shows missing API key guidance', (tester) async {
    await tester.pumpWidget(testApp(const MissingApiKeyView()));

    expect(find.text('Google Maps API 키가 설정되지 않았습니다'), findsOneWidget);
    expect(find.textContaining('GOOGLE_MAPS_API_KEY'), findsOneWidget);
    expect(find.text(itaewonStoreLocations.first.name), findsOneWidget);
  });

  testWidgets('shows map error guidance', (tester) async {
    await tester.pumpWidget(
      testApp(const MapErrorView(error: 'boom', showDiagnostics: true)),
    );

    expect(find.textContaining('지도를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('production map errors hide diagnostic details', (tester) async {
    await tester.pumpWidget(testApp(const MapErrorView(error: 'private')));

    expect(find.text('지도를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
  });

  testWidgets('shows staging JSON errors without building the map', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.staging,
          ),
          stagingStoreLoader: () async {
            throw const FormatException('invalid staging json');
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MapErrorView), findsOneWidget);
    expect(find.textContaining('invalid staging json'), findsOneWidget);
  });

  testWidgets('staging store information appears in existing preview card', (
    tester,
  ) async {
    final stores = loadStagingFixture();
    final store = stores.first;

    await tester.pumpWidget(
      testApp(StorePreviewCard(store: store, onViewDetails: () {})),
    );

    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(
      find.text(BurgerStyle.parse(store.burgerStyle).displayLabel),
      findsOneWidget,
    );
  });

  testWidgets('shows missing Supabase URL without starting a load', (
    tester,
  ) async {
    var loadCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
            storeDataMode: StoreDataMode.supabase,
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async {
            loadCalls += 1;
            return [];
          },
        ),
      ),
    );

    expect(find.byType(MissingSupabaseConfigView), findsOneWidget);
    expect(find.text('서비스 설정을 확인할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsNothing);
    expect(loadCalls, 0);
  });

  testWidgets('shows missing Supabase publishable key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapScreen(
          config: AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
          ),
        ),
      ),
    );

    expect(find.byType(MissingSupabaseConfigView), findsOneWidget);
    expect(find.text('서비스 설정을 확인할 수 없습니다.'), findsOneWidget);
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsNothing);
  });

  testWidgets(
    'production configuration errors never load pilot or staging data',
    (tester) async {
      var stagingLoadCalls = 0;
      var supabaseLoadCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            config: const AppConfig(
              environment: AppEnvironment.production,
              googleMapsApiKey: 'test-key',
              storeDataMode: StoreDataMode.staging,
            ),
            stagingStoreLoader: () async {
              stagingLoadCalls += 1;
              return loadStagingFixture();
            },
            supabaseStoreLoader: () async {
              supabaseLoadCalls += 1;
              return searchableStores;
            },
          ),
        ),
      );

      expect(find.byType(MissingSupabaseConfigView), findsOneWidget);
      expect(find.text('서비스 설정을 확인할 수 없습니다.'), findsOneWidget);
      expect(find.text(itaewonStoreLocations.first.name), findsNothing);
      expect(find.text(loadStagingFixture().first.name), findsNothing);
      expect(stagingLoadCalls, 0);
      expect(supabaseLoadCalls, 0);
      expect(find.textContaining('기술 검증'), findsNothing);
    },
  );

  testWidgets(
    'production overrides pilot request and loads only Supabase data',
    (tester) async {
      var stagingLoadCalls = 0;
      var supabaseLoadCalls = 0;
      var markerCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MapScreen(
            config: const AppConfig(
              environment: AppEnvironment.production,
              googleMapsApiKey: 'test-key',
              storeDataMode: StoreDataMode.pilot,
              supabaseUrl: 'https://unit.invalid',
              supabasePublishableKey: 'public-test-value',
            ),
            stagingStoreLoader: () async {
              stagingLoadCalls += 1;
              return loadStagingFixture();
            },
            supabaseStoreLoader: () async {
              supabaseLoadCalls += 1;
              return searchableStores;
            },
            mapSurfaceBuilder: (markers, onMapTap) {
              markerCount = markers.length;
              return const ColoredBox(color: Colors.white);
            },
          ),
        ),
      );
      await tester.pump();

      expect(markerCount, searchableStores.length);
      expect(supabaseLoadCalls, 1);
      expect(stagingLoadCalls, 0);
      expect(find.text(itaewonStoreLocations.first.name), findsNothing);
      expect(find.textContaining('기술 검증'), findsNothing);
      expect(find.textContaining('debug center:'), findsNothing);
      expect(find.text('카메라 이동 대기 중'), findsNothing);
    },
  );

  testWidgets('development keeps its badge and camera diagnostics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
          ),
          mapSurfaceBuilder: (markers, onMapTap) {
            return const ColoredBox(color: Colors.white);
          },
        ),
      ),
    );

    expect(find.text('기술 검증 · Development'), findsOneWidget);
    expect(find.text('카메라 이동 대기 중'), findsOneWidget);
    expect(find.textContaining('debug center:'), findsOneWidget);
  });

  testWidgets('shows loading while Supabase rows are pending', (tester) async {
    final completer = Completer<List<StoreLocation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () => completer.future,
        ),
      ),
    );

    expect(find.byType(StoreDataLoadingView), findsOneWidget);
    completer.complete([]);
    await tester.pump();
  });

  testWidgets('shows an empty state for zero public Supabase stores', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async => [],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StoreDataEmptyView), findsOneWidget);
    expect(find.text('현재 공개된 매장이 없습니다.'), findsOneWidget);
    expect(find.text(itaewonStoreLocations.first.name), findsNothing);
  });

  testWidgets('hides Supabase error details and retries the load', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('private server response');
            }
            return [];
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StoreDataErrorView), findsOneWidget);
    expect(find.textContaining('private server response'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byType(StoreDataEmptyView), findsOneWidget);
  });

  testWidgets('filters markers by name and restores all markers on clear', (
    tester,
  ) async {
    Set<Marker> visibleMarkers = const <Marker>{};
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        visibleMarkers = markers;
        return const ColoredBox(color: Colors.white);
      },
    );

    expect(visibleMarkers, hasLength(3));
    expect(
      visibleMarkers.every(
        (marker) => marker.clusterManagerId == storeMarkerClusterManagerId,
      ),
      isTrue,
    );
    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();

    expect(visibleMarkers, hasLength(1));
    expect(visibleMarkers.single.clusterManagerId, storeMarkerClusterManagerId);
    expect(find.text('Alpha Burger'), findsOneWidget);
    expect(find.text('Beta Kitchen'), findsNothing);

    await tester.tap(find.byKey(storeSearchClearButtonKey));
    await tester.pump();

    expect(visibleMarkers, hasLength(3));
    expect(find.byKey(storeSearchResultsKey), findsNothing);
  });

  testWidgets('combines favorites with search and burger style filters', (
    tester,
  ) async {
    Set<Marker> visibleMarkers = const <Marker>{};
    final favorites = _MemoryFavoriteStoreIdsStore({'alpha', 'beta'});
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      favoriteStoreIdsStore: favorites,
      mapSurfaceBuilder: (markers, onMapTap) {
        visibleMarkers = markers;
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();
    expect(visibleMarkers, hasLength(2));
    expect(
      visibleMarkers.every(
        (marker) => marker.clusterManagerId == storeMarkerClusterManagerId,
      ),
      isTrue,
    );

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
    await tester.pump();
    expect(visibleMarkers, hasLength(1));
    expect(visibleMarkers.single.clusterManagerId, storeMarkerClusterManagerId);
    expect(find.text('Alpha Burger'), findsOneWidget);

    await tester.enterText(find.byKey(storeSearchFieldKey), 'beta');
    await tester.pump();
    expect(visibleMarkers, isEmpty);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)));
    await tester.pump();
    expect(visibleMarkers, hasLength(1));
    expect(visibleMarkers.single.clusterManagerId, storeMarkerClusterManagerId);
    expect(find.text('Beta Kitchen'), findsOneWidget);
  });

  testWidgets('restores saved favorites after rebuilding the app', (
    tester,
  ) async {
    final favorites = _MemoryFavoriteStoreIdsStore();
    Set<Marker> markers = const <Marker>{};
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      favoriteStoreIdsStore: favorites,
      mapSurfaceBuilder: (nextMarkers, onMapTap) {
        markers = nextMarkers;
        return const ColoredBox(color: Colors.white);
      },
    );

    markers
        .firstWhere((marker) => marker.markerId.value == 'alpha')
        .onTap
        ?.call();
    await tester.pump();
    await tester.tap(find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pumpAndSettle();
    expect(favorites.storeIds, {'alpha'});

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    var markerCount = 0;
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      favoriteStoreIdsStore: favorites,
      mapSurfaceBuilder: (nextMarkers, onMapTap) {
        markerCount = nextMarkers.length;
        return const ColoredBox(color: Colors.white);
      },
    );
    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();

    expect(markerCount, 1);
    expect(favorites.loadCalls, 2);
    expect(find.text('Alpha Burger'), findsOneWidget);
  });

  testWidgets('ignores favorites for stores no longer in the public list', (
    tester,
  ) async {
    var markerCount = 0;
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore({
        'deleted-public-store',
      }),
      mapSurfaceBuilder: (markers, onMapTap) {
        markerCount = markers.length;
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();

    expect(markerCount, 0);
    expect(find.text('즐겨찾기한 매장이 없습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows address matches and an explicit no-results state', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.enterText(
      find.byKey(storeSearchFieldKey),
      '  ITAEWON   burger ',
    );
    await tester.pump();
    expect(find.text('Beta Kitchen'), findsOneWidget);

    await tester.enterText(find.byKey(storeSearchFieldKey), 'missing store');
    await tester.pump();
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
  });

  testWidgets(
    'selecting a result shows its card and requests camera movement',
    (tester) async {
      StoreLocation? movedStore;
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        storeCameraMover: (store) async {
          movedStore = store;
        },
      );

      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(
        find.byKey(const ValueKey<String>('store-search-result-alpha')),
      );
      await tester.pump();

      expect(find.byType(StorePreviewCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StorePreviewCard),
          matching: find.text('Alpha Burger'),
        ),
        findsOneWidget,
      );
      expect(movedStore?.id, 'alpha');
      expect(tester.testTextInput.isVisible, isFalse);
    },
  );

  testWidgets(
    'changing the filter deselects a store that is no longer visible',
    (tester) async {
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        storeCameraMover: (_) async {},
      );

      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('store-search-result-alpha')),
      );
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsOneWidget);

      await tester.enterText(find.byKey(storeSearchFieldKey), 'beta');
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsNothing);
    },
  );

  testWidgets('typing and selecting search results do not reload store data', (
    tester,
  ) async {
    var loadCalls = 0;
    await pumpSearchableMap(
      tester,
      loader: () async {
        loadCalls += 1;
        return searchableStores;
      },
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      storeCameraMover: (_) async {},
    );

    await tester.enterText(find.byKey(storeSearchFieldKey), 'a');
    await tester.pump();
    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
    await tester.pump();
    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('store-search-result-alpha')),
    );
    await tester.pump();

    expect(loadCalls, 1);
  });

  testWidgets(
    'filters 25 loaded public stores locally without another Supabase load',
    (tester) async {
      final publicStores = buildSyntheticPublic25Stores();
      var loadCalls = 0;
      var markerCount = 0;
      await pumpSearchableMap(
        tester,
        loader: () async {
          loadCalls += 1;
          return publicStores;
        },
        mapSurfaceBuilder: (markers, onMapTap) {
          markerCount = markers.length;
          return const ColoredBox(color: Colors.white);
        },
      );

      expect(markerCount, 25);
      expect(loadCalls, 1);
      expect(find.byKey(burgerStyleAllFilterKey), findsOneWidget);
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.classic)),
        findsOneWidget,
      );
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.smash)),
        findsOneWidget,
      );
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
        findsOneWidget,
      );
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.other)),
        findsOneWidget,
      );
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.unclassified)),
        findsOneWidget,
      );
      expect(
        find.byKey(burgerStyleFilterKey(BurgerStyle.plantBased)),
        findsNothing,
      );

      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
      await tester.pump();
      expect(markerCount, 1);

      await tester.enterText(
        find.byKey(storeSearchFieldKey),
        '  yOnGsAn   Test-road 15  ',
      );
      await tester.pump();
      expect(markerCount, 1);
      expect(find.text('Public Burger 15'), findsOneWidget);

      await tester.enterText(find.byKey(storeSearchFieldKey), 'not present');
      await tester.pump();
      expect(markerCount, 0);
      expect(find.text('검색 결과가 없습니다.'), findsOneWidget);

      await tester.tap(find.byKey(storeSearchClearButtonKey));
      await tester.pump();
      expect(markerCount, 1);
      expect(loadCalls, 1);

      await tester.tap(find.byKey(burgerStyleAllFilterKey));
      await tester.pump();
      expect(markerCount, 25);
      expect(loadCalls, 1);
    },
  );

  testWidgets(
    'marker selection and blank map tap keep their existing behavior',
    (tester) async {
      Set<Marker> markers = const <Marker>{};
      ValueChanged<LatLng>? mapTap;
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (nextMarkers, onMapTap) {
          markers = nextMarkers;
          mapTap = onMapTap;
          return const ColoredBox(color: Colors.white);
        },
      );

      markers
          .firstWhere((marker) {
            return marker.markerId.value == 'beta' &&
                marker.clusterManagerId == storeMarkerClusterManagerId;
          })
          .onTap
          ?.call();
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsOneWidget);

      mapTap?.call(const LatLng(37.5, 127));
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsNothing);
    },
  );

  testWidgets('clear search has an accessible label and compact layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );
    await tester.enterText(find.byKey(storeSearchFieldKey), 'a');
    await tester.pump();

    final clearButton = tester.widget<IconButton>(
      find.byKey(storeSearchClearButtonKey),
    );
    expect(clearButton.tooltip, '검색어 지우기');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search is available in pilot and staging data modes', (
    tester,
  ) async {
    Widget mapSurface(Set<Marker> markers, ValueChanged<LatLng> onMapTap) {
      return const ColoredBox(color: Colors.white);
    }

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
          ),
          mapSurfaceBuilder: mapSurface,
        ),
      ),
    );
    expect(find.byKey(storeSearchFieldKey), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.staging,
          ),
          stagingStoreLoader: () async => loadStagingFixture(),
          mapSurfaceBuilder: mapSurface,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(storeSearchFieldKey), findsOneWidget);
  });

  testWidgets(
    'detail navigation passes the same store and preserves map search state',
    (tester) async {
      var loadCalls = 0;
      final externalUriLauncher = _SuccessfulExternalUriLauncher();
      await pumpSearchableMap(
        tester,
        loader: () async {
          loadCalls += 1;
          return searchableStores;
        },
        mapSurfaceBuilder: (markers, onMapTap) {
          return const ColoredBox(color: Colors.white);
        },
        storeCameraMover: (_) async {},
        externalUriLauncher: externalUriLauncher,
      );

      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('store-search-result-alpha')),
      );
      await tester.pump();

      expect(find.byKey(storePreviewDetailsButtonKey), findsOneWidget);
      await tester.tap(find.byKey(storePreviewDetailsButtonKey));
      await tester.pumpAndSettle();

      final detailScreen = tester.widget<StoreDetailScreen>(
        find.byType(StoreDetailScreen),
      );
      expect(identical(detailScreen.store, searchableStores.first), isTrue);
      expect(find.text('Alpha Burger'), findsOneWidget);
      expect(find.text('Seoul Yongsan Alpha-ro 1'), findsOneWidget);

      await tester.tap(find.byKey(storeDirectionsButtonKey));
      await tester.pumpAndSettle();
      expect(externalUriLauncher.callCount, 1);
      expect(loadCalls, 1);

      await tester.tap(find.byKey(storeDetailBackButtonKey));
      await tester.pumpAndSettle();

      final searchField = tester.widget<TextField>(
        find.byKey(storeSearchFieldKey),
      );
      expect(searchField.controller?.text, 'alpha');
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(burgerStyleFilterKey(BurgerStyle.smash)),
            )
            .selected,
        isTrue,
      );
      expect(find.byType(StorePreviewCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(StorePreviewCard),
          matching: find.text('Alpha Burger'),
        ),
        findsOneWidget,
      );
      expect(loadCalls, 1);
    },
  );

  testWidgets('shows only loaded styles in fixed taxonomy order', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    final allChip = tester.widget<ChoiceChip>(
      find.byKey(burgerStyleAllFilterKey),
    );
    expect(allChip.selected, isTrue);
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.classic)),
      findsOneWidget,
    );
    expect(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)), findsOneWidget);
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.unclassified)),
      findsOneWidget,
    );
    expect(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)), findsNothing);

    final classicX = tester
        .getTopLeft(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)))
        .dx;
    final smashX = tester
        .getTopLeft(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)))
        .dx;
    final unclassifiedX = tester
        .getTopLeft(find.byKey(burgerStyleFilterKey(BurgerStyle.unclassified)))
        .dx;
    expect(classicX, lessThan(smashX));
    expect(smashX, lessThan(unclassifiedX));
  });

  testWidgets('combines style and text filters without resetting either', (
    tester,
  ) async {
    var markerCount = 0;
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        markerCount = markers.length;
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
    await tester.pump();
    expect(markerCount, 1);

    await tester.enterText(find.byKey(storeSearchFieldKey), 'beta');
    await tester.pump();
    expect(markerCount, 0);
    expect(find.text('검색 결과가 없습니다.'), findsOneWidget);

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)));
    await tester.pump();
    expect(markerCount, 1);
    expect(find.text('Beta Kitchen'), findsOneWidget);

    await tester.tap(find.byKey(storeSearchClearButtonKey));
    await tester.pump();
    expect(markerCount, 1);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(burgerStyleFilterKey(BurgerStyle.classic)),
          )
          .selected,
      isTrue,
    );

    await tester.enterText(find.byKey(storeSearchFieldKey), 'beta');
    await tester.pump();
    await tester.tap(find.byKey(burgerStyleAllFilterKey));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(storeSearchFieldKey))
          .controller
          ?.text,
      'beta',
    );
    expect(markerCount, 1);
  });

  testWidgets('style filter closes a selected card that no longer matches', (
    tester,
  ) async {
    Set<Marker> markers = const <Marker>{};
    var cameraMoveRequests = 0;
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (nextMarkers, onMapTap) {
        markers = nextMarkers;
        return const ColoredBox(color: Colors.white);
      },
      storeCameraMover: (_) async {
        cameraMoveRequests += 1;
      },
    );

    markers
        .firstWhere((marker) => marker.markerId.value == 'alpha')
        .onTap
        ?.call();
    await tester.pump();
    expect(find.byType(StorePreviewCard), findsOneWidget);

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)));
    await tester.pump();
    expect(find.byType(StorePreviewCard), findsNothing);
    expect(cameraMoveRequests, 0);
  });

  testWidgets('search and filters expose one accessible semantics node each', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    final searchFinder = find.bySemanticsLabel('매장명 또는 주소 검색');
    expect(searchFinder, findsOne);
    expect(
      tester.getSemantics(searchFinder).flagsCollection.isTextField,
      isTrue,
    );

    final favoritesFinder = find.bySemanticsLabel('즐겨찾기 매장만 보기');
    expect(favoritesFinder, findsOne);
    var favoritesNode = tester.getSemantics(favoritesFinder);
    expect(favoritesNode.flagsCollection.isButton, isTrue);
    expect(favoritesNode.flagsCollection.isSelected, isNot(Tristate.none));
    expect(favoritesNode.flagsCollection.isSelected, Tristate.isFalse);

    final allFilterFinder = find.bySemanticsLabel('버거 스타일 전체 필터');
    expect(allFilterFinder, findsOne);
    var allFilterNode = tester.getSemantics(allFilterFinder);
    expect(allFilterNode.flagsCollection.isButton, isTrue);
    expect(allFilterNode.flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();
    favoritesNode = tester.getSemantics(favoritesFinder);
    expect(favoritesNode.flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)));
    await tester.pump();
    allFilterNode = tester.getSemantics(allFilterFinder);
    expect(allFilterNode.flagsCollection.isSelected, Tristate.isFalse);
    final classicNode = tester.getSemantics(
      find.bySemanticsLabel('버거 스타일 클래식 필터'),
    );
    expect(classicNode.flagsCollection.isButton, isTrue);
    expect(classicNode.flagsCollection.isSelected, Tristate.isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('zoom controls are accessible, 48dp, stepped, and bounded', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final zoomMoves = <double>[];
    Set<Marker> markers = const <Marker>{};
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (nextMarkers, onMapTap) {
        markers = nextMarkers;
        return const ColoredBox(color: Colors.white);
      },
      mapZoomMover: (zoom) async {
        zoomMoves.add(zoom);
      },
    );

    final zoomInFinder = find.byKey(mapZoomInButtonKey);
    final zoomOutFinder = find.byKey(mapZoomOutButtonKey);
    expect(find.bySemanticsLabel('지도 확대'), findsOne);
    expect(find.bySemanticsLabel('지도 축소'), findsOne);
    expect(tester.getSize(zoomInFinder).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(zoomInFinder).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(zoomOutFinder).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(zoomOutFinder).height, greaterThanOrEqualTo(48));
    expect(
      tester.getRect(zoomInFinder).top,
      greaterThanOrEqualTo(
        tester.getRect(find.byKey(favoritesOnlyFilterKey)).bottom,
      ),
    );

    final initialZoom = cameraPositionForStores(searchableStores).zoom;
    await tester.tap(zoomInFinder);
    await tester.pumpAndSettle();
    expect(zoomMoves, [initialZoom + mapZoomStep]);

    while (tester
            .widget<IconButton>(
              find.descendant(
                of: zoomInFinder,
                matching: find.byType(IconButton),
              ),
            )
            .onPressed !=
        null) {
      await tester.tap(zoomInFinder);
      await tester.pumpAndSettle();
    }
    expect(zoomMoves.last, maximumMapZoom);
    final movesAtMaximum = zoomMoves.length;
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: zoomInFinder,
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(zoomMoves.length, movesAtMaximum);

    while (tester
            .widget<IconButton>(
              find.descendant(
                of: zoomOutFinder,
                matching: find.byType(IconButton),
              ),
            )
            .onPressed !=
        null) {
      await tester.tap(zoomOutFinder);
      await tester.pumpAndSettle();
    }
    expect(zoomMoves.last, minimumMapZoom);
    for (var index = 1; index < zoomMoves.length; index += 1) {
      final step = (zoomMoves[index] - zoomMoves[index - 1]).abs();
      expect(step, greaterThan(0));
      expect(step, lessThanOrEqualTo(mapZoomStep));
    }

    markers.first.onTap?.call();
    await tester.pump();
    expect(find.byType(StorePreviewCard), findsOneWidget);
    expect(zoomInFinder, findsOneWidget);
    expect(zoomOutFinder, findsOneWidget);
    expect(
      tester.getRect(zoomOutFinder).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(StorePreviewCard)).top),
    );
    semanticsHandle.dispose();
  });

  testWidgets('result and favorite empty states use distinct live regions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();
    final resultCountNode = tester.getSemantics(
      find.bySemanticsLabel('검색 결과 1개'),
    );
    expect(resultCountNode.flagsCollection.isLiveRegion, isTrue);

    await tester.enterText(find.byKey(storeSearchFieldKey), 'not present');
    await tester.pump();
    final noResultsNode = tester.getSemantics(
      find.bySemanticsLabel('검색 결과가 없습니다.'),
    );
    expect(noResultsNode.flagsCollection.isLiveRegion, isTrue);

    await tester.tap(find.byKey(storeSearchClearButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();
    expect(find.text('즐겨찾기한 매장이 없습니다.'), findsOneWidget);
    final noFavoritesNode = tester.getSemantics(
      find.bySemanticsLabel('즐겨찾기한 매장이 없습니다.'),
    );
    expect(noFavoritesNode.flagsCollection.isLiveRegion, isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('loading, error, and retry success are live regions', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final initialLoad = Completer<List<StoreLocation>>();
    final retryLoad = Completer<List<StoreLocation>>();
    var loadCalls = 0;
    await pumpSearchableMap(
      tester,
      loader: () {
        loadCalls += 1;
        return loadCalls == 1 ? initialLoad.future : retryLoad.future;
      },
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    final loadingNode = tester.getSemantics(
      find.bySemanticsLabel('공개 매장을 불러오는 중입니다.'),
    );
    expect(loadingNode.flagsCollection.isLiveRegion, isTrue);

    initialLoad.completeError(StateError('synthetic failure'));
    await tester.pump();
    await tester.pump();
    final errorNode = tester.getSemantics(
      find.bySemanticsLabel('공개 매장 정보를 불러오지 못했습니다.'),
    );
    expect(errorNode.flagsCollection.isLiveRegion, isTrue);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('공개 매장을 불러오는 중입니다.'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    retryLoad.complete(searchableStores);
    await tester.pump();
    await tester.pump();
    final readyNode = tester.getSemantics(
      find.bySemanticsLabel('공개 매장 3개를 불러왔습니다.'),
    );
    expect(readyNode.flagsCollection.isLiveRegion, isTrue);
    semanticsHandle.dispose();
  });

  testWidgets('staging exposes approved styles in taxonomy order', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.staging,
          ),
          stagingStoreLoader: () async => loadStagingFixture(),
          mapSurfaceBuilder: (markers, onMapTap) {
            return const ColoredBox(color: Colors.white);
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(burgerStyleAllFilterKey), findsOneWidget);
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.classic)),
      findsOneWidget,
    );
    expect(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)), findsOneWidget);
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
      findsOneWidget,
    );
    expect(find.byKey(burgerStyleFilterKey(BurgerStyle.other)), findsOneWidget);
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.unclassified)),
      findsOneWidget,
    );
    expect(
      find.byKey(burgerStyleFilterKey(BurgerStyle.plantBased)),
      findsNothing,
    );
  });
}

class _SuccessfulExternalUriLauncher implements ExternalUriLauncher {
  int callCount = 0;

  @override
  Future<bool> launch(Uri uri) async {
    callCount += 1;
    return true;
  }
}

class _MemoryFavoriteStoreIdsStore implements FavoriteStoreIdsStore {
  _MemoryFavoriteStoreIdsStore([Set<String> initialIds = const <String>{}])
    : storeIds = Set<String>.of(initialIds);

  Set<String> storeIds;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<Set<String>> load() async {
    loadCalls += 1;
    return Set<String>.unmodifiable(storeIds);
  }

  @override
  Future<void> save(Set<String> storeIds) async {
    saveCalls += 1;
    this.storeIds = Set<String>.of(storeIds);
  }
}

class _FakeCurrentLocationService implements CurrentLocationService {
  _FakeCurrentLocationService({
    this.serviceEnabled = true,
    this.checkedPermission = LocationPermissionStatus.whileInUse,
    LocationPermissionStatus? requestedPermission,
    CurrentLocation? location,
    this.currentLocationError,
    this.currentLocationHandler,
  }) : requestedPermission = requestedPermission ?? checkedPermission,
       location =
           location ??
           const CurrentLocation(latitude: 37.53, longitude: 126.99);

  final bool serviceEnabled;
  final LocationPermissionStatus checkedPermission;
  final LocationPermissionStatus requestedPermission;
  final CurrentLocation location;
  final Object? currentLocationError;
  final Future<CurrentLocation> Function()? currentLocationHandler;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int currentLocationCalls = 0;
  int openAppSettingsCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    checkPermissionCalls += 1;
    return checkedPermission;
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    requestPermissionCalls += 1;
    return requestedPermission;
  }

  @override
  Future<CurrentLocation> getCurrentLocation() async {
    currentLocationCalls += 1;
    final handler = currentLocationHandler;
    if (handler != null) {
      return handler();
    }
    final error = currentLocationError;
    if (error != null) {
      throw error;
    }
    return location;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls += 1;
    return true;
  }
}
