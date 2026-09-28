import 'dart:async';

import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/reviews/domain/review.dart';
import 'package:burger_map_korea/features/reviews/domain/review_repository.dart';
import 'package:burger_map_korea/features/reviews/presentation/store_review_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps all five preferences and canonical optional text', () {
    expect(preferenceLabel(5), '매우 선호');
    expect(preferenceLabel(4), '선호');
    expect(preferenceLabel(3), '보통');
    expect(preferenceLabel(2), '비선호');
    expect(preferenceLabel(1), '매우 비선호');
    expect(normalizedReviewContent(' \t\n '), isNull);
    expect(normalizedReviewContent('  맛있고 또 가고 싶어요  '), '맛있고 또 가고 싶어요');
    expect(reviewContentValidationMessage(null), isNull);
    expect(reviewContentValidationMessage('짧아요'), isNotNull);
    expect(reviewContentValidationMessage('가' * 10), isNull);
    expect(reviewContentValidationMessage('가' * 2001), isNotNull);
    expect(reviewContentValidationMessage('🍔' * 5), isNotNull);
    expect(reviewContentValidationMessage('🍔' * 10), isNull);
  });

  testWidgets('public reviews, optional text, and empty state are distinct', (
    tester,
  ) async {
    final repository = _FakeReviewRepository()
      ..rows.addAll([
        _review('other-a', rating: 5, content: null, nickname: '버거친구'),
        _review('other-b', rating: 2, content: '다음에는 다른 메뉴를 고를래요'),
      ]);
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.text('매우 선호 · 버거친구'), findsOneWidget);
    expect(find.text('비선호'), findsOneWidget);
    expect(find.text('다음에는 다른 메뉴를 고를래요'), findsOneWidget);
    expect(find.byKey(reviewEditButtonKey), findsNothing);
    expect(find.byKey(reviewDeleteButtonKey), findsNothing);

    repository.rows.clear();
    await tester.pumpWidget(_app(repository, storeId: 'store-b'));
    await tester.pump();
    expect(find.text('아직 작성된 리뷰가 없습니다.'), findsOneWidget);
  });

  testWidgets('loading, error and retry do not masquerade as empty', (
    tester,
  ) async {
    final pending = Completer<List<StoreReview>>();
    final repository = _FakeReviewRepository()
      ..loadHandler = (_, _) => pending.future;
    await tester.pumpWidget(_app(repository));
    expect(find.text('아직 작성된 리뷰가 없습니다.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.completeError(StateError('private database error'));
    await tester.pump();
    expect(find.text('리뷰를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('private database error'), findsNothing);
    repository.loadHandler = (_, _) async => [_review('other-a', rating: 4)];
    await tester.tap(find.byKey(reviewRetryButtonKey));
    await tester.pump();
    expect(find.text('선호'), findsOneWidget);
  });

  testWidgets(
    'late store A response cannot appear in store B or after dispose',
    (tester) async {
      final pendingA = Completer<List<StoreReview>>();
      final repository = _FakeReviewRepository()
        ..loadHandler = (storeId, _) => storeId == 'store-a'
            ? pendingA.future
            : Future.value([_review('other-b', storeId: 'store-b', rating: 3)]);
      await tester.pumpWidget(_app(repository));
      await tester.pumpWidget(_app(repository, storeId: 'store-b'));
      await tester.pump();
      expect(find.text('보통'), findsOneWidget);
      pendingA.complete([_review('other-a', rating: 5)]);
      await tester.pump();
      expect(find.text('매우 선호'), findsNothing);
      expect(find.text('보통'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('guest CTA returns to the same store editor after login', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository();
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final reviews = _FakeReviewRepository();
    var signInRequests = 0;
    await tester.pumpWidget(
      _app(reviews, auth: auth, onSignIn: () => signInRequests++),
    );
    await tester.pump();
    await tester.tap(find.byKey(reviewWriteButtonKey));
    await tester.pump();
    expect(signInRequests, 1);
    expect(find.byKey(reviewContentFieldKey), findsNothing);

    authRepository.signIn();
    await tester.pump();
    await tester.pump();
    expect(find.byKey(reviewContentFieldKey), findsOneWidget);
    expect(find.byKey(reviewSubmitButtonKey), findsOneWidget);
    expect(reviews.requestedStores, everyElement('store-a'));
    expect(reviews.requestedUsers.last, 'user-a');
  });

  testWidgets('pending review waits for nickname onboarding', (tester) async {
    final authRepository = _FakeAuthRepository()..needsProfile = true;
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final reviews = _FakeReviewRepository();
    var nicknameRequests = 0;
    await tester.pumpWidget(
      _app(
        reviews,
        auth: auth,
        onSignIn: () {},
        onSetNickname: () => nicknameRequests++,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(reviewWriteButtonKey));
    authRepository.signIn();
    await tester.pump();
    await tester.pump();
    expect(nicknameRequests, 1);
    expect(find.byKey(reviewContentFieldKey), findsNothing);
    await auth.submitNickname('버거팬');
    await tester.pump();
    await tester.pump();
    expect(find.byKey(reviewContentFieldKey), findsOneWidget);
  });

  testWidgets('create uses null for blank text and prevents duplicate submit', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository()..signIn();
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final pendingSave = Completer<void>();
    final reviews = _FakeReviewRepository()..createGate = pendingSave.future;
    await tester.pumpWidget(_app(reviews, auth: auth));
    await tester.pump();
    await tester.tap(find.byKey(reviewWriteButtonKey));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(reviewSubmitButtonKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(reviewPreferenceKey(5)));
    await tester.enterText(find.byKey(reviewContentFieldKey), '  ');
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    expect(reviews.createCalls, 1);
    expect(reviews.lastContent, isNull);
    expect(
      tester.widget<FilledButton>(find.byKey(reviewSubmitButtonKey)).onPressed,
      isNull,
    );
    pendingSave.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('매우 선호 · 내 리뷰'), findsOneWidget);
    expect(reviews.rows.single.content, isNull);
  });

  testWidgets('short text is rejected; own review edits and deletes', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository()..signIn();
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final reviews = _FakeReviewRepository()
      ..rows.addAll([
        _review('user-a', rating: 4, content: null),
        _review('other-a', rating: 3),
      ]);
    await tester.pumpWidget(_app(reviews, auth: auth));
    await tester.pump();
    expect(find.byKey(reviewEditButtonKey), findsOneWidget);
    expect(find.byKey(reviewDeleteButtonKey), findsOneWidget);
    await tester.tap(find.byKey(reviewEditButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(reviewPreferenceKey(1)));
    await tester.enterText(find.byKey(reviewContentFieldKey), '짧아요');
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    expect(find.text('리뷰 글은 10자 이상 입력해 주세요.'), findsOneWidget);
    expect(reviews.updateCalls, 0);

    await tester.enterText(
      find.byKey(reviewContentFieldKey),
      ' 다시 방문하고 싶지 않아요 ',
    );
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    await tester.pump();
    expect(reviews.updateCalls, 1);
    expect(reviews.rows.first.rating, 1);
    expect(reviews.rows.first.content, '다시 방문하고 싶지 않아요');

    await tester.tap(find.byKey(reviewDeleteButtonKey));
    await tester.pump();
    expect(find.text('리뷰를 삭제할까요?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '삭제').last);
    await tester.pump();
    await tester.pump();
    expect(reviews.deleteCalls, 1);
    expect(reviews.rows.length, 1);
    expect(find.byKey(reviewEditButtonKey), findsNothing);
  });

  testWidgets('save failure retains editor with safe retry feedback', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository()..signIn();
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final reviews = _FakeReviewRepository()..failNextCreate = true;
    await tester.pumpWidget(_app(reviews, auth: auth));
    await tester.pump();
    await tester.tap(find.byKey(reviewWriteButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(reviewPreferenceKey(3)));
    await tester.pump();
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    expect(find.text('리뷰를 저장하지 못했습니다. 다시 시도해 주세요.'), findsOneWidget);
    expect(find.byKey(reviewContentFieldKey), findsOneWidget);
    expect(reviews.rows, isEmpty);
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    await tester.pump();
    expect(reviews.rows.single.rating, 3);
  });

  testWidgets('uncertain write requires a fresh read before another submit', (
    tester,
  ) async {
    final authRepository = _FakeAuthRepository()..signIn();
    final auth = AuthController(authRepository)..initialize();
    addTearDown(auth.dispose);
    final reviews = _FakeReviewRepository()
      ..nextCreateFailure = ReviewFailure.unknownOutcome;
    await tester.pumpWidget(_app(reviews, auth: auth));
    await tester.pump();
    await tester.tap(find.byKey(reviewWriteButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(reviewPreferenceKey(3)));
    await tester.pump();
    await tester.tap(find.byKey(reviewSubmitButtonKey));
    await tester.pump();
    expect(find.byKey(reviewCheckResultButtonKey), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(reviewSubmitButtonKey)).onPressed,
      isNull,
    );
    reviews.rows.add(_review('user-a', rating: 3));
    await tester.tap(find.byKey(reviewCheckResultButtonKey));
    await tester.pump();
    expect(find.text('보통 · 내 리뷰'), findsOneWidget);
    expect(reviews.createCalls, 1);
  });
}

Widget _app(
  ReviewRepository repository, {
  String storeId = 'store-a',
  AuthController? auth,
  VoidCallback? onSignIn,
  VoidCallback? onSetNickname,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: StoreReviewSection(
        storeId: storeId,
        repository: repository,
        authController: auth,
        onSignIn: onSignIn,
        onSetNickname: onSetNickname,
      ),
    ),
  ),
);

StoreReview _review(
  String userId, {
  String storeId = 'store-a',
  int rating = 5,
  String? content,
  String? nickname,
}) => StoreReview(
  id: '$storeId-$userId',
  storeId: storeId,
  userId: userId,
  rating: rating,
  content: content,
  createdAt: DateTime.utc(2026, 9, 28),
  isHidden: false,
  nickname: nickname,
);

class _FakeReviewRepository implements ReviewRepository {
  final rows = <StoreReview>[];
  final requestedStores = <String>[];
  final requestedUsers = <String?>[];
  Future<List<StoreReview>> Function(String storeId, String? userId)?
  loadHandler;
  Future<void>? createGate;
  bool failNextCreate = false;
  ReviewFailure? nextCreateFailure;
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  String? lastContent;

  @override
  Future<List<StoreReview>> loadForStore(
    String storeId, {
    String? userId,
  }) async {
    requestedStores.add(storeId);
    requestedUsers.add(userId);
    return await loadHandler?.call(storeId, userId) ??
        rows.where((row) => row.storeId == storeId).toList();
  }

  @override
  Future<void> create({
    required String storeId,
    required int rating,
    required String? content,
  }) async {
    createCalls++;
    lastContent = content;
    if (nextCreateFailure case final failure?) {
      nextCreateFailure = null;
      throw ReviewException(failure);
    }
    if (failNextCreate) {
      failNextCreate = false;
      throw const ReviewException(ReviewFailure.unavailable);
    }
    await createGate;
    rows.add(
      _review('user-a', storeId: storeId, rating: rating, content: content),
    );
  }

  @override
  Future<void> update({
    required String reviewId,
    required int rating,
    required String? content,
  }) async {
    updateCalls++;
    final index = rows.indexWhere((row) => row.id == reviewId);
    rows[index] = _review('user-a', rating: rating, content: content);
  }

  @override
  Future<void> delete(String reviewId) async {
    deleteCalls++;
    rows.removeWhere((row) => row.id == reviewId);
  }
}

class _FakeAuthRepository implements AuthRepository {
  String? userId;
  bool needsProfile = false;
  final changes = StreamController<String?>.broadcast();

  void signIn() {
    userId = 'user-a';
    changes.add(userId);
  }

  @override
  String? get currentUserId => userId;

  @override
  Stream<String?> get userChanges => changes.stream;

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
  Future<void> signInWithGoogle() async {}

  @override
  Future<void> signOut() async {
    userId = null;
    changes.add(null);
  }
}
