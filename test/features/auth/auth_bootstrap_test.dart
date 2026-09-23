import 'dart:async';

import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:burger_map_korea/features/auth/presentation/login_screen.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pending auth bootstrap leaves the public map usable', (
    tester,
  ) async {
    final pending = Completer<AuthController>();
    var calls = 0;
    await tester.pumpWidget(
      _app(() {
        calls++;
        return pending.future;
      }),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.byKey(explorerListTabKey), findsOneWidget);
    await tester.tap(find.byKey(explorerListTabKey));
    await tester.pump();
    expect(calls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(AuthController(_IdleAuthRepository()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth bootstrap failure can retry without blocking public map', (
    tester,
  ) async {
    final pending = Completer<AuthController>();
    var calls = 0;
    await tester.pumpWidget(
      _app(() {
        calls++;
        if (calls == 1) {
          return Future<AuthController>.error(
            const AuthFlowException(AuthFailureKind.network),
          );
        }
        return pending.future;
      }),
    );
    await tester.pump();

    expect(find.byType(MapScreen), findsOneWidget);
    await tester.tap(find.byKey(loginButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(loginButtonKey));
    await tester.pump();
    expect(calls, 2);
    expect(find.byType(MapScreen), findsOneWidget);

    pending.complete(AuthController(_IdleAuthRepository()));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(MapScreen), findsOneWidget);
  });
}

Widget _app(Future<AuthController> Function() loader) => BurgerMapApp(
  config: const AppConfig(
    environment: AppEnvironment.development,
    googleMapsApiKey: 'test-key',
  ),
  mapSurfaceBuilder: (_, _) => const SizedBox.expand(),
  authControllerLoader: loader,
);

class _IdleAuthRepository implements AuthRepository {
  @override
  String? get currentUserId => null;

  @override
  Stream<String?> get userChanges => const Stream<String?>.empty();

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) =>
      throw UnimplementedError();

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() => throw UnimplementedError();

  @override
  Future<void> sendMagicLink(String email) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();
}
