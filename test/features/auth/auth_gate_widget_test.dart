import 'dart:async';

import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/auth_gate.dart';
import 'package:burger_map_korea/features/auth/presentation/login_screen.dart';
import 'package:burger_map_korea/features/auth/presentation/nickname_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _loginKey = ValueKey('test-login');
const _logoutKey = ValueKey('test-logout');
const _nicknameKey = ValueKey('test-nickname');
const _retryKey = ValueKey('test-retry');
const _countKey = ValueKey('test-count');

void main() {
  testWidgets('guest explores while sign-in remains optional and cancellable', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byKey(_countKey), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    await tester.tap(find.byKey(_countKey));
    await tester.tap(find.byKey(_loginKey));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.enterText(find.byKey(authEmailFieldKey), 'not-an-email');
    await tester.tap(find.byKey(authEmailSubmitButtonKey));
    await tester.pump();
    expect(repository.sendCalls, 0);
    expect(find.text('올바른 이메일 주소를 입력해 주세요.'), findsOneWidget);

    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('count: 1'), findsOneWidget);

    await tester.tap(find.byKey(_loginKey));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('magic-link submit normalizes email and blocks duplicate taps', (
    tester,
  ) async {
    final pending = Completer<void>();
    final repository = _FakeAuthRepository()..sendCompleter = pending;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.tap(find.byKey(_loginKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(authEmailFieldKey),
      '  USER@Example.COM  ',
    );
    await tester.tap(find.byKey(authEmailSubmitButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(authEmailSubmitButtonKey), warnIfMissed: false);
    expect(repository.sentEmails, ['user@example.com']);

    pending.complete();
    await tester.pump();
    expect(find.textContaining('로그인 링크를 보냈습니다'), findsOneWidget);
  });

  testWidgets('restored session and logout keep the same public shell', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(
      userId: 'user-a',
      profile: const AuthUserProfile(id: 'user-a', nickname: '버거팬'),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.byKey(_logoutKey), findsOneWidget);
    await tester.tap(find.byKey(_countKey));

    await tester.tap(find.byKey(_logoutKey));
    await tester.pump();
    expect(find.byKey(_loginKey), findsOneWidget);
    expect(find.text('count: 1'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
  });

  testWidgets('profile is optional for exploration and can be created later', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(userId: 'user-a');
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.byKey(_countKey), findsOneWidget);
    expect(find.byType(NicknameOnboardingScreen), findsNothing);
    expect(find.byKey(_nicknameKey), findsOneWidget);

    await tester.tap(find.byKey(_nicknameKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(nicknameFieldKey), '버거팬');
    await tester.tap(find.byKey(nicknameSubmitButtonKey));
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
    expect(find.byType(NicknameOnboardingScreen), findsNothing);
    expect(find.byKey(_countKey), findsOneWidget);
    expect(find.byKey(_logoutKey), findsOneWidget);
  });

  testWidgets('optional nickname route blocks duplicate saves', (tester) async {
    final pending = Completer<AuthUserProfile>();
    final repository = _FakeAuthRepository(userId: 'user-a')
      ..createCompleter = pending;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.tap(find.byKey(_nicknameKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(nicknameFieldKey), '버거팬');
    await tester.tap(find.byKey(nicknameSubmitButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(nicknameSubmitButtonKey), warnIfMissed: false);
    expect(repository.createCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(const AuthUserProfile(id: 'user-a', nickname: '버거팬'));
    await tester.pumpAndSettle();
    expect(find.byType(NicknameOnboardingScreen), findsNothing);
    expect(find.byKey(_countKey), findsOneWidget);
  });

  testWidgets('profile read failure leaves public exploration available', (
    tester,
  ) async {
    final repository = _FakeAuthRepository(userId: 'user-a')
      ..failProfileRead = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.byKey(_countKey), findsOneWidget);
    expect(find.byKey(_logoutKey), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(_retryKey), findsOneWidget);
    repository.failProfileRead = false;
    await tester.tap(find.byKey(_retryKey));
    await tester.pumpAndSettle();
    expect(find.byKey(_retryKey), findsNothing);
    expect(find.byKey(_nicknameKey), findsOneWidget);
  });

  testWidgets('auth stream error and failed link leave a route back to map', (
    tester,
  ) async {
    final repository = _FakeAuthRepository()..failMagicLink = true;
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    repository.emitError();
    await tester.pump();
    expect(find.byKey(_countKey), findsOneWidget);
    await tester.tap(find.byKey(_loginKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(authEmailFieldKey), 'a@example.com');
    await tester.tap(find.byKey(authEmailSubmitButtonKey));
    await tester.pump();
    expect(find.byKey(authMessageKey), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byKey(_countKey), findsOneWidget);
  });

  testWidgets('login and optional nickname route fit a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeAuthRepository();
    await tester.pumpWidget(_app(repository, textScale: 2));
    await tester.pump();
    await tester.tap(find.byKey(_loginKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    repository.emitUser('user-a');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_nicknameKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_countKey), findsOneWidget);
  });
}

Widget _app(_FakeAuthRepository repository, {double textScale = 1}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AuthGate(
        controllerLoader: () async => AuthController(repository),
        publicBuilder:
            (context, onSignIn, onSignOut, onSetNickname, onRetryAuth) =>
                _PublicShell(
                  onSignIn: onSignIn,
                  onSignOut: onSignOut,
                  onSetNickname: onSetNickname,
                  onRetryAuth: onRetryAuth,
                ),
      ),
    );

class _PublicShell extends StatefulWidget {
  const _PublicShell({
    required this.onSignIn,
    required this.onSignOut,
    required this.onSetNickname,
    required this.onRetryAuth,
  });

  final VoidCallback onSignIn;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onSetNickname;
  final VoidCallback? onRetryAuth;

  @override
  State<_PublicShell> createState() => _PublicShellState();
}

class _PublicShellState extends State<_PublicShell> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          key: _countKey,
          onPressed: () => setState(() => count++),
          child: Text('count: $count'),
        ),
        if (widget.onSignOut == null)
          TextButton(
            key: _loginKey,
            onPressed: widget.onSignIn,
            child: const Text('login'),
          ),
        if (widget.onSignOut != null)
          TextButton(
            key: _logoutKey,
            onPressed: widget.onSignOut,
            child: const Text('logout'),
          ),
        if (widget.onSetNickname != null)
          TextButton(
            key: _nicknameKey,
            onPressed: widget.onSetNickname,
            child: const Text('nickname'),
          ),
        if (widget.onRetryAuth != null)
          TextButton(
            key: _retryKey,
            onPressed: widget.onRetryAuth,
            child: const Text('retry'),
          ),
      ],
    ),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.userId, this.profile});

  String? userId;
  AuthUserProfile? profile;
  bool failProfileRead = false;
  bool failMagicLink = false;
  Completer<void>? sendCompleter;
  Completer<AuthUserProfile>? createCompleter;
  int sendCalls = 0;
  int createCalls = 0;
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

  void emitError() => _changes.addError(StateError('private auth error'));

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() async {
    if (failProfileRead) {
      throw const AuthFlowException(AuthFailureKind.profile);
    }
    return profile;
  }

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) async {
    createCalls++;
    final pending = createCompleter;
    if (pending != null) return pending.future;
    profile = AuthUserProfile(id: userId!, nickname: nickname);
    return profile!;
  }

  @override
  Future<void> sendMagicLink(String email) async {
    sendCalls++;
    sentEmails.add(email);
    if (failMagicLink) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }
    final pending = sendCompleter;
    if (pending != null) await pending.future;
  }

  @override
  Future<void> signOut() async => emitUser(null);
}
