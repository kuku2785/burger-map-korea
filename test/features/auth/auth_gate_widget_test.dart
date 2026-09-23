import 'dart:async';

import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/auth_gate.dart';
import 'package:burger_map_korea/features/auth/presentation/login_screen.dart';
import 'package:burger_map_korea/features/auth/presentation/nickname_onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('no session shows login and validates email', (tester) async {
    final repository = WidgetFakeAuthRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.enterText(find.byKey(authEmailFieldKey), 'not-an-email');
    await tester.tap(find.byKey(authEmailSubmitButtonKey));
    await tester.pump();

    expect(find.text('올바른 이메일 주소를 입력해 주세요.'), findsOneWidget);
    expect(repository.sendCalls, 0);
  });

  testWidgets(
    'magic-link submit is normalized and duplicate taps are blocked',
    (tester) async {
      final pending = Completer<void>();
      final repository = WidgetFakeAuthRepository()..sendCompleter = pending;
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      await tester.enterText(
        find.byKey(authEmailFieldKey),
        '  USER@Example.COM  ',
      );
      await tester.tap(find.byKey(authEmailSubmitButtonKey));
      await tester.pump();
      await tester.tap(
        find.byKey(authEmailSubmitButtonKey),
        warnIfMissed: false,
      );

      expect(repository.sendCalls, 1);
      expect(repository.sentEmails, ['user@example.com']);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete();
      await tester.pump();
      expect(find.textContaining('로그인 링크를 보냈습니다'), findsOneWidget);
    },
  );

  testWidgets('session without profile shows nickname onboarding', (
    tester,
  ) async {
    final repository = WidgetFakeAuthRepository(userId: 'user-a');
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byType(NicknameOnboardingScreen), findsOneWidget);
  });

  testWidgets('nickname submit blocks duplicate taps while saving', (
    tester,
  ) async {
    final pending = Completer<AuthUserProfile>();
    final repository = WidgetFakeAuthRepository(userId: 'user-a')
      ..createCompleter = pending;
    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byKey(nicknameFieldKey), '패티왕');
    await tester.tap(find.byKey(nicknameSubmitButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(nicknameSubmitButtonKey), warnIfMissed: false);

    expect(repository.createCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete(const AuthUserProfile(id: 'user-a', nickname: '패티왕'));
    await tester.pump();
    expect(find.text('main-app'), findsOneWidget);
  });

  testWidgets('restored session with profile and logout event switch views', (
    tester,
  ) async {
    final repository = WidgetFakeAuthRepository(
      userId: 'user-a',
      profile: const AuthUserProfile(id: 'user-a', nickname: '패티왕'),
    );
    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.text('main-app'), findsOneWidget);

    repository.emitUser(null);
    await tester.pump();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('login and onboarding fit a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final signedOut = WidgetFakeAuthRepository();
    await tester.pumpWidget(_app(signedOut, textScale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _app(WidgetFakeAuthRepository(userId: 'user-a'), textScale: 2),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Widget _app(WidgetFakeAuthRepository repository, {double textScale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: AuthGate(
      controller: AuthController(repository),
      signedInBuilder: (context, signOut) =>
          const Scaffold(body: Text('main-app')),
    ),
  );
}

class WidgetFakeAuthRepository implements AuthRepository {
  WidgetFakeAuthRepository({this.userId, this.profile});

  String? userId;
  AuthUserProfile? profile;
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

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() async => profile;

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) async {
    createCalls++;
    final pending = createCompleter;
    if (pending != null) return pending.future;
    return AuthUserProfile(id: userId!, nickname: nickname);
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
    emitUser(null);
  }
}
