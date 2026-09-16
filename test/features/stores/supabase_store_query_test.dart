import 'dart:io';

import 'package:burger_map_korea/features/stores/data/supabase_store_locations_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final enableRegions in [false, true]) {
    test(
      'public HTTP query preserves visibility with regions=$enableRegions',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final requests = <HttpRequest>[];
        final subscription = server.listen((request) async {
          requests.add(request);
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

        final rows = await fetchPublicSupabaseStoreRows(
          client,
          enableStoreRegions: enableRegions,
        );

        expect(rows, isEmpty);
        expect(requests, hasLength(1));
        final request = requests.single;
        expect(request.method, 'GET');
        expect(request.uri.path, '/rest/v1/stores');
        expect(request.uri.queryParameters, {
          'select':
              'id,name,address,latitude,longitude,burger_style,verification_status'
              '${enableRegions ? ',region' : ''}',
          'verification_status': 'eq.verified',
          'is_active': 'eq.true',
          'order': 'name.asc.nullslast',
        });
      },
    );
  }
}
