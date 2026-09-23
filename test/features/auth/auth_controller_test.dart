import 'dart:async';

import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/data/supabase_auth_repository.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nickname validation matches the database contract', () {
    test('accepts Hangul, English, numbers and underscore', () {
      expect(validateNickname('버거Fan_27'), isNull);
      expect(validateNickname('  패티_2  '), isNull);
    });

    test('rejects too short and too long values', () {
      expect(validateNickname('a'), NicknameValidationError.tooShort);
      expect(validateNickname('a' * 21), NicknameValidationError.tooLong);
    });

    test('rejects invalid characters and whitespace inside the value', () {
      expect(
        validateNickname('burger fan'),
        NicknameValidationError.invalidCharacters,
      );
      expect(
        validateNickname('burger-fan'),
        NicknameValidationError.invalidCharacters,
      );
    });

    test('rejects all database-reserved fragments case-insensitively', () {
      for (final value in [
        'myAdmin',
        'MODERATOR2',
        'support_team',
        '운영자님',
        '관리자2',
        '버거맵팬',
      ]) {
        expect(validateNickname(value), NicknameValidationError.reserved);
      }
    });
  });

  test('profile payload contains only the RLS-approved fields', () {
    expect(supabaseProfileSelectColumns, 'id,nickname');
    expect(buildProfileInsertPayload(userId: 'user-a', nickname: '패티왕'), {
      'id': 'user-a',
      'nickname': '패티왕',
    });
    expect(
      buildProfileInsertPayload(userId: 'user-a', nickname: '패티왕').keys,
      unorderedEquals(['id', 'nickname']),
    );
  });

  test('no session resolves to signed out', () async {
    final repository = FakeAuthRepository();
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    expect(controller.state, AuthGateState.signedOut);
    controller.dispose();
    await repository.close();
  });

  test('restored session without profile requires onboarding', () async {
    final repository = FakeAuthRepository(userId: 'user-a');
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    expect(controller.state, AuthGateState.signedInNeedsProfile);
    expect(repository.profileReads, 1);
    controller.dispose();
    await repository.close();
  });

  test('restored session with profile opens the app', () async {
    final repository = FakeAuthRepository(
      userId: 'user-a',
      profile: const AuthUserProfile(id: 'user-a', nickname: '패티왕'),
    );
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    expect(controller.state, AuthGateState.signedInReady);
    expect(controller.profile?.nickname, '패티왕');
    controller.dispose();
    await repository.close();
  });

  test('auth logout event returns the gate to login', () async {
    final repository = FakeAuthRepository(
      userId: 'user-a',
      profile: const AuthUserProfile(id: 'user-a', nickname: '패티왕'),
    );
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    repository.emitUser(null);
    await pumpEventQueue();

    expect(controller.state, AuthGateState.signedOut);
    expect(controller.profile, isNull);
    controller.dispose();
    await repository.close();
  });

  test(
    'token refresh for the ready user does not hide the app or re-read',
    () async {
      final repository = FakeAuthRepository(
        userId: 'user-a',
        profile: const AuthUserProfile(id: 'user-a', nickname: '패티왕'),
      );
      final controller = AuthController(repository)..initialize();
      await pumpEventQueue();

      repository.emitUser('user-a');
      await pumpEventQueue();

      expect(controller.state, AuthGateState.signedInReady);
      expect(repository.profileReads, 1);
      controller.dispose();
      await repository.close();
    },
  );

  test('profile read failure is distinct and retry recovers', () async {
    final repository = FakeAuthRepository(userId: 'user-a')
      ..fetchError = const AuthFlowException(AuthFailureKind.profile);
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    expect(controller.state, AuthGateState.error);
    expect(controller.message, contains('프로필'));

    repository
      ..fetchError = null
      ..profile = const AuthUserProfile(id: 'user-a', nickname: '패티왕');
    await controller.retry();

    expect(controller.state, AuthGateState.signedInReady);
    controller.dispose();
    await repository.close();
  });

  test('profile creation trims nickname and becomes ready', () async {
    final repository = FakeAuthRepository(userId: 'user-a');
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    await controller.submitNickname('  패티왕  ');

    expect(repository.createdNicknames, ['패티왕']);
    expect(controller.state, AuthGateState.signedInReady);
    expect(controller.profile?.id, 'user-a');
    controller.dispose();
    await repository.close();
  });

  test('already-created profile recovery becomes ready', () async {
    final repository = FakeAuthRepository(userId: 'user-a')
      ..createResult = const AuthUserProfile(id: 'user-a', nickname: '먼저저장됨');
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    await controller.submitNickname('동시저장');

    expect(controller.state, AuthGateState.signedInReady);
    expect(controller.profile?.nickname, '먼저저장됨');
    controller.dispose();
    await repository.close();
  });

  test('backend create failure stays on onboarding with safe error', () async {
    final repository = FakeAuthRepository(userId: 'user-a')
      ..createError = const AuthFlowException(AuthFailureKind.profile);
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    await controller.submitNickname('패티왕');

    expect(controller.state, AuthGateState.signedInNeedsProfile);
    expect(controller.message, contains('저장하지 못했습니다'));
    controller.dispose();
    await repository.close();
  });

  test('late profile result after logout cannot reopen the app', () async {
    final pending = Completer<AuthUserProfile?>();
    final repository = FakeAuthRepository(userId: 'user-a')
      ..fetchCompleter = pending;
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();
    expect(controller.state, AuthGateState.signedInProfileLoading);

    repository.emitUser(null);
    pending.complete(const AuthUserProfile(id: 'user-a', nickname: '늦은응답'));
    await pumpEventQueue();

    expect(controller.state, AuthGateState.signedOut);
    controller.dispose();
    await repository.close();
  });

  test(
    'same user can sign in again while an old profile read is pending',
    () async {
      final firstRead = Completer<AuthUserProfile?>();
      final secondRead = Completer<AuthUserProfile?>();
      final repository = FakeAuthRepository(userId: 'user-a')
        ..fetchCompleter = firstRead;
      final controller = AuthController(repository)..initialize();
      await pumpEventQueue();

      repository.emitUser(null);
      repository.fetchCompleter = secondRead;
      repository.emitUser('user-a');
      await pumpEventQueue();

      expect(repository.profileReads, 2);
      secondRead.complete(
        const AuthUserProfile(id: 'user-a', nickname: '다시로그인'),
      );
      await pumpEventQueue();
      expect(controller.state, AuthGateState.signedInReady);
      expect(controller.profile?.nickname, '다시로그인');

      firstRead.complete(
        const AuthUserProfile(id: 'user-a', nickname: '오래된응답'),
      );
      await pumpEventQueue();
      expect(controller.profile?.nickname, '다시로그인');
      controller.dispose();
      await repository.close();
    },
  );

  test('signOut calls repository and clears local gate state', () async {
    final repository = FakeAuthRepository(
      userId: 'user-a',
      profile: const AuthUserProfile(id: 'user-a', nickname: '패티왕'),
    );
    final controller = AuthController(repository)..initialize();
    await pumpEventQueue();

    await controller.signOut();

    expect(repository.signOutCalls, 1);
    expect(controller.state, AuthGateState.signedOut);
    controller.dispose();
    await repository.close();
  });
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.userId, this.profile});

  String? userId;
  AuthUserProfile? profile;
  AuthUserProfile? createResult;
  Object? fetchError;
  Object? createError;
  Completer<AuthUserProfile?>? fetchCompleter;
  Completer<void>? sendCompleter;
  int profileReads = 0;
  int signOutCalls = 0;
  int sendCalls = 0;
  final createdNicknames = <String>[];
  final sentEmails = <String>[];
  final _changes = StreamController<String?>.broadcast();

  @override
  String? get currentUserId => userId;

  @override
  Stream<String?> get userChanges => _changes.stream;

  void emitUser(String? value) {
    userId = value;
    _changes.add(value);
  }

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() async {
    profileReads++;
    final error = fetchError;
    if (error != null) throw error;
    final pending = fetchCompleter;
    if (pending != null) return pending.future;
    return profile;
  }

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) async {
    createdNicknames.add(nickname);
    final error = createError;
    if (error != null) throw error;
    return createResult ?? AuthUserProfile(id: userId!, nickname: nickname);
  }

  @override
  Future<void> sendMagicLink(String email) async {
    sendCalls++;
    sentEmails.add(email);
    final pending = sendCompleter;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    userId = null;
  }

  Future<void> close() => _changes.close();
}
