import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
import 'package:burger_map_korea/features/info/presentation/app_info_screen.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_list_panel.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const listTab = ValueKey<String>('explorer-list-tab');
const mapTab = ValueKey<String>('explorer-map-tab');

final stores = List<StoreLocation>.generate(
  25,
  (i) => StoreLocation(
    id: 'public-$i',
    name: 'Burger $i',
    address: 'Yongsan road $i',
    latitude: 37.53 + i * .001,
    longitude: 126.99,
    burgerStyle: i.isEven ? 'classic' : 'smash',
    verificationStatus: 'verified',
  ),
);

class MemoryFavorites implements FavoriteStoreIdsStore {
  Set<String> ids = {'public-0', 'unpublished-uuid'};

  @override
  Future<Set<String>> load() async => Set.of(ids);

  @override
  Future<void> save(Set<String> storeIds) async {
    ids = Set.of(storeIds);
  }
}

Future<void> pumpExplorer(
  WidgetTester tester, {
  bool hasMapKey = true,
  Object? mapError,
  SupabaseStoreLoader? loader,
  StoreMapSurfaceBuilder? surface,
  FavoriteStoreIdsStore? favorites,
  StoreCameraMover? cameraMover,
  MapZoomMover? zoomMover,
  CurrentLocationService? locationService,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: MapScreen(
        config: AppConfig(
          environment: AppEnvironment.production,
          googleMapsApiKey: hasMapKey ? 'fake-map-key' : '',
          storeDataMode: StoreDataMode.supabase,
          supabaseUrl: 'https://unit.invalid',
          supabasePublishableKey: 'fake-publishable-key',
        ),
        initialMapError: mapError,
        supabaseStoreLoader: loader ?? () async => stores,
        favoriteStoreIdsStore: favorites ?? MemoryFavorites(),
        storeCameraMover: cameraMover,
        mapZoomMover: zoomMover,
        currentLocationService: locationService,
        mapSurfaceBuilder: surface ?? (_, _) => const SizedBox.expand(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'information action remains accessible on a compact pilot screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: MapScreen(
            config: const AppConfig(
              environment: AppEnvironment.development,
              googleMapsApiKey: '',
            ),
            favoriteStoreIdsStore: MemoryFavorites(),
            mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(appInfoButtonKey).hitTestable(), findsOneWidget);
      await tester.tap(find.byKey(appInfoButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(AppInfoScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'information stays reachable during loading error and empty states',
    (tester) async {
      final pending = Completer<List<StoreLocation>>();
      var loads = 0;
      await pumpExplorer(
        tester,
        hasMapKey: false,
        loader: () {
          loads++;
          return loads == 1 ? pending.future : Future.value([]);
        },
      );
      for (final state in ['loading', 'error', 'empty']) {
        expect(find.text('용산구 우선'), findsOneWidget);
        await tester.tap(find.byKey(appInfoButtonKey));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        expect(find.byType(AppInfoScreen), findsOneWidget, reason: state);
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump();
        if (state == 'loading') {
          pending.completeError(StateError('synthetic load failure'));
          await tester.pump();
        } else if (state == 'error') {
          await tester.tap(find.text('다시 시도'));
          await tester.pump();
        }
      }
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'information round trip preserves list search favorites and nearby',
    (tester) async {
      final favorites = MemoryFavorites();
      await pumpExplorer(
        tester,
        favorites: favorites,
        locationService: NearbyLocation(),
      );
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(appInfoButtonKey));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller!
            .text,
        'Burger',
      );
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isTrue,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isTrue,
      );
      expect(find.byType(StoreListPanel), findsOneWidget);
      expect(favorites.ids, {'public-0', 'unpublished-uuid'});
    },
  );

  for (final missingKey in [true, false]) {
    testWidgets(
      'list and detail remain usable with ${missingKey ? 'missing Maps key' : 'map failure'}',
      (tester) async {
        await pumpExplorer(
          tester,
          hasMapKey: !missingKey,
          mapError: missingKey ? null : StateError('private map error'),
        );
        await tester.tap(find.byKey(listTab));
        await tester.pump();
        expect(find.text('Burger 0'), findsOneWidget);
        await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger 1');
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('store-list-item-public-1')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(storeAddressCopyButtonKey), findsOneWidget);
        expect(find.byKey(storeFavoriteButtonKey), findsOneWidget);
        expect(find.textContaining('private map error'), findsNothing);
      },
    );
  }

  testWidgets('a map that never becomes ready cannot block list navigation', (
    tester,
  ) async {
    var calls = 0;
    await pumpExplorer(
      tester,
      loader: () async {
        calls++;
        return stores;
      },
      surface: (_, _) => const CircularProgressIndicator(),
    );
    await tester.tap(find.byKey(listTab));
    await tester.pump();
    expect(find.text('매장 25개'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('store-list-item-public-0')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(storeAddressCopyButtonKey), findsOneWidget);
    expect(calls, 1);
  });

  testWidgets(
    'tabs remain reachable through loading error empty and recovery',
    (tester) async {
      final initial = Completer<List<StoreLocation>>();
      var calls = 0;
      await pumpExplorer(
        tester,
        loader: () {
          calls++;
          return calls == 1
              ? initial.future
              : Future.value(calls == 2 ? [] : stores);
        },
      );
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      expect(find.byType(StoreDataLoadingView), findsOneWidget);
      initial.completeError(StateError('private-data-error'));
      await tester.pump();
      expect(find.byType(StoreDataErrorView), findsOneWidget);
      await tester.tap(find.byKey(mapTab));
      await tester.pump();
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      expect(calls, 1);
      expect(find.textContaining('private-data-error'), findsNothing);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(find.byType(StoreDataEmptyView), findsOneWidget);
      expect(find.text('검색 결과가 없습니다.'), findsNothing);
      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();
      expect(find.text('매장 25개'), findsOneWidget);
      expect(calls, 3);
    },
  );

  testWidgets(
    'refresh and tabs retain map instance but clear its markers and stale list',
    (tester) async {
      var calls = 0;
      var creates = 0;
      var disposes = 0;
      var markerIds = <String>{};
      final refresh = Completer<List<StoreLocation>>();
      await pumpExplorer(
        tester,
        loader: () {
          calls++;
          return calls == 2
              ? refresh.future
              : Future.value(calls == 1 ? stores : [stores.last]);
        },
        surface: (markers, _) {
          markerIds = markers.map((m) => m.markerId.value).toSet();
          return MapLifetimeProbe(
            onCreate: () => creates++,
            onDispose: () => disposes++,
          );
        },
      );
      expect(creates, 1);
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();
      expect(markerIds, isEmpty);
      expect(find.text('Burger 0'), findsNothing);
      expect(find.byType(StoreDataRefreshingView), findsOneWidget);
      await tester.tap(find.byKey(mapTab));
      await tester.pump();
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      expect(calls, 2);
      refresh.completeError(StateError('offline'));
      await tester.pump();
      expect(find.byType(StoreDataErrorView), findsOneWidget);
      expect(find.text('Burger 0'), findsNothing);
      expect(markerIds, isEmpty);
      expect(creates, 1);
      expect(disposes, 0);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      expect(markerIds, {'public-24'});
      expect(find.text('Burger 24'), findsOneWidget);
      expect(find.text('Burger 0'), findsNothing);
      expect(creates, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(disposes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list scroll survives detail and map round trips without fetching',
    (tester) async {
      var calls = 0;
      await pumpExplorer(
        tester,
        loader: () async {
          calls++;
          return stores;
        },
      );
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      final scrollFinder = find.byKey(
        const PageStorageKey<String>('public-store-list'),
      );
      await tester.drag(scrollFinder, const Offset(0, -750));
      await tester.pumpAndSettle();
      final scroll = tester.widget<CustomScrollView>(scrollFinder).controller!;
      final offset = scroll.offset;
      expect(offset, greaterThan(0));
      final row = find.byType(ListTile).hitTestable().first;
      await tester.tap(row);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(storeDetailBackButtonKey));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, .1));
      await tester.tap(find.byKey(mapTab));
      await tester.pump();
      await tester.tap(find.byKey(listTab));
      await tester.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, .1));
      expect(calls, 1);
    },
  );

  testWidgets(
    'list favorites use shared saved UUIDs and preserve unpublished IDs',
    (tester) async {
      final favorites = MemoryFavorites();
      await pumpExplorer(tester, favorites: favorites);
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.pump();
      expect(find.text('매장 1개'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('store-list-item-public-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(storeFavoriteButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(storeDetailBackButtonKey));
      await tester.pumpAndSettle();
      expect(find.text('즐겨찾기한 공개 매장이 없습니다.'), findsOneWidget);
      expect(favorites.ids, {'unpublished-uuid'});
      await tester.tap(find.text('조건 초기화'));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'no match');
      await tester.pump();
      expect(find.text('검색 결과가 없습니다.'), findsOneWidget);
      expect(find.byType(StoreDataEmptyView), findsNothing);
    },
  );

  testWidgets(
    'search style favorites nearby order and zoom survive list switching',
    (tester) async {
      final favorites = MemoryFavorites()
        ..ids = {'public-0', 'public-2', 'unpublished-uuid'};
      final zooms = <double>[];
      final moves = <String>[];
      await pumpExplorer(
        tester,
        favorites: favorites,
        locationService: NearbyLocation(),
        zoomMover: (zoom) async => zooms.add(zoom),
        cameraMover: (store) async => moves.add(store.id),
      );
      await tester.tap(find.byKey(mapZoomInButtonKey));
      await tester.pump();
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.tap(find.byKey(nearbySortFilterKey));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(burgerStyleFilterKey(BurgerStyle.classic)),
      );
      await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.classic)));
      await tester.pump();
      final panel = tester.widget<StoreListPanel>(find.byType(StoreListPanel));
      expect(panel.stores.map((s) => s.id), ['public-2', 'public-0']);
      await tester.tap(find.byKey(const ValueKey('store-list-map-public-2')));
      await tester.pumpAndSettle();
      expect(moves, ['public-2']);
      expect(find.byType(StorePreviewCard), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller!
            .text,
        'Burger',
      );
      expect(
        tester.widget<FilterChip>(find.byKey(favoritesOnlyFilterKey)).selected,
        isTrue,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isTrue,
      );
      await tester.tap(find.byKey(mapZoomInButtonKey));
      await tester.pump();
      expect(zooms.length, 2);
      expect(zooms.last, zooms.first + mapZoomStep);
      expect(favorites.ids, {'public-0', 'public-2', 'unpublished-uuid'});
    },
  );

  testWidgets(
    'camera failure leaves list and detail usable without unhandled errors',
    (tester) async {
      await pumpExplorer(
        tester,
        cameraMover: (_) async => throw StateError('private camera failure'),
        zoomMover: (_) async => throw StateError('private zoom failure'),
      );
      await tester.tap(find.byKey(mapZoomInButtonKey));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('store-list-map-public-0')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('private camera'), findsNothing);
      await tester.tap(find.byKey(listTab));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('store-list-item-public-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(storeAddressCopyButtonKey), findsOneWidget);
    },
  );

  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    testWidgets(
      'list remains scrollable with 200 percent text at $size and keyboard',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        await pumpExplorer(tester, textScaler: const TextScaler.linear(2));
        await tester.tap(find.byKey(listTab));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger 0');
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * .3);
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('store-list-item-public-0')),
          80,
          scrollable: find
              .descendant(
                of: find.byKey(
                  const PageStorageKey<String>('public-store-list'),
                ),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump();
        expect(find.byKey(listTab).hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('store-list-item-public-0')).hitTestable(),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('empty and error actions fit landscape at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    await pumpExplorer(
      tester,
      textScaler: const TextScaler.linear(2),
      loader: () async {
        if (++calls == 1) return [];
        throw StateError('offline');
      },
    );
    await tester.tap(find.byKey(listTab));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byKey(storeDataRefreshButtonKey));
    await tester.tap(find.byKey(storeDataRefreshButtonKey));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('다시 시도'));
    expect(find.text('다시 시도').hitTestable(), findsOneWidget);
    expect(find.byKey(mapTab).hitTestable(), findsOneWidget);
  });

  testWidgets(
    'late native marker taps cannot restore stale selected information',
    (tester) async {
      VoidCallback? oldTap;
      var calls = 0;
      final replacement = Completer<List<StoreLocation>>();
      await pumpExplorer(
        tester,
        loader: () =>
            ++calls == 1 ? Future.value([stores.first]) : replacement.future,
        surface: (markers, _) {
          if (oldTap == null && markers.isNotEmpty) {
            oldTap = markers.first.onTap;
          }
          return const SizedBox.expand();
        },
      );
      await tester.tap(find.byKey(storeDataRefreshButtonKey));
      await tester.pump();
      oldTap!();
      await tester.pump();
      expect(find.byType(StorePreviewCard), findsNothing);
      replacement.complete([
        StoreLocation(
          id: stores.first.id,
          name: 'New name',
          address: 'New address',
          latitude: 37.53,
          longitude: 126.99,
          burgerStyle: 'classic',
        ),
      ]);
      await tester.pump();
      oldTap!();
      await tester.pump();
      expect(find.text('New name'), findsOneWidget);
      expect(find.text('Burger 0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      oldTap!();
      expect(tester.takeException(), isNull);
    },
  );
}

class MapLifetimeProbe extends StatefulWidget {
  const MapLifetimeProbe({
    super.key,
    required this.onCreate,
    required this.onDispose,
  });
  final VoidCallback onCreate;
  final VoidCallback onDispose;
  @override
  State<MapLifetimeProbe> createState() => _MapLifetimeProbeState();
}

class _MapLifetimeProbeState extends State<MapLifetimeProbe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class NearbyLocation implements CurrentLocationService {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermissionStatus> checkPermission() async =>
      LocationPermissionStatus.whileInUse;
  @override
  Future<LocationPermissionStatus> requestPermission() async =>
      LocationPermissionStatus.whileInUse;
  @override
  Future<CurrentLocation> getCurrentLocation() async => CurrentLocation(
    latitude: 37.532,
    longitude: 126.99,
    capturedAt: DateTime.now(),
  );
  @override
  Future<bool> openAppSettings() async => true;
}
