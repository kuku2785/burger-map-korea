import 'dart:async';

import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() {
  final stores = ['a', 'b']
      .map(
        (id) => StoreLocation(
          id: id,
          name: 'Burger $id',
          address: 'Yongsan $id',
          latitude: 37.53,
          longitude: 126.99,
          burgerStyle: 'classic',
          verificationStatus: 'verified',
        ),
      )
      .toList();
  late Set<Marker> markers;
  Future<void> mount(
    WidgetTester tester,
    _Store storage, {
    SupabaseStoreLoader? loader,
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'test',
          ),
          supabaseStoreLoader: loader ?? () async => stores,
          favoriteStoreIdsStore: storage,
          mapSurfaceBuilder: (next, _) {
            markers = next;
            return const ColoredBox(color: Colors.white);
          },
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, String id) async {
    markers.firstWhere((marker) => marker.markerId.value == id).onTap!();
    await tester.pump();
    await tester.tap(find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byKey(storeDetailBackButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'delayed read blocks detail writes then enables the same open screen',
    (tester) async {
      final storage = _Store();
      final delayed = Completer<Set<String>>();
      storage.read = () => delayed.future;
      await mount(tester, storage);
      await open(tester, 'b');
      expect(
        tester.widget<IconButton>(find.byKey(storeFavoriteButtonKey)).onPressed,
        isNull,
      );
      expect(storage.writes, isEmpty);
      delayed.complete({'a'});
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(find.byKey(storeFavoriteButtonKey)).onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(storeFavoriteButtonKey));
      await tester.pumpAndSettle();
      expect(storage.ids, {'a', 'b'});
      await back(tester);
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.pump();
      expect(markers.map((marker) => marker.markerId.value).toSet(), {
        'a',
        'b',
      });
    },
  );

  testWidgets(
    'read error retry keeps saved favorites and disables writes until recovered',
    (tester) async {
      final storage = _Store()..ids = {'a'};
      storage.read = () async => throw StateError('read');
      await mount(tester, storage);
      expect(find.byKey(favoritesRetryButtonKey), findsOneWidget);
      await open(tester, 'b');
      expect(
        tester.widget<IconButton>(find.byKey(storeFavoriteButtonKey)).onPressed,
        isNull,
      );
      await back(tester);
      storage.read = null;
      await tester.tap(find.byKey(favoritesRetryButtonKey));
      await tester.pumpAndSettle();
      await open(tester, 'b');
      await tester.tap(find.byKey(storeFavoriteButtonKey));
      await tester.pumpAndSettle();
      expect(storage.ids, {'a', 'b'});
    },
  );

  testWidgets(
    'favorites restore retry is accessible while stores fail on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = _Store()..ids = {'a'};
      storage.read = () async => throw StateError('restore failed');
      var storeOffline = true;
      await mount(
        tester,
        storage,
        textScaler: TextScaler.linear(2),
        loader: () async {
          if (storeOffline) throw StateError('store request failed');
          return stores;
        },
      );
      expect(find.byType(StoreDataErrorView), findsOneWidget);
      final restoreRetry = find.byKey(favoritesRetryButtonKey);
      expect(restoreRetry.hitTestable(), findsOneWidget);
      expect(storage.writes, isEmpty);
      storage.read = null;
      await tester.tap(restoreRetry);
      await tester.pumpAndSettle();
      expect(restoreRetry, findsNothing);
      expect(storage.ids, {'a'});
      expect(find.byType(StoreDataErrorView), findsOneWidget);
      storeOffline = false;
      await tester.tap(
        find.descendant(
          of: find.byType(StoreDataErrorView),
          matching: find.text('다시 시도'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.pump();
      expect(markers.map((m) => m.markerId.value).toSet(), {'a'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'save failure after leaving detail remains visible and retryable',
    (tester) async {
      final storage = _Store()..ids = {'a'};
      final pending = Completer<void>();
      storage.write = (_) => pending.future;
      await mount(tester, storage);
      await open(tester, 'b');
      await tester.tap(find.byKey(storeFavoriteButtonKey));
      await tester.pump();
      await back(tester);
      pending.completeError(StateError('save failed after navigation'));
      await tester.pumpAndSettle();
      expect(storage.ids, {'a'});
      final retry = find.byKey(const ValueKey('favorites-save-retry-button'));
      expect(retry, findsOneWidget);
      await tester.tap(find.byKey(explorerListTabKey));
      await tester.pump();
      expect(retry, findsOneWidget);
      storage.write = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(storage.ids, {'a', 'b'});
      expect(retry, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, storage);
      await tester.pump();
      await tester.tap(find.byKey(favoritesOnlyFilterKey));
      await tester.pump();
      expect(markers.map((m) => m.markerId.value).toSet(), {'a', 'b'});
      expect(tester.takeException(), isNull);
    },
  );

  for (final fail in [false, true]) {
    testWidgets(
      'save across routes preserves queue after ${fail ? 'failure' : 'success'}',
      (tester) async {
        final storage = _Store();
        final pending = Completer<void>();
        storage.write = (ids) =>
            storage.writes.length == 1 ? pending.future : Future<void>.value();
        await mount(tester, storage);
        await open(tester, 'a');
        await tester.tap(find.byKey(storeFavoriteButtonKey));
        await tester.pump();
        await back(tester);
        await open(tester, 'a');
        expect(
          tester
              .widget<IconButton>(find.byKey(storeFavoriteButtonKey))
              .onPressed,
          isNull,
        );
        await back(tester);
        await open(tester, 'b');
        await tester.tap(find.byKey(storeFavoriteButtonKey));
        await tester.pump();
        expect(storage.writes, [
          {'a'},
        ]);
        if (fail) {
          pending.completeError(StateError('write'));
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(storage.ids, fail ? {'b'} : {'a', 'b'});
        expect(tester.takeException(), isNull);
        await back(tester);
        await open(tester, 'a');
        await tester.tap(find.byKey(storeFavoriteButtonKey));
        await tester.pumpAndSettle();
        expect(storage.ids, fail ? {'a', 'b'} : {'b'});
      },
    );
  }
}

class _Store implements FavoriteStoreIdsStore {
  Set<String> ids = {};
  final List<Set<String>> writes = [];
  Future<Set<String>> Function()? read;
  Future<void> Function(Set<String>)? write;
  @override
  Future<Set<String>> load() async =>
      read == null ? Set.of(ids) : await read!();
  @override
  Future<void> save(Set<String> next) async {
    writes.add(Set.of(next));
    await write?.call(next);
    ids = Set.of(next);
  }
}
