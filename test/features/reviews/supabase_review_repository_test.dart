import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:burger_map_korea/features/reviews/data/supabase_review_repository.dart';
import 'package:burger_map_korea/features/reviews/domain/review_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('public read uses public view and preserves null content', () async {
    final requests = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final subscription = server.listen((request) async {
      requests.add(request);
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        request.uri.path == '/rest/v1/profiles'
            ? '[{"id":"user-a","nickname":"버거팬"}]'
            : jsonEncode([
                {
                  'id': 'review-a',
                  'store_id': 'store-a',
                  'user_id': 'user-a',
                  'rating': 5,
                  'content': null,
                  'created_at': '2026-09-28T00:00:00Z',
                },
              ]),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);
    final client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'local-test-placeholder',
    );
    addTearDown(client.dispose);

    final reviews = await SupabaseReviewRepository(
      clientLoader: () async => client,
    ).loadForStore('store-a');

    expect(reviews, hasLength(1));
    expect(reviews.single.rating, 5);
    expect(reviews.single.content, isNull);
    expect(reviews.single.nickname, '버거팬');
    expect(requests, hasLength(2));
    expect(requests.first.uri.path, '/rest/v1/public_reviews');
    expect(requests.first.uri.queryParameters['store_id'], 'eq.store-a');
    expect(
      requests.first.uri.queryParameters['select'],
      reviewPublicSelectColumns,
    );
    expect(requests.last.uri.path, '/rest/v1/profiles');
    expect(requests.last.uri.queryParameters['select'], 'id,nickname');
  });

  test(
    'real client REST create omits user_id and owner mutations check rows',
    () async {
      final requests = <({String method, Uri uri, String body})>[];
      var zeroRows = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add((method: request.method, uri: request.uri, body: body));
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          request.response.write(
            jsonEncode({
              'access_token': 'local-session',
              'refresh_token': 'local-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'user-a',
                'aud': 'authenticated',
                'created_at': '2026-09-28T00:00:00Z',
              },
            }),
          );
        } else if (request.method == 'POST') {
          request.response.statusCode = HttpStatus.created;
          request.response.write('');
        } else if (request.method == 'PATCH' || request.method == 'DELETE') {
          request.response.write(zeroRows ? '[]' : '[{"id":"review-a"}]');
        } else {
          request.response.write('[]');
        }
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'local-test-placeholder',
      );
      addTearDown(client.dispose);
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'local-id-token',
      );
      final repository = SupabaseReviewRepository(
        clientLoader: () async => client,
      );

      await repository.create(storeId: 'store-a', rating: 3, content: null);
      final insert = requests.last;
      expect(insert.method, 'POST');
      expect(insert.uri.path, '/rest/v1/reviews');
      expect(jsonDecode(insert.body), {
        'store_id': 'store-a',
        'rating': 3,
        'content': null,
      });

      await repository.update(
        reviewId: 'review-a',
        rating: 4,
        content: '맛있어서 또 올게요',
      );
      final update = requests.last;
      expect(update.method, 'PATCH');
      expect(update.uri.queryParameters['id'], 'eq.review-a');
      expect(update.uri.queryParameters['user_id'], 'eq.user-a');
      expect(jsonDecode(update.body), {'rating': 4, 'content': '맛있어서 또 올게요'});

      await repository.delete('review-a');
      final delete = requests.last;
      expect(delete.method, 'DELETE');
      expect(delete.uri.queryParameters['user_id'], 'eq.user-a');

      zeroRows = true;
      await expectLater(
        repository.update(reviewId: 'review-other', rating: 1, content: null),
        throwsA(
          isA<ReviewException>().having(
            (error) => error.failure,
            'failure',
            ReviewFailure.noLongerAvailable,
          ),
        ),
      );
    },
  );

  test(
    'signed-in read includes only the current owner hidden review',
    () async {
      final requests = <Uri>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        requests.add(request.uri);
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path == '/auth/v1/token') {
          request.response.write(
            jsonEncode({
              'access_token': 'local-session',
              'refresh_token': 'local-refresh',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': 'user-a',
                'aud': 'authenticated',
                'created_at': '2026-09-28T00:00:00Z',
              },
            }),
          );
        } else if (request.uri.path == '/rest/v1/reviews') {
          request.response.write(
            jsonEncode([
              {
                'id': 'review-own',
                'store_id': 'store-a',
                'user_id': 'user-a',
                'rating': 2,
                'content': null,
                'created_at': '2026-09-28T00:00:00Z',
                'is_hidden': true,
              },
            ]),
          );
        } else if (request.uri.path == '/rest/v1/profiles') {
          request.response.write('[{"id":"user-a","nickname":"버거팬"}]');
        } else {
          request.response.write('[]');
        }
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'local-test-placeholder',
      );
      addTearDown(client.dispose);
      await client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: 'local-id-token',
      );

      final reviews = await SupabaseReviewRepository(
        clientLoader: () async => client,
      ).loadForStore('store-a', userId: 'user-a');

      expect(reviews, hasLength(1));
      expect(reviews.single.isHidden, isTrue);
      expect(reviews.single.nickname, '버거팬');
      final ownerRead = requests.singleWhere(
        (uri) => uri.path == '/rest/v1/reviews',
      );
      expect(ownerRead.queryParameters['store_id'], 'eq.store-a');
      expect(ownerRead.queryParameters['user_id'], 'eq.user-a');
      expect(ownerRead.queryParameters['select'], reviewOwnerSelectColumns);
    },
  );

  test(
    'backend errors and timeout remain errors rather than empty reviews',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"code":"test","message":"private detail"}');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'local-test-placeholder',
      );
      addTearDown(client.dispose);

      await expectLater(
        SupabaseReviewRepository(
          clientLoader: () async => client,
        ).loadForStore('store-a'),
        throwsA(isA<ReviewException>()),
      );
      final pending = Completer<SupabaseClient>();
      await expectLater(
        SupabaseReviewRepository(
          clientLoader: () => pending.future,
          timeout: Duration.zero,
        ).loadForStore('store-a'),
        throwsA(isA<ReviewException>()),
      );
      await expectLater(
        SupabaseReviewRepository(
          clientLoader: () => pending.future,
          timeout: Duration.zero,
        ).create(storeId: 'store-a', rating: 5, content: null),
        throwsA(
          isA<ReviewException>().having(
            (error) => error.failure,
            'failure',
            ReviewFailure.unknownOutcome,
          ),
        ),
      );
    },
  );
}
