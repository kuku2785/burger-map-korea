import 'dart:convert';
import 'dart:io';

import 'package:burger_map_korea/features/stores/data/staging_store_locations_loader.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
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
    final counts = <BurgerStyle, int>{};
    for (final store in stores) {
      final style = BurgerStyle.parse(store.burgerStyle);
      counts[style] = (counts[style] ?? 0) + 1;
    }
    expect(counts, {
      BurgerStyle.classic: 14,
      BurgerStyle.smash: 1,
      BurgerStyle.chicken: 2,
      BurgerStyle.other: 3,
      BurgerStyle.unclassified: 4,
    });
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

  test('parses optional valid and null staging regions', () {
    final stores =
        jsonDecode(File(stagingFixturePath).readAsStringSync())
            as List<dynamic>;
    (stores.first as Map<String, dynamic>)['region'] = {
      'sidoCode': '11',
      'sidoName': '서울특별시',
      'sigunguCode': '11170',
      'sigunguName': '용산구',
      'dongCode': '1117010100',
      'dongName': '후암동',
    };
    (stores[1] as Map<String, dynamic>)['region'] = null;

    final parsed = parseYongsanStagingStoreLocations(jsonEncode(stores));

    expect(parsed.first.region?.sidoCode, '11');
    expect(parsed.first.region?.dongName, '후암동');
    expect(parsed[1].region, isNull);
  });

  test('rejects malformed optional staging regions', () {
    final stores =
        jsonDecode(File(stagingFixturePath).readAsStringSync())
            as List<dynamic>;
    (stores.first as Map<String, dynamic>)['region'] = {'sidoCode': '11'};

    expect(
      () => parseYongsanStagingStoreLocations(jsonEncode(stores)),
      throwsFormatException,
    );
  });
}
