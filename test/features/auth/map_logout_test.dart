import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('map logout requires confirmation and keeps favorites', (
    tester,
  ) async {
    var signOutCalls = 0;
    final favorites = _MemoryFavorites({'store-a'});
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
          ),
          favoriteStoreIdsStore: favorites,
          mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
          onSignOut: () async => signOutCalls++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(logoutButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('이 기기에서 로그아웃할까요? 즐겨찾기는 그대로 유지됩니다.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '취소'));
    await tester.pumpAndSettle();
    expect(signOutCalls, 0);

    await tester.tap(find.byKey(logoutButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '로그아웃'));
    await tester.pumpAndSettle();

    expect(signOutCalls, 1);
    expect(favorites.ids, {'store-a'});
    expect(favorites.saveCalls, 0);
  });
}

class _MemoryFavorites implements FavoriteStoreIdsStore {
  _MemoryFavorites(Set<String> ids) : ids = Set<String>.of(ids);

  Set<String> ids;
  int saveCalls = 0;

  @override
  Future<Set<String>> load() async => Set<String>.unmodifiable(ids);

  @override
  Future<void> save(Set<String> storeIds) async {
    saveCalls++;
    ids = Set<String>.of(storeIds);
  }
}
