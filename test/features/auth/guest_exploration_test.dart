import 'dart:async';

import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/login_screen.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/menu/domain/menu_item.dart';
import 'package:burger_map_korea/features/menu/domain/menu_repository.dart';
import 'package:burger_map_korea/features/reviews/domain/review.dart';
import 'package:burger_map_korea/features/reviews/domain/review_repository.dart';
import 'package:burger_map_korea/features/reviews/domain/review_report.dart';
import 'package:burger_map_korea/features/reviews/presentation/store_review_section.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guest review login returns to the same store editor', (
    tester,
  ) async {
    final auth = _AuthRepository();
    final reviews = _EmptyReviewRepository();
    final authBootstrap = Completer<AuthController>();
    await tester.pumpWidget(
      BurgerMapApp(
        config: const AppConfig(
          environment: AppEnvironment.development,
          storeDataMode: StoreDataMode.supabase,
          googleMapsApiKey: 'test-key',
          supabaseUrl: 'https://unit.invalid',
          supabasePublishableKey: 'publishable-test-value',
        ),
        authControllerLoader: () => authBootstrap.future,
        supabaseStoreLoader: () async => [
          StoreLocation(
            id: 'store-alpha',
            name: 'Alpha Burger',
            address: 'Seoul Yongsan Alpha-ro 1',
            latitude: 37.53,
            longitude: 126.99,
            burgerStyle: 'smash',
            verificationStatus: 'verified',
          ),
        ],
        favoriteStoreIdsStore: _FavoritesStore(),
        reviewRepository: reviews,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(storeSearchFieldKey), 'Alpha');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('store-search-result-store-alpha')),
    );
    await tester.pump();
    await tester.tap(find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    await tester.ensureVisible(find.byKey(reviewWriteButtonKey));
    await tester.tap(find.byKey(reviewWriteButtonKey));
    authBootstrap.complete(AuthController(auth));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(find.byKey(reviewContentFieldKey), findsNothing);
    await tester.ensureVisible(find.byKey(reviewWriteButtonKey));
    await tester.tap(find.byKey(reviewWriteButtonKey));
    await tester.pumpAndSettle();
    auth.signIn();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(find.text('Alpha Burger'), findsOneWidget);
    expect(find.byKey(reviewContentFieldKey), findsOneWidget);
    expect(reviews.lastUserId, 'user-a');
  });

  testWidgets('guest can read store/menu and keep favorites and map context', (
    tester,
  ) async {
    final auth = _AuthRepository();
    final favorites = _FavoritesStore();
    final menu = _EmptyMenuRepository();
    var storeLoads = 0;
    const storeId = 'store-alpha';
    await tester.pumpWidget(
      BurgerMapApp(
        config: const AppConfig(
          environment: AppEnvironment.development,
          storeDataMode: StoreDataMode.supabase,
          googleMapsApiKey: 'test-key',
          supabaseUrl: 'https://unit.invalid',
          supabasePublishableKey: 'publishable-test-value',
        ),
        authControllerLoader: () async => AuthController(auth),
        supabaseStoreLoader: () async {
          storeLoads++;
          return [
            StoreLocation(
              id: storeId,
              name: 'Alpha Burger',
              address: 'Seoul Yongsan Alpha-ro 1',
              latitude: 37.53,
              longitude: 126.99,
              burgerStyle: 'smash',
              verificationStatus: 'verified',
            ),
          ];
        },
        favoriteStoreIdsStore: favorites,
        menuRepository: menu,
        mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
      ),
    );
    await tester.pump();
    expect(find.byType(MapScreen), findsOneWidget);
    final mapState = tester.state(find.byType(MapScreen));
    expect(find.byType(LoginScreen), findsNothing);

    await tester.tap(find.byKey(burgerStyleFilterKey(BurgerStyle.smash)));
    await tester.pump();
    await tester.enterText(find.byKey(storeSearchFieldKey), 'Alpha');
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('store-search-result-store-alpha')),
    );
    await tester.pump();
    expect(find.byType(StorePreviewCard), findsOneWidget);

    await tester.tap(find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(menu.requestedIds, [storeId]);
    expect(find.text('아직 확인된 메뉴 정보가 없습니다.'), findsOneWidget);
    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pump();
    expect(favorites.ids, {storeId});

    await tester.tap(find.byKey(storeDetailBackButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(loginButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(StorePreviewCard), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(storeSearchFieldKey))
          .controller
          ?.text,
      'Alpha',
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(burgerStyleFilterKey(BurgerStyle.smash)),
          )
          .selected,
      isTrue,
    );
    expect(storeLoads, 1);

    await tester.tap(find.byKey(loginButtonKey));
    await tester.pumpAndSettle();
    auth.signIn();
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(logoutButtonKey), findsOneWidget);
    expect(find.byType(StorePreviewCard), findsOneWidget);
    expect(identical(tester.state(find.byType(MapScreen)), mapState), isTrue);
    expect(favorites.ids, {storeId});

    await tester.tap(find.byKey(logoutButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '로그아웃'));
    await tester.pumpAndSettle();
    expect(find.byKey(loginButtonKey), findsOneWidget);
    expect(find.byType(StorePreviewCard), findsOneWidget);
    expect(identical(tester.state(find.byType(MapScreen)), mapState), isTrue);
    expect(favorites.ids, {storeId});
    expect(favorites.loadCalls, 1);
    expect(storeLoads, 1);
  });
}

class _AuthRepository implements AuthRepository {
  String? userId;
  final _changes = StreamController<String?>.broadcast();

  void signIn() {
    userId = 'user-a';
    _changes.add(userId);
  }

  @override
  String? get currentUserId => userId;

  @override
  Stream<String?> get userChanges => _changes.stream;

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() async =>
      const AuthUserProfile(id: 'user-a', nickname: '버거팬');

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) =>
      throw UnimplementedError();

  @override
  Future<void> sendMagicLink(String email) async {}

  @override
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {
    userId = null;
    _changes.add(null);
  }
}

class _FavoritesStore implements FavoriteStoreIdsStore {
  Set<String> ids = {};
  int loadCalls = 0;

  @override
  Future<Set<String>> load() async {
    loadCalls++;
    return Set.of(ids);
  }

  @override
  Future<void> save(Set<String> storeIds) async => ids = Set.of(storeIds);
}

class _EmptyMenuRepository implements MenuRepository {
  final requestedIds = <String>[];

  @override
  Future<List<MenuItem>> fetchMenusForStore(String storeId) async {
    requestedIds.add(storeId);
    return [];
  }
}

class _EmptyReviewRepository implements ReviewRepository {
  String? lastUserId;

  @override
  Future<List<StoreReview>> loadForStore(
    String storeId, {
    String? userId,
  }) async {
    lastUserId = userId;
    return [];
  }

  @override
  Future<void> create({
    required String storeId,
    required int rating,
    required String? content,
  }) async {}

  @override
  Future<void> update({
    required String reviewId,
    required int rating,
    required String? content,
  }) async {}

  @override
  Future<void> delete(String reviewId) async {}

  @override
  Future<void> report({
    required String reviewId,
    required ReviewReportReason reason,
    required String? detail,
  }) async {}
}
