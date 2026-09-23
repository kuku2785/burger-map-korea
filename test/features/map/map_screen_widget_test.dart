import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/menu/domain/menu_item.dart';
import 'package:burger_map_korea/features/menu/domain/menu_repository.dart';
import 'package:burger_map_korea/features/stores/application/public_store_controller.dart';
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
  final nearbySortStores = <StoreLocation>[
    StoreLocation(
      id: 'far-chicken',
      name: 'Far Chicken Burger',
      address: 'Seoul Far-ro 1',
      latitude: 37.56,
      longitude: 127.02,
      burgerStyle: 'chicken',
    ),
    StoreLocation(
      id: 'near-chicken',
      name: 'Near Chicken Burger',
      address: 'Seoul Near-ro 2',
      latitude: 37.531,
      longitude: 126.991,
      burgerStyle: 'chicken',
    ),
    StoreLocation(
      id: 'near-classic',
      name: 'Near Classic Burger',
      address: 'Seoul Near-ro 3',
      latitude: 37.532,
      longitude: 126.992,
      burgerStyle: 'classic',
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
    MenuRepository? menuRepository,
    Duration storeLoadTimeout = const Duration(seconds: 10),
    Duration storeRefreshInterval = const Duration(minutes: 5),
    PublicStoreClock? storeClock,
    PublicStoreRefreshScheduler? storeRefreshScheduler,
    CurrentLocationClock? currentLocationClock,
    Duration maximumCurrentLocationAge = const Duration(minutes: 2),
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
          menuRepository: menuRepository,
          storeLoadTimeout: storeLoadTimeout,
          storeRefreshInterval: storeRefreshInterval,
          storeClock: storeClock,
          storeRefreshScheduler: storeRefreshScheduler,
          currentLocationClock: currentLocationClock,
          maximumCurrentLocationAge: maximumCurrentLocationAge,
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

  testWidgets('unready map controller does not block search list or details', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
    );
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(mapZoomInButtonKey),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byKey(storeSearchResultsKey),
        matching: find.text('Alpha Burger'),
      ),
    );
    await tester.pump();
    expect(find.byType(StorePreviewCard), findsOneWidget);
    await tester.tap(find.byKey(explorerListTabKey));
    await tester.pump();
    await tester.tap(find.text('Alpha Burger'));
    await tester.pumpAndSettle();
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'stalled zoom unlocks and late completion cannot unlock a retry',
    (tester) async {
      final first = Completer<void>();
      final second = Completer<void>();
      var calls = 0;
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
        mapZoomMover: (_) => ++calls == 1 ? first.future : second.future,
      );
      final zoom = find.byKey(mapZoomInButtonKey);
      final zoomButton = find.descendant(
        of: zoom,
        matching: find.byType(IconButton),
      );
      await tester.tap(zoom);
      await tester.pump();
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNull);
      await tester.pump(const Duration(seconds: 10));
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNotNull);
      await tester.tap(zoom);
      await tester.pump();
      expect(calls, 2);
      first.completeError(StateError('late camera failure'));
      await tester.pump();
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      second.complete();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background interrupts camera wait while inactive alone does not',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
        mapZoomMover: (_) {
          calls++;
          return calls == 1 ? pending.future : Future<void>.value();
        },
      );
      final zoom = find.byKey(mapZoomInButtonKey);
      final zoomButton = find.descendant(
        of: zoom,
        matching: find.byType(IconButton),
      );
      await tester.tap(zoom);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNotNull);
      await tester.tap(zoom);
      await tester.pump();
      expect(calls, 2);
      pending.completeError(StateError('previous background camera'));
      await tester.pump();
      expect(tester.widget<IconButton>(zoomButton).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stalled cluster movement releases its lock and disposes safely',
    (tester) async {
      late ClusterManager manager;
      final first = Completer<void>();
      final second = Completer<void>();
      var calls = 0;
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
        onClusterManagerReady: (value) => manager = value,
        clusterCameraMover: (_, _) =>
            ++calls == 1 ? first.future : second.future,
      );
      final cluster = Cluster(
        storeMarkerClusterManagerId,
        const [MarkerId('alpha'), MarkerId('beta')],
        position: const LatLng(37.53, 126.99),
        bounds: LatLngBounds(
          southwest: const LatLng(37.52, 126.98),
          northeast: const LatLng(37.54, 127),
        ),
      );
      manager.onClusterTap!(cluster);
      await tester.pump();
      manager.onClusterTap!(cluster);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 10));
      manager.onClusterTap!(cluster);
      await tester.pump();
      expect(calls, 2);
      first.completeError(StateError('late cluster failure'));
      await tester.pump();
      manager.onClusterTap!(cluster);
      expect(calls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      second.completeError(StateError('disposed camera'));
      manager.onClusterTap!(cluster);
      await tester.pump();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pilot details remain available after public snapshot wiring', (
    tester,
  ) async {
    Set<Marker> markers = {};
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
          ),
          favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore(),
          mapSurfaceBuilder: (next, _) {
            markers = next;
            return const ColoredBox(color: Colors.white);
          },
        ),
      ),
    );
    await tester.pump();
    markers.first.onTap!();
    await tester.pump();
    await tester.tap(find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(storeAddressCopyButtonKey), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byKey(storeFavoriteButtonKey)).onPressed,
      isNotNull,
    );
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

  testWidgets('camera failure keeps a valid location usable for nearby sort', (
    tester,
  ) async {
    final service = _FakeCurrentLocationService(
      checkedPermission: LocationPermissionStatus.whileInUse,
    );
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
      currentLocationService: service,
      currentLocationCameraMover: (_, _) async {
        throw StateError('synthetic camera failure');
      },
    );
    await tester.tap(find.byKey(currentLocationButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.text('현재 위치로 지도를 이동하지 못했습니다. 잠시 후 다시 시도해 주세요.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
    expect(service.currentLocationCalls, 1);
  });

  testWidgets(
    'camera timeout recovers and a late error after dispose is safe',
    (tester) async {
      final camera = Completer<void>();
      await pumpSearchableMap(
        tester,
        loader: () async => searchableStores,
        mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
        currentLocationService: _FakeCurrentLocationService(
          checkedPermission: LocationPermissionStatus.whileInUse,
        ),
        currentLocationCameraMover: (_, _) => camera.future,
      );
      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(
        find.text('현재 위치로 지도를 이동하지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      camera.completeError(StateError('late camera error'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows the nearby sort control', (tester) async {
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    expect(find.byKey(nearbySortFilterKey), findsOneWidget);
    expect(find.text('가까운 순'), findsOneWidget);
  });

  testWidgets('foreground expiry clears nearby selection and location layer', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 9);
    final enabled = <bool>[];
    final service = _FakeCurrentLocationService(
      currentLocationHandler: () async =>
          CurrentLocation(latitude: 37.53, longitude: 126.99, capturedAt: now),
    );
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      currentLocationService: service,
      currentLocationClock: () => now,
      onMyLocationEnabledChanged: enabled.add,
    );
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isFalse,
    );
    expect(enabled, [true, false]);
    expect(service.currentLocationCalls, 1);
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();
    expect(service.currentLocationCalls, 2);
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
  });

  testWidgets(
    'late location after background cannot move camera or enable sorting',
    (tester) async {
      final old = Completer<CurrentLocation>();
      var calls = 0;
      var cameraCalls = 0;
      final service = _FakeCurrentLocationService(
        currentLocationHandler: () {
          calls++;
          return calls == 1
              ? old.future
              : Future.value(
                  CurrentLocation(
                    latitude: 37.53,
                    longitude: 126.99,
                    capturedAt: DateTime.now(),
                  ),
                );
        },
      );
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        currentLocationService: service,
        currentLocationCameraMover: (_, _) async {
          cameraCalls++;
        },
      );
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      old.complete(
        CurrentLocation(
          latitude: 37.53,
          longitude: 126.99,
          capturedAt: DateTime.now(),
        ),
      );
      await tester.pump();
      expect(cameraCalls, 0);
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(cameraCalls, 0);
      expect(calls, 2);
    },
  );

  testWidgets(
    'approximate-only location enables current location and nearby order with lasting notice',
    (tester) async {
      var moves = 0;
      final service = _FakeCurrentLocationService(
        location: CurrentLocation(
          latitude: 37.53,
          longitude: 126.99,
          capturedAt: DateTime.now(),
          precision: CurrentLocationPrecision.approximate,
          accuracyMeters: 500,
        ),
      );
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        currentLocationService: service,
        currentLocationCameraMover: (_, _) async {
          moves++;
        },
      );
      await tester.tap(find.byKey(currentLocationButtonKey));
      await tester.pumpAndSettle();
      expect(moves, 1);
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isTrue,
      );
      expect(_visibleSearchResultIds(tester).first, 'near-chicken');
      await tester.pump(const Duration(seconds: 5));
      expect(find.textContaining('대략적인 위치 기준'), findsOneWidget);
      expect(service.requestPermissionCalls, 0);
    },
  );

  testWidgets('nearby sort requests a location and activates after success', (
    tester,
  ) async {
    final locationService = _FakeCurrentLocationService(
      location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
    );
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: locationService,
    );

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(locationService.currentLocationCalls, 1);
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
  });

  testWidgets('nearby sort stays inactive when location lookup fails', (
    tester,
  ) async {
    final locationService = _FakeCurrentLocationService(
      currentLocationError: StateError('synthetic location failure'),
    );
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: locationService,
    );

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isFalse,
    );
    expect(find.textContaining('현재 위치를 가져오지 못했습니다.'), findsOneWidget);
  });

  testWidgets('nearby sort replaces an expired in-memory location', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 8, 12);
    var locationCalls = 0;
    final locationService = _FakeCurrentLocationService(
      currentLocationHandler: () async {
        locationCalls += 1;
        return CurrentLocation(
          latitude: 37.53 + locationCalls / 1000,
          longitude: 126.99,
          capturedAt: now,
        );
      },
    );

    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      currentLocationService: locationService,
      currentLocationCameraMover: (_, _) async {},
      currentLocationClock: () => now,
    );

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();
    now = now.add(const Duration(minutes: 3));
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(locationService.currentLocationCalls, 2);
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
  });

  testWidgets('background resume refreshes an expired nearby location', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 9, 8, 12);
    final locationService = _FakeCurrentLocationService(
      currentLocationHandler: () async =>
          CurrentLocation(latitude: 37.53, longitude: 126.99, capturedAt: now),
    );

    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      currentLocationService: locationService,
      currentLocationCameraMover: (_, _) async {},
      currentLocationClock: () => now,
    );
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(minutes: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(locationService.currentLocationCalls, 2);
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
  });

  testWidgets(
    'resume clears nearby sort after location permission is revoked',
    (tester) async {
      var permissionChecks = 0;
      final enabledChanges = <bool>[];
      final locationService = _FakeCurrentLocationService(
        checkPermissionHandler: () async {
          permissionChecks += 1;
          return permissionChecks == 1
              ? LocationPermissionStatus.whileInUse
              : LocationPermissionStatus.denied;
        },
      );

      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        currentLocationService: locationService,
        currentLocationCameraMover: (_, _) async {},
        onMyLocationEnabledChanged: enabledChanges.add,
      );
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(permissionChecks, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(permissionChecks, 2);
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      expect(enabledChanges, <bool>[true, false]);
    },
  );

  testWidgets('approximate location shows a non-precise sorting notice', (
    tester,
  ) async {
    final locationService = _FakeCurrentLocationService(
      location: CurrentLocation(
        latitude: 37.53,
        longitude: 126.99,
        capturedAt: DateTime.now(),
        accuracyMeters: 500,
        precision: CurrentLocationPrecision.approximate,
      ),
    );

    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      currentLocationService: locationService,
      currentLocationCameraMover: (_, _) async {},
    );
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();

    expect(find.textContaining('대략적인 위치 기준'), findsOneWidget);
  });

  testWidgets('nearby sort orders results and off restores original order', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      ),
    );
    await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
    await tester.pump();
    expect(_visibleSearchResultIds(tester), [
      'far-chicken',
      'near-chicken',
      'near-classic',
    ]);

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();
    expect(_visibleSearchResultIds(tester), [
      'near-chicken',
      'near-classic',
      'far-chicken',
    ]);

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();
    expect(_visibleSearchResultIds(tester), [
      'far-chicken',
      'near-chicken',
      'near-classic',
    ]);
  });

  testWidgets('combines text search with nearby sort', (tester) async {
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      ),
    );

    await tester.enterText(find.byKey(storeSearchFieldKey), 'Chicken');
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(_visibleSearchResultIds(tester), ['near-chicken', 'far-chicken']);
  });

  testWidgets('combines burger style filter with nearby sort', (tester) async {
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      ),
    );

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)));
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(_visibleSearchResultIds(tester), ['near-chicken', 'far-chicken']);
  });

  testWidgets('combines favorites only with nearby sort', (tester) async {
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      ),
      favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore({
        'far-chicken',
        'near-chicken',
      }),
    );

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(_visibleSearchResultIds(tester), ['near-chicken', 'far-chicken']);
  });

  testWidgets('favorites retap turns the filter off and preserves search', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore({'alpha'}),
    );
    await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
    await tester.pump();

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();
    expect(_visibleSearchResultIds(tester), ['alpha']);

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();

    expect(
      tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
      isFalse,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(storeSearchFieldKey))
          .controller
          ?.text,
      'Burger',
    );
    expect(_visibleSearchResultIds(tester), ['alpha', 'beta']);
  });

  testWidgets(
    'nearby retap turns sorting off without another location lookup',
    (tester) async {
      final locationService = _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      );
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        currentLocationService: locationService,
      );
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Chicken');
      await tester.ensureVisible(
        find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
      );
      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)));
      await tester.pump();

      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();
      expect(_visibleSearchResultIds(tester), ['near-chicken', 'far-chicken']);
      expect(locationService.currentLocationCalls, 1);

      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pump();

      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      expect(locationService.currentLocationCalls, 1);
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller
            ?.text,
        'Chicken',
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
            )
            .selected,
        isTrue,
      );
      expect(_visibleSearchResultIds(tester), ['far-chicken', 'near-chicken']);
    },
  );

  testWidgets(
    'style retap clears only style and leaves every style chip unselected',
    (tester) async {
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore({
          'far-chicken',
          'near-classic',
        }),
      );
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.ensureVisible(
        find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
      );
      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)));
      await tester.pump();
      expect(_visibleSearchResultIds(tester), ['far-chicken']);

      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)));
      await tester.pump();

      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
            )
            .selected,
        isFalse,
      );
      expect(
        tester.widget<ChoiceChip>(find.byKey(burgerStyleAllFilterKey)).selected,
        isFalse,
      );
      expect(_visibleSearchResultIds(tester), ['far-chicken', 'near-classic']);
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isTrue,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller
            ?.text,
        'Burger',
      );
      expect(_visibleSearchResultIds(tester), ['far-chicken', 'near-classic']);
    },
  );

  testWidgets(
    'All clears every criterion, shows all stores, and retap closes results',
    (tester) async {
      Set<String> markerIds = <String>{};
      final locationService = _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      );
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (markers, _) {
          markerIds = markers.map((marker) => marker.markerId.value).toSet();
          return const ColoredBox(color: Colors.white);
        },
        currentLocationService: locationService,
        favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore({'far-chicken'}),
      );

      final allChip = find.byKey(burgerStyleAllFilterKey);
      expect(tester.widget<ChoiceChip>(allChip).selected, isFalse);
      expect(find.byKey(storeSearchResultsKey), findsNothing);
      expect(markerIds, {'far-chicken', 'near-chicken', 'near-classic'});

      await tester.tap(allChip);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isTrue);
      expect(_visibleSearchResultIds(tester), [
        'far-chicken',
        'near-chicken',
        'near-classic',
      ]);

      await tester.enterText(find.byKey(storeSearchFieldKey), 'Chicken');
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isFalse);

      await tester.tap(allChip);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller
            ?.text,
        isEmpty,
      );

      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isFalse);

      await tester.tap(allChip);
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isTrue);
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isFalse,
      );

      await tester.ensureVisible(
        find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
      );
      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)));
      await tester.pump();
      expect(tester.widget<ChoiceChip>(allChip).selected, isFalse);

      await tester.enterText(find.byKey(storeSearchFieldKey), 'Chicken');
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();
      expect(locationService.currentLocationCalls, 1);
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isTrue,
      );

      await tester.ensureVisible(allChip);
      await tester.tap(allChip);
      await tester.pump();

      expect(tester.widget<ChoiceChip>(allChip).selected, isTrue);
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller
            ?.text,
        isEmpty,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isFalse,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(burgerStyleFilterKey(BurgerStyle.chicken)),
            )
            .selected,
        isFalse,
      );
      expect(_visibleSearchResultIds(tester), [
        'far-chicken',
        'near-chicken',
        'near-classic',
      ]);
      expect(markerIds, {'far-chicken', 'near-chicken', 'near-classic'});

      await tester.tap(allChip);
      await tester.pump();

      expect(tester.widget<ChoiceChip>(allChip).selected, isFalse);
      expect(find.byKey(storeSearchResultsKey), findsNothing);
      expect(markerIds, {'far-chicken', 'near-chicken', 'near-classic'});
    },
  );

  testWidgets(
    'All prevents a pending nearby request from reselecting sorting',
    (tester) async {
      final pendingLocation = Completer<CurrentLocation>();
      await pumpSearchableMap(
        tester,
        loader: () async => nearbySortStores,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
        currentLocationService: _FakeCurrentLocationService(
          currentLocationHandler: () => pendingLocation.future,
        ),
      );

      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pump();
      await tester.tap(find.byKey(burgerStyleAllFilterKey));
      await tester.pump();

      pendingLocation.complete(
        const CurrentLocation(latitude: 37.53, longitude: 126.99),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<ChoiceChip>(find.byKey(burgerStyleAllFilterKey)).selected,
        isTrue,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      expect(_visibleSearchResultIds(tester), [
        'far-chicken',
        'near-chicken',
        'near-classic',
      ]);
    },
  );

  testWidgets('current location button supplies location for nearby sort', (
    tester,
  ) async {
    final locationService = _FakeCurrentLocationService(
      location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
    );
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: locationService,
      currentLocationCameraMover: (location, zoom) async {},
    );

    await tester.tap(find.byKey(currentLocationButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();

    expect(locationService.currentLocationCalls, 1);
    expect(
      tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
      isTrue,
    );
  });

  testWidgets('nearby sort does not change the marker set', (tester) async {
    Set<Marker> visibleMarkers = const <Marker>{};
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        visibleMarkers = markers;
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        location: const CurrentLocation(latitude: 37.53, longitude: 126.99),
      ),
    );
    final initialMarkerIds = visibleMarkers
        .map((marker) => marker.markerId)
        .toSet();
    visibleMarkers
        .firstWhere((marker) => marker.markerId.value == 'far-chicken')
        .onTap
        ?.call();
    await tester.pump();
    expect(
      tester.widget<StorePreviewCard>(find.byType(StorePreviewCard)).store.id,
      'far-chicken',
    );

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pumpAndSettle();

    expect(
      visibleMarkers.map((marker) => marker.markerId).toSet(),
      initialMarkerIds,
    );
    expect(visibleMarkers, hasLength(nearbySortStores.length));
    expect(
      tester.widget<StorePreviewCard>(find.byType(StorePreviewCard)).store.id,
      'far-chicken',
    );
  });

  testWidgets('nearby sort semantics expose location and selected states', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final locationCompleter = Completer<CurrentLocation>();
    await pumpSearchableMap(
      tester,
      loader: () async => nearbySortStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
      currentLocationService: _FakeCurrentLocationService(
        currentLocationHandler: () => locationCompleter.future,
      ),
    );

    final needsLocationFinder = find.bySemanticsLabel(
      '가까운 순 정렬, 현재 위치가 필요합니다.',
    );
    expect(needsLocationFinder, findsOneWidget);
    expect(
      tester.getSemantics(needsLocationFinder).flagsCollection.isSelected,
      Tristate.isFalse,
    );

    await tester.tap(find.byKey(nearbySortFilterKey));
    await tester.pump();
    expect(
      find.bySemanticsLabel('가까운 순 정렬, 현재 위치를 확인하는 중입니다.'),
      findsOneWidget,
    );

    locationCompleter.complete(
      const CurrentLocation(latitude: 37.53, longitude: 126.99),
    );
    await tester.pumpAndSettle();
    final activeFinder = find.bySemanticsLabel('가까운 순 정렬');
    expect(activeFinder, findsOneWidget);
    expect(
      tester.getSemantics(activeFinder).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    semanticsHandle.dispose();
  });

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
      await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
      await tester.pump();
      clusterManager!.onClusterTap!.call(cluster);
      await tester.pump();
      expect(moveCalls, 1, reason: 'filtered-out cluster members are stale');
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
    final storeRetry = find.descendant(
      of: find.byType(StoreDataErrorView),
      matching: find.text('다시 시도'),
    );
    expect(storeRetry, findsOneWidget);

    await tester.tap(storeRetry);
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byType(StoreDataEmptyView), findsOneWidget);
  });

  testWidgets(
    'times out an unresponsive load and applies only the retry result',
    (tester) async {
      final firstLoad = Completer<List<StoreLocation>>();
      final secondLoad = Completer<List<StoreLocation>>();
      var attempts = 0;
      Set<String> visibleMarkerIds = <String>{};

      await pumpSearchableMap(
        tester,
        loader: () {
          attempts += 1;
          return attempts == 1 ? firstLoad.future : secondLoad.future;
        },
        storeLoadTimeout: const Duration(seconds: 1),
        mapSurfaceBuilder: (markers, onMapTap) {
          visibleMarkerIds = markers
              .map((marker) => marker.markerId.value)
              .toSet();
          return const ColoredBox(color: Colors.white);
        },
      );

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byType(StoreDataErrorView), findsOneWidget);

      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(attempts, 2);

      secondLoad.complete(<StoreLocation>[searchableStores.last]);
      await tester.pump();
      expect(visibleMarkerIds, <String>{searchableStores.last.id});

      firstLoad.complete(<StoreLocation>[searchableStores.first]);
      await tester.pump();
      expect(visibleMarkerIds, <String>{searchableStores.last.id});
    },
  );

  testWidgets('keeps a zero-store result distinct from an unresponsive error', (
    tester,
  ) async {
    await pumpSearchableMap(
      tester,
      loader: () async => const <StoreLocation>[],
      storeLoadTimeout: const Duration(seconds: 1),
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );
    expect(find.byType(StoreDataEmptyView), findsOneWidget);
    expect(find.byType(StoreDataErrorView), findsNothing);
  });

  testWidgets(
    'duplicate retries and late failure cannot replace recovered data',
    (tester) async {
      final first = Completer<List<StoreLocation>>();
      final second = Completer<List<StoreLocation>>();
      var calls = 0;
      Set<String> ids = {};
      await pumpSearchableMap(
        tester,
        loader: () => ++calls == 1 ? first.future : second.future,
        storeLoadTimeout: const Duration(seconds: 1),
        mapSurfaceBuilder: (markers, _) {
          ids = markers.map((marker) => marker.markerId.value).toSet();
          return const ColoredBox(color: Colors.white);
        },
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      final retry = tester
          .widget<StoreDataErrorView>(find.byType(StoreDataErrorView))
          .onRetry;
      retry();
      retry();
      await tester.pump();
      expect(calls, 2);
      expect(find.byType(StoreDataLoadingView), findsOneWidget);
      second.complete([searchableStores.last]);
      await tester.pump();
      first.completeError(StateError('late private failure'));
      await tester.pump();
      expect(ids, {searchableStores.last.id});
      expect(find.byType(StoreDataErrorView), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      retry();
      await tester.pump();
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ignores a store load completion after the map is disposed', (
    tester,
  ) async {
    final pendingLoad = Completer<List<StoreLocation>>();
    await pumpSearchableMap(
      tester,
      loader: () => pendingLoad.future,
      mapSurfaceBuilder: (markers, onMapTap) {
        return const ColoredBox(color: Colors.white);
      },
    );

    await tester.pumpWidget(const SizedBox.shrink());
    pendingLoad.complete(<StoreLocation>[searchableStores.first]);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'ready refresh hides the old snapshot and shows the replacement',
    (tester) async {
      final replacement = Completer<List<StoreLocation>>();
      var calls = 0;
      Set<String> markerIds = <String>{};
      await pumpSearchableMap(
        tester,
        loader: () {
          calls += 1;
          return calls == 1
              ? Future.value(searchableStores)
              : replacement.future;
        },
        mapSurfaceBuilder: (markers, _) {
          markerIds = markers.map((marker) => marker.markerId.value).toSet();
          return const ColoredBox(color: Colors.white);
        },
      );

      expect(find.byKey(storeDataRefreshButtonKey), findsOneWidget);
      expect(markerIds, {'alpha', 'beta', 'gamma'});
      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();

      expect(calls, 2);
      expect(find.byType(StoreDataRefreshingView), findsOneWidget);
      expect(find.byKey(storeSearchFieldKey), findsNothing);
      expect(find.text('Alpha Burger'), findsNothing);

      replacement.complete(<StoreLocation>[searchableStores.last]);
      await tester.pump();
      expect(find.byType(StoreDataRefreshingView), findsNothing);
      expect(markerIds, {'gamma'});
      expect(find.byKey(storeDataRefreshButtonKey), findsOneWidget);
    },
  );

  testWidgets('zero-store refresh can recover to a public snapshot', (
    tester,
  ) async {
    var calls = 0;
    var mapCreations = 0;
    Set<String> markerIds = <String>{};
    await pumpSearchableMap(
      tester,
      loader: () async {
        calls += 1;
        return calls == 1
            ? const <StoreLocation>[]
            : <StoreLocation>[searchableStores.first];
      },
      mapSurfaceBuilder: (markers, _) {
        mapCreations += 1;
        markerIds = markers.map((marker) => marker.markerId.value).toSet();
        return const ColoredBox(color: Colors.white);
      },
    );

    expect(find.byType(StoreDataEmptyView), findsOneWidget);
    expect(
      mapCreations,
      0,
      reason: 'do not initialize a map at the pilot camera',
    );
    expect(find.text('새로고침'), findsOneWidget);
    await tester.tap(find.byKey(storeDataRefreshButtonKey));
    await tester.pump();
    await tester.pump();

    expect(calls, 2);
    expect(find.byType(StoreDataEmptyView), findsNothing);
    expect(markerIds, {'alpha'});
    expect(mapCreations, 1);
  });

  testWidgets(
    'refresh preserves search filters nearby sort favorites and camera',
    (tester) async {
      var calls = 0;
      var zoomMoves = 0;
      Set<String> markerIds = <String>{};
      final favorites = _MemoryFavoriteStoreIdsStore({'alpha'});
      final replacement = StoreLocation(
        id: 'alpha',
        name: 'Alpha Burger Refreshed',
        address: 'Seoul Yongsan Alpha-ro 2',
        latitude: 37.531,
        longitude: 126.991,
        burgerStyle: 'smash',
        verificationStatus: 'verified',
      );
      await pumpSearchableMap(
        tester,
        loader: () async {
          calls += 1;
          return calls == 1 ? searchableStores : <StoreLocation>[replacement];
        },
        favoriteStoreIdsStore: favorites,
        currentLocationService: _FakeCurrentLocationService(),
        currentLocationCameraMover: (_, _) async {},
        mapZoomMover: (_) async => zoomMoves += 1,
        mapSurfaceBuilder: (markers, _) {
          markerIds = markers.map((marker) => marker.markerId.value).toSet();
          return const ColoredBox(color: Colors.white);
        },
      );

      await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(mapZoomInButtonKey));
      await tester.pump();
      expect(markerIds, {'alpha'});
      expect(zoomMoves, 1);

      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();
      await tester.pump();

      expect(calls, 2);
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller
            ?.text,
        'alpha',
      );
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isTrue,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(burgerStyleFilterKey(BurgerStyle.smash)),
            )
            .selected,
        isTrue,
      );
      expect(markerIds, {'alpha'});
      expect(find.text(replacement.name), findsOneWidget);
      expect(zoomMoves, 1);
      expect(favorites.storeIds, {'alpha'});
    },
  );

  testWidgets(
    'failed refresh keeps stale stores hidden until a manual retry succeeds',
    (tester) async {
      var calls = 0;
      Set<String> markerIds = <String>{};
      await pumpSearchableMap(
        tester,
        loader: () async {
          calls += 1;
          if (calls == 1) {
            return <StoreLocation>[searchableStores.first];
          }
          if (calls == 2) {
            throw StateError('offline private detail');
          }
          return <StoreLocation>[searchableStores.last];
        },
        mapSurfaceBuilder: (markers, _) {
          markerIds = markers.map((marker) => marker.markerId.value).toSet();
          return const ColoredBox(color: Colors.white);
        },
      );

      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();
      await tester.pump();
      expect(find.byType(StoreDataErrorView), findsOneWidget);
      expect(find.textContaining('offline private detail'), findsNothing);
      expect(find.byKey(storeSearchFieldKey), findsNothing);

      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();
      expect(calls, 3);
      expect(markerIds, {'gamma'});
      expect(find.byType(StoreDataErrorView), findsNothing);
    },
  );

  testWidgets(
    'background expiry hides an open detail and applies updated or removed data',
    (tester) async {
      var now = DateTime.utc(2026, 9, 7, 12);
      final updatedLoad = Completer<List<StoreLocation>>();
      final removedLoad = Completer<List<StoreLocation>>();
      var calls = 0;
      Set<Marker> markers = <Marker>{};
      final original = searchableStores.first;
      final updated = StoreLocation(
        id: original.id,
        name: 'Alpha Burger Updated',
        address: 'Seoul Yongsan Updated-ro 9',
        latitude: original.latitude,
        longitude: original.longitude,
        burgerStyle: original.burgerStyle,
        verificationStatus: 'verified',
      );
      await pumpSearchableMap(
        tester,
        loader: () {
          calls += 1;
          return switch (calls) {
            1 => Future.value(<StoreLocation>[original]),
            2 => updatedLoad.future,
            _ => removedLoad.future,
          };
        },
        storeClock: () => now,
        mapSurfaceBuilder: (nextMarkers, _) {
          markers = nextMarkers;
          return const ColoredBox(color: Colors.white);
        },
      );
      markers.single.onTap?.call();
      await tester.pump();
      await tester.tap(find.byKey(storePreviewDetailsButtonKey));
      await tester.pumpAndSettle();
      expect(find.text(original.address), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 2);
      expect(find.text(original.address), findsNothing);
      expect(find.text('매장 정보를 새로 확인하고 있습니다.'), findsOneWidget);

      updatedLoad.complete(<StoreLocation>[updated]);
      await tester.pump();
      expect(find.text(updated.name), findsOneWidget);
      expect(find.text(updated.address), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, 3);
      expect(find.text(updated.address), findsNothing);

      removedLoad.complete(const <StoreLocation>[]);
      await tester.pump();
      expect(find.text('이 매장은 더 이상 공개 목록에서 제공되지 않습니다.'), findsOneWidget);
    },
  );

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

  testWidgets('search filters fit at 320px width and 200% text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          );
        },
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async => searchableStores,
          mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
          favoriteStoreIdsStore: _MemoryFavoriteStoreIdsStore(),
        ),
      ),
    );
    await tester.pump();

    final searchRect = tester.getRect(find.byKey(storeSearchFieldKey));
    final favoritesRect = tester.getRect(find.byKey(favoritesOnlyFilterKey));
    await tester.scrollUntilVisible(
      find.byKey(burgerStyleAllFilterKey),
      200,
      scrollable: find.ancestor(
        of: find.byKey(favoritesOnlyFilterKey),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    final allFilter = tester.widget<ChoiceChip>(
      find.byKey(burgerStyleAllFilterKey),
    );

    expect(searchRect.left, greaterThanOrEqualTo(0));
    expect(searchRect.right, lessThanOrEqualTo(320));
    expect(searchRect.height, greaterThanOrEqualTo(64));
    expect(favoritesRect.top, greaterThanOrEqualTo(searchRect.bottom));
    expect(favoritesRect.left, greaterThanOrEqualTo(0));
    expect(favoritesRect.right, lessThanOrEqualTo(320));
    expect(allFilter.selected, isFalse);
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
      final requestedMenuStores = <String>[];
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
        menuRepository: _InlineMenuRepository((storeId) async {
          requestedMenuStores.add(storeId);
          return [
            MenuItem(
              id: 'menu-a',
              storeId: storeId,
              name: '알파 버거 메뉴',
              price: 12900,
              category: null,
              description: null,
              isSignature: true,
              displayOrder: 0,
            ),
          ];
        }),
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
      expect(find.text('알파 버거 메뉴'), findsOneWidget);
      expect(requestedMenuStores, ['alpha']);

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
    expect(allChip.selected, isFalse);
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

    final allFilterFinder = find.bySemanticsLabel('공개 매장 전체 보기');
    expect(allFilterFinder, findsOne);
    var allFilterNode = tester.getSemantics(allFilterFinder);
    expect(allFilterNode.flagsCollection.isButton, isTrue);
    expect(allFilterNode.flagsCollection.isSelected, Tristate.isFalse);

    await tester.tap(find.byKey(burgerStyleAllFilterKey));
    await tester.pump();
    allFilterNode = tester.getSemantics(allFilterFinder);
    expect(allFilterNode.flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pump();
    favoritesNode = tester.getSemantics(favoritesFinder);
    expect(favoritesNode.flagsCollection.isSelected, Tristate.isTrue);
    allFilterNode = tester.getSemantics(allFilterFinder);
    expect(allFilterNode.flagsCollection.isSelected, Tristate.isFalse);

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

List<String> _visibleSearchResultIds(WidgetTester tester) {
  return tester
      .widgetList<ListTile>(
        find.descendant(
          of: find.byKey(storeSearchResultsKey),
          matching: find.byType(ListTile),
        ),
      )
      .map((tile) => (tile.key! as ValueKey<String>).value)
      .map((key) => key.replaceFirst('store-search-result-', ''))
      .toList();
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
    this.checkPermissionHandler,
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
  final Future<LocationPermissionStatus> Function()? checkPermissionHandler;
  int checkPermissionCalls = 0;
  int requestPermissionCalls = 0;
  int currentLocationCalls = 0;
  int openAppSettingsCalls = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    checkPermissionCalls += 1;
    final handler = checkPermissionHandler;
    if (handler != null) {
      return handler();
    }
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
      final value = await handler();
      return value.capturedAt == null
          ? value.withCapturedAt(DateTime.now())
          : value;
    }
    final error = currentLocationError;
    if (error != null) {
      throw error;
    }
    return location.capturedAt == null
        ? location.withCapturedAt(DateTime.now())
        : location;
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls += 1;
    return true;
  }
}

class _InlineMenuRepository implements MenuRepository {
  _InlineMenuRepository(this._fetch);

  final Future<List<MenuItem>> Function(String storeId) _fetch;

  @override
  Future<List<MenuItem>> fetchMenusForStore(String storeId) => _fetch(storeId);
}
