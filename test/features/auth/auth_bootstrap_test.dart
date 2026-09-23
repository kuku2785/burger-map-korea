import 'dart:async';

import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/auth/application/auth_controller.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('auth bootstrap ignores repeated retry taps while loading', (
    tester,
  ) async {
    final pending = Completer<AuthController>();
    var calls = 0;

    await tester.pumpWidget(
      BurgerMapApp(
        config: const AppConfig(
          environment: AppEnvironment.development,
          googleMapsApiKey: '',
        ),
        authControllerLoader: () {
          calls++;
          if (calls == 1) {
            return Future<AuthController>.error(
              const AuthFlowException(AuthFailureKind.network),
            );
          }
          return pending.future;
        },
      ),
    );
    await tester.pump();

    expect(find.text('다시 시도'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.tap(find.text('다시 시도'));

    expect(calls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(AuthController(_IdleAuthRepository()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

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
