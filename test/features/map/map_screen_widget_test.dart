import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../support/staging_fixture.dart';

void main() {
  final searchableStores = <StoreLocation>[
    StoreLocation(
      id: 'alpha',
      name: 'Alpha Burger',
      address: 'Seoul Yongsan Alpha-ro 1',
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: '미분류',
      verificationStatus: 'verified',
    ),
    StoreLocation(
      id: 'beta',
      name: 'Beta Kitchen',
      address: 'Seoul Itaewon Burger-gil 2',
      latitude: 37.54,
      longitude: 127.0,
      burgerStyle: '미분류',
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
        ),
      ),
    );
    await tester.pump();
  }

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

    await tester.pumpWidget(testApp(StorePreviewCard(store: store)));

    expect(find.text('검수 데이터'), findsOneWidget);
    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(find.text(store.burgerStyle), findsOneWidget);
  });

  testWidgets('shows missing API key guidance', (tester) async {
    await tester.pumpWidget(testApp(const MissingApiKeyView()));

    expect(find.text('Google Maps API 키가 설정되지 않았습니다'), findsOneWidget);
    expect(find.textContaining('GOOGLE_MAPS_API_KEY'), findsOneWidget);
    expect(find.text(itaewonStoreLocations.first.name), findsOneWidget);
  });

  testWidgets('shows map error guidance', (tester) async {
    await tester.pumpWidget(testApp(const MapErrorView(error: 'boom')));

    expect(find.textContaining('지도를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
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

    await tester.pumpWidget(testApp(StorePreviewCard(store: store)));

    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(find.text('미분류'), findsOneWidget);
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
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
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
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
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
    var markerCount = 0;
    await pumpSearchableMap(
      tester,
      loader: () async => searchableStores,
      mapSurfaceBuilder: (markers, onMapTap) {
        markerCount = markers.length;
        return const ColoredBox(color: Colors.white);
      },
    );

    expect(markerCount, 3);
    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();

    expect(markerCount, 1);
    expect(find.text('Alpha Burger'), findsOneWidget);
    expect(find.text('Beta Kitchen'), findsNothing);

    await tester.tap(find.byKey(storeSearchClearButtonKey));
    await tester.pump();

    expect(markerCount, 3);
    expect(find.byKey(storeSearchResultsKey), findsNothing);
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
    await tester.enterText(find.byKey(storeSearchFieldKey), 'alpha');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('store-search-result-alpha')),
    );
    await tester.pump();

    expect(loadCalls, 1);
  });

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
          .firstWhere((marker) => marker.markerId.value == 'beta')
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
}
