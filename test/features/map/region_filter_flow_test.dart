import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/domain/store_region.dart';
import 'package:burger_map_korea/features/stores/presentation/region_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

StoreRegion region(String code, String name) => StoreRegion(
  sidoCode: '11',
  sidoName: '서울',
  sigunguCode: '11170',
  sigunguName: '용산구',
  dongCode: code,
  dongName: name,
);

final fixtures = [
  StoreLocation(
    id: 'uuid-a',
    name: 'Burger A',
    latitude: 37.51,
    longitude: 127.0,
    address: '테스트 A',
    burgerStyle: 'classic',
    verificationStatus: 'verified',
    region: region('1117010100', '후암동'),
  ),
  StoreLocation(
    id: 'uuid-b',
    name: 'Burger B',
    latitude: 37.52,
    longitude: 127.0,
    address: '테스트 B',
    burgerStyle: 'classic',
    verificationStatus: 'verified',
    region: region('1117013000', '이태원동'),
  ),
  StoreLocation(
    id: 'uuid-c',
    name: 'Burger C',
    latitude: 37.53,
    longitude: 127.0,
    address: '테스트 C',
    burgerStyle: 'classic',
    verificationStatus: 'verified',
  ),
];

class MemoryFavorites implements FavoriteStoreIdsStore {
  Set<String> ids = {'uuid-a', 'uuid-c', 'unpublished-uuid'};
  @override
  Future<Set<String>> load() async => Set.of(ids);
  @override
  Future<void> save(Set<String> storeIds) async {
    ids = Set.of(storeIds);
  }
}

class LocationFixture implements CurrentLocationService {
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
    latitude: 37.5,
    longitude: 127,
    capturedAt: DateTime.now(),
  );
  @override
  Future<bool> openAppSettings() async => true;
}

Future<void> pumpMap(
  WidgetTester tester, {
  required MemoryFavorites favorites,
  required ValueChanged<Set<String>> markers,
  SupabaseStoreLoader? loader,
  DateTime Function()? clock,
  StoreCameraMover? camera,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: MapScreen(
        config: const AppConfig(
          environment: AppEnvironment.development,
          storeDataMode: StoreDataMode.supabase,
          googleMapsApiKey: 'test-only',
          supabaseUrl: 'https://unit.invalid',
          supabasePublishableKey: 'test-only',
        ),
        supabaseStoreLoader: loader ?? () async => fixtures,
        favoriteStoreIdsStore: favorites,
        currentLocationService: LocationFixture(),
        storeClock: clock,
        storeCameraMover: camera,
        mapSurfaceBuilder: (Set<Marker> values, _) {
          markers(values.map((marker) => marker.markerId.value).toSet());
          return const SizedBox.expand();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> tapControl(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, Key key, String label) async {
  final dropdown = find.descendant(
    of: find.byKey(key),
    matching: find.byType(DropdownButton<String>),
  );
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> chooseHuam(WidgetTester tester) async {
  await tapControl(tester, regionFilterButtonKey);
  await pick(tester, regionSidoDropdownKey, '서울');
  await pick(tester, regionSigunguDropdownKey, '용산구');
  await pick(tester, regionDongDropdownKey, '후암동');
  await tapControl(tester, regionApplyButtonKey);
}

void main() {
  testWidgets(
    'region combines with search favorites style nearby and All clears every criterion',
    (tester) async {
      final favorites = MemoryFavorites();
      var visible = <String>{};
      var cameraMoves = 0;
      await pumpMap(
        tester,
        favorites: favorites,
        markers: (ids) => visible = ids,
        camera: (_) async {
          cameraMoves++;
        },
      );
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
      await tapControl(tester, favoritesOnlyFilterKey);
      await tapControl(tester, nearbySortFilterKey);
      await tapControl(tester, burgerStyleFilterKey(BurgerStyle.classic));
      await chooseHuam(tester);
      expect(visible, {'uuid-a'});
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
      expect(find.textContaining('지역 미확정 1곳'), findsOneWidget);
      expect(favorites.ids, {'uuid-a', 'uuid-c', 'unpublished-uuid'});
      expect(cameraMoves, 0);
      await tapControl(tester, burgerStyleAllFilterKey);
      expect(visible, {'uuid-a', 'uuid-b', 'uuid-c'});
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(regionFilterButtonKey)).selected,
        isFalse,
      );
      expect(
        tester.widget<FilterChip>(find.byKey(nearbySortFilterKey)).selected,
        isFalse,
      );
      expect(favorites.ids, {'uuid-a', 'uuid-c', 'unpublished-uuid'});
      await tapControl(tester, burgerStyleAllFilterKey);
      expect(find.byKey(storeSearchResultsKey), findsNothing);
      expect(visible, {'uuid-a', 'uuid-b', 'uuid-c'});
    },
  );

  testWidgets(
    'region cancel preserves applied path and region clear leaves search intact',
    (tester) async {
      var visible = <String>{};
      await pumpMap(
        tester,
        favorites: MemoryFavorites(),
        markers: (ids) => visible = ids,
      );
      await tester.enterText(find.byKey(storeSearchFieldKey), 'Burger');
      await chooseHuam(tester);
      await tapControl(tester, regionFilterButtonKey);
      await pick(tester, regionDongDropdownKey, '이태원동');
      await tapControl(tester, regionCancelButtonKey);
      expect(visible, {'uuid-a'});
      await tapControl(tester, regionFilterButtonKey);
      await tapControl(tester, regionClearButtonKey);
      expect(visible, {'uuid-a', 'uuid-b', 'uuid-c'});
      expect(
        tester
            .widget<TextField>(find.byKey(storeSearchFieldKey))
            .controller!
            .text,
        'Burger',
      );
    },
  );

  testWidgets(
    'expiry closes stale region menu; error and retry retain selected path without stale stores',
    (tester) async {
      var now = DateTime.utc(2026, 9, 14);
      var requests = 0;
      final pending = Completer<List<StoreLocation>>();
      var visible = <String>{};
      await pumpMap(
        tester,
        favorites: MemoryFavorites(),
        markers: (ids) => visible = ids,
        clock: () => now,
        loader: () {
          requests++;
          if (requests == 1) return Future.value(fixtures);
          if (requests == 2) return pending.future;
          return Future.value([fixtures[1]]);
        },
      );
      await chooseHuam(tester);
      await tapControl(tester, regionFilterButtonKey);
      await tester.tap(
        find.descendant(
          of: find.byKey(regionDongDropdownKey),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(minutes: 5));
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(find.text('후암동'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byKey(regionApplyButtonKey)).onPressed,
        isNull,
      );
      pending.completeError(Exception('test read failure'));
      await tester.pumpAndSettle();
      expect(find.text('후암동'), findsNothing);
      await tapControl(tester, regionCancelButtonKey);
      await tester.tap(find.text('다시 시도').last);
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(visible, isEmpty);
      expect(
        tester.widget<FilterChip>(find.byKey(regionFilterButtonKey)).selected,
        isTrue,
      );
      await tapControl(tester, regionFilterButtonKey);
      expect(find.textContaining('현재 매장 목록에서 선택할 수 없습니다'), findsOneWidget);
      await tapControl(tester, regionClearButtonKey);
      expect(visible, {'uuid-b'});
    },
  );
}
