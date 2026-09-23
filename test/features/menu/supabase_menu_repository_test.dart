import 'dart:async';
import 'dart:io';

import 'package:burger_map_korea/features/menu/data/supabase_menu_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'HTTP menu read selects only one active store and orders rows',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write('''[
        {"id":"menu-b","store_id":"store-a","name":"B","price":null,
         "category":null,"description":null,"is_signature":false,"display_order":2},
        {"id":"menu-a","store_id":"store-a","name":"A","price":12900,
         "category":"버거","description":"설명","is_signature":true,"display_order":1}
      ]''');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'local-test-placeholder',
      );
      addTearDown(client.dispose);
      final repository = SupabaseMenuRepository(
        clientLoader: () async => client,
      );

      final menus = await repository.fetchMenusForStore('store-a');

      expect(menus.map((menu) => menu.id), ['menu-a', 'menu-b']);
      expect(menus.first.price, 12900);
      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/rest/v1/menus');
      expect(request.uri.queryParameters, {
        'select': menuSelectColumns,
        'store_id': 'eq.store-a',
        'is_active': 'eq.true',
        'order': 'display_order.asc.nullslast,id.asc.nullslast',
      });
    },
  );

  test('empty result remains an empty successful list', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write('[]');
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);

    final result = await SupabaseMenuRepository(
      clientLoader: () async => client,
    ).fetchMenusForStore('store-a');
    expect(result, isEmpty);
  });

  test('backend error and timeout stay distinct from empty', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"code":"test","message":"private"}');
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);

    await expectLater(
      SupabaseMenuRepository(
        clientLoader: () async => client,
      ).fetchMenusForStore('store-a'),
      throwsA(isA<MenuLoadException>()),
    );

    final pending = Completer<SupabaseClient>();
    await expectLater(
      SupabaseMenuRepository(
        clientLoader: () => pending.future,
        timeout: Duration.zero,
      ).fetchMenusForStore('store-a'),
      throwsA(isA<MenuLoadException>()),
    );
  });
}
