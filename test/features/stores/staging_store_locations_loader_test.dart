import 'dart:convert';
import 'dart:io';

import 'package:burger_map_korea/features/stores/data/staging_store_locations_loader.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/staging_fixture.dart';

class FixtureAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(
      utf8.encode(File(stagingFixturePath).readAsStringSync()),
    );
    return ByteData.sublistView(bytes);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads exactly 24 unique pending staging stores from asset', () async {
    final stores = await loadYongsanStagingStoreLocations(
      bundle: FixtureAssetBundle(),
    );

    expect(stores, hasLength(24));
    expect(stores.map((store) => store.id).toSet(), hasLength(24));
    expect(
      stores.every(
        (store) =>
            store.latitude >= -90 &&
            store.latitude <= 90 &&
            store.longitude >= -180 &&
            store.longitude <= 180 &&
            store.verificationStatus == 'pending',
      ),
      isTrue,
    );
  });

  test('rejects malformed staging JSON', () {
    expect(
      () => parseYongsanStagingStoreLocations('{bad json'),
      throwsFormatException,
    );
  });

  test('rejects forbidden external place fields', () {
    final stores = List.generate(24, (index) {
      return {
        'id': 'candidate-$index',
        'name': '테스트 매장 $index',
        'address': '서울 용산구 테스트로 $index',
        'latitude': 37.5,
        'longitude': 127.0,
        'burgerStyle': '미분류',
        'verificationStatus': 'pending',
        'sourcePlaceId': 'external-$index',
      };
    });

    expect(
      () => parseYongsanStagingStoreLocations(jsonEncode(stores)),
      throwsFormatException,
    );
  });
}
