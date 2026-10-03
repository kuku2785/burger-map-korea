import 'dart:async';

import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/login_screen.dart';
import 'package:burger_map_korea/features/auth/presentation/nickname_onboarding_screen.dart';
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
  for (final needsProfile in [false, true]) {
    testWidgets('guest Google report return survives repeated auth and rebuild '
        '(nickname required: $needsProfile)', (tester) async {
      final googleCompletion = Completer<void>();
      final reviewLoad = Completer<List<StoreReview>>();
      final auth = _AuthRepository()
        ..needsProfile = needsProfile
        ..googleGate = googleCompletion.future;
      final reviews = _EmptyReviewRepository()
        ..rows.add(_otherReview())
        ..loadHandler = (userId) =>
            userId == null ? Future.value([_otherReview()]) : reviewLoad.future;
      await _openGuestReport(tester, _reportApp(auth, reviews));
      await tester.tap(find.byKey(authGoogleSignInButtonKey));
      // A controlled review read is still pending; settle only navigation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (needsProfile) {
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<MapScreen>(find.byType(MapScreen, skipOffstage: false))
              .onSetNickname,
          isNotNull,
        );
        expect(find.byType(NicknameOnboardingScreen), findsOneWidget);
        expect(find.text('리뷰 신고'), findsNothing);
        await tester.enterText(find.byKey(nicknameFieldKey), '버거팬');
        await tester.tap(find.byKey(nicknameSubmitButtonKey));
        await tester.pump();
      }
      expect(find.text('리뷰 신고'), findsNothing);
      reviewLoad.complete([_otherReview()]);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(NicknameOnboardingScreen), findsNothing);
      expect(find.text('리뷰 신고'), findsOneWidget);
      final dialogElement = tester.element(find.byType(AlertDialog));
      for (var i = 0; i < 3; i++) {
        auth.signIn(); // Same-user Auth stream notification.
        await tester.pumpWidget(_reportApp(auth, reviews));
        await tester.pumpAndSettle();
        expect(find.text('리뷰 신고'), findsOneWidget);
        expect(tester.element(find.byType(AlertDialog)), same(dialogElement));
      }
      // The native Google operation can finish after the Auth stream/profile.
      googleCompletion.complete();
      await tester.pumpAndSettle();
      expect(find.text('리뷰 신고'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('review-report-reason-irrelevant')),
      );
      await tester.pump();
      await tester.tap(find.byKey(reviewReportSubmitButtonKey));
      await tester.pumpAndSettle();
      expect(reviews.reportCalls, 1);
      expect(reviews.lastReportId, 'review-other');
      expect(find.text('신고가 접수되었습니다.'), findsOneWidget);
      expect(find.byType(StoreDetailScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('refresh during returned report does not silently discard it', (
    tester,
  ) async {
    final auth = _AuthRepository();
    final reviews = _EmptyReviewRepository()..rows.add(_otherReview());
    final replacement = Completer<List<StoreLocation>>();
    var storeLoads = 0;
    await _openGuestReport(
      tester,
      _reportApp(
        auth,
        reviews,
        storeLoader: () => ++storeLoads == 1
            ? Future.value([_reportStore()])
            : replacement.future,
      ),
    );
    await tester.tap(find.byKey(authGoogleSignInButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('리뷰 신고'), findsOneWidget);
    final oldSection = tester.state(
      find.byType(StoreReviewSection, skipOffstage: false),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('review-report-reason-other')),
    );
    await tester.enterText(find.byKey(reviewReportDetailFieldKey), '확인 요청');
    await tester.pump(const Duration(minutes: 5));
    expect(storeLoads, 2);
    expect(oldSection.mounted, isFalse);
    expect(find.text('리뷰 신고'), findsOneWidget);
    replacement.complete([_reportStore()]);
    await tester.pumpAndSettle();
    expect(find.text('리뷰 신고'), findsOneWidget);
    await tester.tap(find.byKey(reviewReportSubmitButtonKey));
    await tester.pumpAndSettle();
    expect(reviews.reportCalls, 0);
    expect(find.text('리뷰 신고'), findsOneWidget);
    expect(
      find.text('로그인 또는 매장 정보가 변경되었습니다. 신고 창을 닫고 다시 열어 주세요.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(reviewReportDetailFieldKey))
          .controller
          ?.text,
      '확인 요청',
    );
    await tester.tap(find.text('취소').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(reviewReportButtonKey));
    await tester.tap(find.byKey(reviewReportButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('review-report-reason-irrelevant')),
    );
    await tester.pump();
    await tester.tap(find.byKey(reviewReportSubmitButtonKey));
    await tester.pumpAndSettle();
    expect(reviews.reportCalls, 1);
    expect(reviews.lastReportId, 'review-other');
    expect(tester.takeException(), isNull);
  });

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
  bool needsProfile = false;
  Future<void>? googleGate;
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
  Future<AuthUserProfile?> fetchCurrentProfile() async => needsProfile
      ? null
      : const AuthUserProfile(id: 'user-a', nickname: '버거팬');

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) async {
    needsProfile = false;
    return AuthUserProfile(id: 'user-a', nickname: nickname);
  }

  @override
  Future<void> sendMagicLink(String email) async {}

  @override
  Future<void> signInWithGoogle() async {
    signIn();
    await googleGate;
  }

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
  final rows = <StoreReview>[];
  Future<List<StoreReview>> Function(String? userId)? loadHandler;
  int reportCalls = 0;
  String? lastReportId;

  @override
  Future<List<StoreReview>> loadForStore(
    String storeId, {
    String? userId,
  }) async {
    lastUserId = userId;
    return await loadHandler?.call(userId) ?? List.of(rows);
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
  }) async {
    reportCalls++;
    lastReportId = reviewId;
  }
}

StoreLocation _reportStore() => StoreLocation(
  id: 'store-alpha',
  name: 'Alpha Burger',
  address: 'Seoul Yongsan Alpha-ro 1',
  latitude: 37.53,
  longitude: 126.99,
  burgerStyle: 'smash',
  verificationStatus: 'verified',
);

StoreReview _otherReview() => StoreReview(
  id: 'review-other',
  storeId: 'store-alpha',
  userId: 'other-user',
  rating: 4,
  content: '신고 흐름 확인을 위한 가짜 리뷰입니다.',
  createdAt: DateTime.utc(2026, 10, 1),
  isHidden: false,
);

Widget _reportApp(
  _AuthRepository auth,
  _EmptyReviewRepository reviews, {
  Future<List<StoreLocation>> Function()? storeLoader,
}) => BurgerMapApp(
  config: const AppConfig(
    environment: AppEnvironment.development,
    storeDataMode: StoreDataMode.supabase,
    googleMapsApiKey: 'test-key',
    supabaseUrl: 'https://unit.invalid',
    supabasePublishableKey: 'publishable-test-value',
  ),
  authControllerLoader: () async =>
      AuthController(auth, googleSignInEnabled: true),
  supabaseStoreLoader: storeLoader ?? () async => [_reportStore()],
  favoriteStoreIdsStore: _FavoritesStore(),
  reviewRepository: reviews,
  mapSurfaceBuilder: (_, _) => const ColoredBox(color: Colors.white),
);

Future<void> _openGuestReport(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(storeSearchFieldKey), 'Alpha');
  await tester.pump();
  await tester.tap(
    find.byKey(const ValueKey<String>('store-search-result-store-alpha')),
  );
  await tester.pump();
  await tester.tap(find.byKey(storePreviewDetailsButtonKey));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(reviewReportButtonKey));
  await tester.tap(find.byKey(reviewReportButtonKey));
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
}
