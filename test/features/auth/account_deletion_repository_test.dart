import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:burger_map_korea/features/auth/data/supabase_auth_repository.dart';
import 'package:burger_map_korea/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// The only URL supplied in this suite is its disposable loopback HTTP fixture.
class _LoopbackFixtureHttp extends HttpOverrides {}

String _session([String id = 'user-a']) => jsonEncode({
  'access_token': 'local-test-access',
  'refresh_token': 'local-test-refresh',
  'token_type': 'bearer',
  'expires_in': 3600,
  'user': {
    'id': id,
    'aud': 'authenticated',
    'role': 'authenticated',
    'is_anonymous': false,
    'created_at': '2026-10-06T00:00:00Z',
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousOverrides = HttpOverrides.current;
  setUpAll(() => HttpOverrides.global = _LoopbackFixtureHttp());
  tearDownAll(() => HttpOverrides.global = previousOverrides);
  late HttpServer server;
  late SupabaseClient client;
  late SharedPreferencesLocalStorage storage;
  late SupabaseAuthRepository repository;
  late StreamSubscription<HttpRequest> subscription;
  var status = 204;
  var logoutStatus = 403;
  var calls = 0;
  var logoutCalls = 0;
  Completer<void>? gate;

  setUp(() async {
    status = 204;
    logoutStatus = 403;
    calls = 0;
    logoutCalls = 0;
    gate = null;
    SharedPreferences.setMockInitialValues({
      'local-favorites': ['retained-store'],
    });
    storage = SharedPreferencesLocalStorage(
      persistSessionKey: 'test-auth-session',
    );
    await storage.initialize();
    await storage.persistSession(_session());
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    subscription = server.listen((request) async {
      if (request.uri.path == '/functions/v1/delete-account') {
        calls++;
        expect(request.method, 'POST');
        expect(request.uri.query, isEmpty);
        expect(
          request.headers.value('Authorization'),
          'Bearer local-test-access',
        );
        expect(request.headers.value('apikey'), 'local-test-public');
        expect(jsonDecode(await utf8.decoder.bind(request).join()), {
          'confirmation': 'DELETE',
        });
        final pending = gate;
        if (pending != null) await pending.future;
        request.response.statusCode = status;
        if (status != 204) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            '{"error":"private JWT postgres secret detail"}',
          );
        }
      } else {
        expect(request.uri.path, '/auth/v1/logout');
        logoutCalls++;
        request.response.statusCode = logoutStatus;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"message":"private logout detail"}');
      }
      await request.response.close();
    });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-public',
    );
    await client.auth.setInitialSession(_session());
    repository = SupabaseAuthRepository(
      client,
      googleServerClientId: '',
      sessionStorage: storage,
    );
  });
  tearDown(() async {
    await client.dispose();
    await subscription.cancel();
    await server.close(force: true);
  });

  for (final remoteLogout in [403, 500]) {
    test(
      '204 clears SDK and persisted session despite logout $remoteLogout',
      () async {
        logoutStatus = remoteLogout;
        await repository.deleteAccount();
        expect(calls, 1);
        expect(logoutCalls, 1);
        expect(client.auth.currentSession, isNull);
        expect(await storage.hasAccessToken(), false);
        expect(
          (await SharedPreferences.getInstance()).getStringList(
            'local-favorites',
          ),
          ['retained-store'],
        );
      },
    );
  }
  for (final response in [401, 404, 503, 200]) {
    test('$response never clears session or exposes raw response', () async {
      status = response;
      await expectLater(
        repository.deleteAccount(),
        throwsA(
          isA<AuthFlowException>().having(
            (e) => e.kind,
            'safe kind',
            response == 401
                ? AuthFailureKind.authentication
                : AuthFailureKind.unknown,
          ),
        ),
      );
      expect(client.auth.currentUser?.id, 'user-a');
      expect(await storage.hasAccessToken(), true);
      expect(logoutCalls, 0);
    });
  }
  test('duplicate repository requests send only one HTTP call', () async {
    gate = Completer<void>();
    final first = repository.deleteAccount();
    await repository.deleteAccount();
    gate!.complete();
    await first;
    expect(calls, 1);
  });
  test('late 204 preserves a different signed-in account', () async {
    gate = Completer<void>();
    final pending = repository.deleteAccount();
    await client.auth.setInitialSession(_session('user-b'));
    await storage.persistSession(_session('user-b'));
    gate!.complete();
    await pending;
    expect(client.auth.currentUser?.id, 'user-b');
    expect(await storage.hasAccessToken(), true);
    expect(logoutCalls, 0);
  });
  test('no session rejects without calling function', () async {
    await client.auth.signOut();
    await expectLater(
      repository.deleteAccount(),
      throwsA(isA<AuthFlowException>()),
    );
    expect(calls, 0);
  });
  test('transport failure preserves local and persisted session', () async {
    await server.close(force: true);
    await expectLater(
      repository.deleteAccount(),
      throwsA(isA<AuthFlowException>()),
    );
    expect(client.auth.currentUser?.id, 'user-a');
    expect(await storage.hasAccessToken(), true);
  });
  test('failed request can retry successfully', () async {
    status = 503;
    await expectLater(
      repository.deleteAccount(),
      throwsA(isA<AuthFlowException>()),
    );
    status = 204;
    await repository.deleteAccount();
    expect(calls, 2);
    expect(client.auth.currentSession, isNull);
    expect(await storage.hasAccessToken(), false);
  });
}
