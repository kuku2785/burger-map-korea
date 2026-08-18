import 'package:burger_map_korea/features/stores/data/supabase_store_locations_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps Supabase rows to StoreLocation with UUID strings', () {
    final stores = mapSupabaseStoreRows([
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Alpha Burger',
        'address': 'Seoul test address 1',
        'latitude': 37.51,
        'longitude': 126.98,
        'burger_style': 'Smash',
        'verification_status': 'verified',
      },
    ]);

    expect(stores, hasLength(1));
    expect(stores.single.id, '11111111-1111-4111-8111-111111111111');
    expect(stores.single.name, 'Alpha Burger');
    expect(stores.single.address, 'Seoul test address 1');
    expect(stores.single.verificationStatus, 'verified');
  });

  test('maps null and empty burger styles to unclassified', () {
    final rows = [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Alpha Burger',
        'address': 'Seoul test address 1',
        'latitude': 37.51,
        'longitude': 126.98,
        'burger_style': null,
        'verification_status': 'verified',
      },
      {
        'id': '22222222-2222-4222-8222-222222222222',
        'name': 'Beta Burger',
        'address': 'Seoul test address 2',
        'latitude': 37.52,
        'longitude': 126.99,
        'burger_style': '   ',
        'verification_status': 'verified',
      },
    ];

    final stores = mapSupabaseStoreRows(rows);

    expect(stores.map((store) => store.burgerStyle), everyElement('미분류'));
  });

  test('rejects rows that are not verified', () {
    final rows = [
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Pending Burger',
        'address': 'Seoul test address',
        'latitude': 37.51,
        'longitude': 126.98,
        'burger_style': null,
        'verification_status': 'pending',
      },
    ];

    expect(() => mapSupabaseStoreRows(rows), throwsFormatException);
  });

  test('loader replaces initialization errors with a safe exception', () async {
    final diagnostics = <String>[];
    String? receivedUrl;
    String? receivedKey;
    final loader = SupabaseStoreLocationsLoader(
      url: '  https://unit.invalid  ',
      publishableKey: '  publishable-test-value  ',
      enableDebugDiagnostics: true,
      diagnosticLogger: diagnostics.add,
      initializer: ({required url, required publishableKey}) async {
        receivedUrl = url;
        receivedKey = publishableKey;
        throw StateError('private initialization detail');
      },
    );

    await expectLater(
      loader.load(),
      throwsA(isA<SupabaseStoreLoadException>()),
    );
    try {
      await loader.load();
      fail('loader should throw');
    } on SupabaseStoreLoadException catch (error) {
      expect(
        error.toString(),
        isNot(contains('private initialization detail')),
      );
      expect(error.toString(), '공개 매장 정보를 불러오지 못했습니다.');
      expect(error.stage, SupabaseStoreLoadStage.initialization);
      expect(error.diagnosticCode, 'client_initialization_failed');
    }
    expect(receivedUrl, 'https://unit.invalid');
    expect(receivedKey, 'publishable-test-value');
    expect(diagnostics, hasLength(2));
    expect(
      diagnostics.first,
      '[SupabaseStoreLoader] stage=initialization '
      'type=StateError code=client_initialization_failed',
    );
    expect(
      diagnostics.join(),
      isNot(contains('private initialization detail')),
    );
    expect(diagnostics.join(), isNot(contains('https://')));
    expect(diagnostics.join(), isNot(contains('publishable-test-value')));
  });

  test('loader records a safe PostgREST code for select failures', () async {
    final diagnostics = <String>[];
    final loader = SupabaseStoreLocationsLoader(
      url: 'https://unit.invalid',
      publishableKey: 'publishable-test-value',
      enableDebugDiagnostics: true,
      diagnosticLogger: diagnostics.add,
      initializer: ({required url, required publishableKey}) async {
        return SupabaseClient(url, publishableKey);
      },
      rowsFetcher: (_) async {
        throw const PostgrestException(
          message: 'private database detail',
          code: 'PGRST301',
        );
      },
    );

    await expectLater(
      loader.load(),
      throwsA(
        isA<SupabaseStoreLoadException>()
            .having(
              (error) => error.stage,
              'stage',
              SupabaseStoreLoadStage.select,
            )
            .having(
              (error) => error.diagnosticCode,
              'diagnosticCode',
              'PGRST301',
            ),
      ),
    );

    expect(diagnostics, hasLength(1));
    expect(
      diagnostics.single,
      '[SupabaseStoreLoader] stage=select '
      'type=PostgrestException code=PGRST301',
    );
    expect(diagnostics.single, isNot(contains('private database detail')));
  });

  test('empty Supabase rows remain a successful empty result', () async {
    final loader = SupabaseStoreLocationsLoader(
      url: 'https://unit.invalid',
      publishableKey: 'publishable-test-value',
      initializer: ({required url, required publishableKey}) async {
        return SupabaseClient(url, publishableKey);
      },
      rowsFetcher: (_) async => [],
    );

    await expectLater(loader.load(), completion(isEmpty));
  });
}
