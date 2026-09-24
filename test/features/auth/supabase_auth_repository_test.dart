import 'dart:convert';
import 'dart:io';

import 'package:burger_map_korea/features/auth/data/native_google_token_provider.dart';
import 'package:burger_map_korea/features/auth/data/supabase_auth_repository.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('native Google tokens create a Supabase session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Map<String, dynamic>>[];
    final subscription = server.listen((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/auth/v1/token');
      expect(request.uri.queryParameters['grant_type'], 'id_token');
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'access_token': 'local-session',
          'refresh_token': 'local-refresh',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'user-a',
            'aud': 'authenticated',
            'created_at': '2026-09-24T00:00:00Z',
          },
        }),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(
      client,
      googleServerClientId: 'local-web-client-id',
      googleTokenLoader: (clientId) async {
        expect(clientId, 'local-web-client-id');
        return const GoogleAuthTokens(
          idToken: 'local-id-token',
          accessToken: 'local-google-access',
        );
      },
    );

    await repository.signInWithGoogle();

    expect(requests, hasLength(1));
    expect(requests.single['provider'], 'google');
    expect(requests.single['id_token'], 'local-id-token');
    expect(requests.single['access_token'], 'local-google-access');
    expect(repository.currentUserId, 'user-a');
    expect(client.auth.currentSession, isNotNull);
  });

  test('Supabase token exchange error never creates a session', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"code":"invalid_grant","msg":"private backend detail"}',
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(
      client,
      googleServerClientId: 'local-web-client-id',
      googleTokenLoader: (_) async => const GoogleAuthTokens(
        idToken: 'local-id-token',
        accessToken: 'local-google-access',
      ),
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<AuthFlowException>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.authentication,
        ),
      ),
    );
    expect(repository.currentUserId, isNull);
    expect(client.auth.currentSession, isNull);
  });

  test('native account picker cancellation does not call Supabase', () async {
    final client = SupabaseClient(
      'http://127.0.0.1:1',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);
    final repository = SupabaseAuthRepository(
      client,
      googleServerClientId: 'local-web-client-id',
      googleTokenLoader: (_) async => throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
      ),
    );

    await expectLater(
      repository.signInWithGoogle(),
      throwsA(
        isA<AuthFlowException>().having(
          (e) => e.kind,
          'kind',
          AuthFailureKind.canceled,
        ),
      ),
    );
    expect(client.auth.currentSession, isNull);
  });
}
