import 'dart:async';

import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/account_deletion_button.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_controller_test.dart' show FakeAuthRepository;

class _DeletionRepository extends FakeAuthRepository {
  _DeletionRepository({bool guest = false})
    : super(
        userId: guest ? null : 'user-a',
        profile: guest
            ? null
            : const AuthUserProfile(id: 'user-a', nickname: '버거팬'),
      );
  final completion = Completer<void>();
  int deleteCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    final expected = userId;
    await completion.future;
    if (userId == expected) emitUser(null);
  }
}

class _Favorites implements FavoriteStoreIdsStore {
  final ids = <String>{'retained-local-store'};
  int saves = 0;
  @override
  Future<Set<String>> load() async => ids;
  @override
  Future<void> save(Set<String> storeIds) async {
    saves++;
  }
}

Widget _app(AuthController controller, {_Favorites? favorites}) => BurgerMapApp(
  config: const AppConfig(
    environment: AppEnvironment.development,
    googleMapsApiKey: 'test-key',
  ),
  mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
  authControllerLoader: () async => controller,
  favoriteStoreIdsStore: favorites,
);

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(accountDeleteEntryKey));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'guest cannot delete; authenticated duplicate and logout are blocked',
    () async {
      final guest = _DeletionRepository(guest: true);
      final guestController = AuthController(guest)..initialize();
      expect(await guestController.deleteAccount(), false);
      expect(guest.deleteCalls, 0);
      guestController.dispose();
      await guest.close();
      final repo = _DeletionRepository();
      final controller = AuthController(repo)..initialize();
      await Future<void>.delayed(Duration.zero);
      final pending = controller.deleteAccount();
      expect(controller.deletingAccount, true);
      expect(await controller.deleteAccount(), false);
      await controller.signOut();
      expect(repo.deleteCalls, 1);
      expect(repo.signOutCalls, 0);
      repo.completion.complete();
      expect(await pending, true);
      expect(controller.hasSession, false);
      expect(controller.profile, isNull);
      expect(controller.state, AuthGateState.signedOut);
      controller.dispose();
      await repo.close();
    },
  );

  for (final failure in [
    const AuthFlowException(AuthFailureKind.authentication),
    const AuthFlowException(AuthFailureKind.network),
    StateError('private backend JWT detail'),
  ]) {
    test(
      'controller preserves session and sanitizes ${failure.runtimeType} ${failure is AuthFlowException ? failure.kind : "raw"}',
      () async {
        final repo = _DeletionRepository();
        final controller = AuthController(repo)..initialize();
        await Future<void>.delayed(Duration.zero);
        final profile = controller.profile;
        final pending = controller.deleteAccount();
        repo.completion.completeError(failure);
        expect(await pending, false);
        expect(controller.hasSession, true);
        expect(controller.profile, same(profile));
        expect(controller.state, AuthGateState.signedInReady);
        expect(controller.message, isNot(contains('private')));
        expect(controller.message, isNot(contains('JWT')));
        expect(controller.deletingAccount, false);
        controller.dispose();
        await repo.close();
      },
    );
  }

  test('late success cannot sign out a new account', () async {
    final repo = _DeletionRepository();
    final controller = AuthController(repo)..initialize();
    await Future<void>.delayed(Duration.zero);
    final pending = controller.deleteAccount();
    repo.profile = const AuthUserProfile(id: 'user-b', nickname: '다른팬');
    repo.emitUser('user-b');
    await Future<void>.delayed(Duration.zero);
    repo.completion.complete();
    expect(await pending, false);
    expect(controller.currentUserId, 'user-b');
    expect(controller.profile?.id, 'user-b');
    controller.dispose();
    await repo.close();
  });

  test('late profile read cannot resurrect deleted account', () async {
    final repo = _DeletionRepository()
      ..fetchCompleter = Completer<AuthUserProfile?>();
    final controller = AuthController(repo)..initialize();
    final pending = controller.deleteAccount();
    repo.completion.complete();
    expect(await pending, true);
    repo.fetchCompleter!.complete(repo.profile);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state, AuthGateState.signedOut);
    expect(controller.profile, isNull);
    controller.dispose();
    await repo.close();
  });

  testWidgets('guest has no account delete entry', (tester) async {
    final repo = _DeletionRepository(guest: true);
    addTearDown(repo.close);
    await tester.pumpWidget(_app(AuthController(repo)));
    await tester.pumpAndSettle();
    expect(find.byKey(accountDeleteEntryKey), findsNothing);
  });

  testWidgets(
    'authenticated entry opens destructive confirmation; cancel makes zero calls',
    (tester) async {
      final repo = _DeletionRepository();
      addTearDown(repo.close);
      await tester.pumpWidget(_app(AuthController(repo)));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await _open(tester);
      expect(find.text('계정을 삭제할까요?'), findsOneWidget);
      expect(find.textContaining('복구할 수 없습니다'), findsOneWidget);
      expect(find.textContaining('즐겨찾기는 유지됩니다'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(accountDeleteConfirmKey)).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSemantics(find.byKey(accountDeleteConfirmKey)).label,
        contains('계정 삭제'),
      );
      expect(
        tester.widget<TextButton>(find.byKey(accountDeleteCancelKey)).autofocus,
        true,
      );
      await tester.tap(find.byKey(accountDeleteCancelKey));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 0);
      semantics.dispose();
    },
  );

  testWidgets(
    'confirm once, loading prevents duplicates, success returns guest preserving map/favorites',
    (tester) async {
      final repo = _DeletionRepository();
      final controller = AuthController(repo);
      final favorites = _Favorites();
      addTearDown(repo.close);
      await tester.pumpWidget(_app(controller, favorites: favorites));
      await tester.pumpAndSettle();
      final mapState = tester.state(find.byType(MapScreen));
      await _open(tester);
      await tester.tap(find.byKey(accountDeleteConfirmKey));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(accountDeleteConfirmKey))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(accountDeleteConfirmKey));
      expect(repo.deleteCalls, 1);
      repo.completion.complete();
      await tester.pumpAndSettle();
      expect(controller.hasSession, false);
      expect(controller.profile, isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(accountDeleteEntryKey), findsNothing);
      expect(find.byKey(logoutButtonKey), findsNothing);
      expect(find.byKey(loginButtonKey), findsOneWidget);
      expect(tester.state(find.byType(MapScreen)), same(mapState));
      expect(favorites.ids, {'retained-local-store'});
      expect(favorites.saves, 0);
    },
  );

  testWidgets(
    'failure preserves authenticated UI and displays only safe retry error',
    (tester) async {
      final repo = _DeletionRepository();
      final controller = AuthController(repo);
      addTearDown(repo.close);
      await tester.pumpWidget(_app(controller));
      await tester.pumpAndSettle();
      await _open(tester);
      await tester.tap(find.byKey(accountDeleteConfirmKey));
      await tester.pump();
      repo.completion.completeError(StateError('private JWT postgres detail'));
      await tester.pumpAndSettle();
      expect(controller.hasSession, true);
      expect(
        find.text('계정 삭제 완료를 확인하지 못했습니다. 잠시 후 다시 시도해 주세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(accountDeleteConfirmKey))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.byKey(accountDeleteCancelKey));
      await tester.pumpAndSettle();
      expect(find.byKey(logoutButtonKey), findsOneWidget);
    },
  );

  testWidgets(
    'account change while confirmation is open cannot delete new user',
    (tester) async {
      final repo = _DeletionRepository();
      addTearDown(repo.close);
      await tester.pumpWidget(_app(AuthController(repo)));
      await tester.pumpAndSettle();
      await _open(tester);
      repo.profile = const AuthUserProfile(id: 'user-b', nickname: '다른팬');
      repo.emitUser('user-b');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(accountDeleteConfirmKey))
            .onPressed,
        isNull,
      );
      expect(repo.deleteCalls, 0);
    },
  );

  testWidgets('disposed dialog/controller tolerates late completion', (
    tester,
  ) async {
    final repo = _DeletionRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(_app(AuthController(repo)));
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.tap(find.byKey(accountDeleteConfirmKey));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    repo.completion.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(repo.currentUserId, isNull);
  });
}
