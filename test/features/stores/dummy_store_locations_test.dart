import 'package:burger_map_korea/features/stores/data/dummy_store_locations.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates StoreLocation with valid coordinates', () {
    final store = StoreLocation(
      id: 'valid',
      name: '테스트 매장',
      latitude: 37.5,
      longitude: 127.0,
      address: '서울특별시 테스트구 테스트로 1',
      burgerStyle: '테스트 버거',
    );

    expect(store.latitude, 37.5);
    expect(store.longitude, 127.0);
  });

  test('rejects invalid latitude', () {
    expect(
      () => StoreLocation(
        id: 'bad-lat',
        name: '테스트 매장',
        latitude: 91,
        longitude: 127.0,
        address: '서울특별시 테스트구 테스트로 1',
        burgerStyle: '테스트 버거',
      ),
      throwsArgumentError,
    );
  });

  test('rejects invalid longitude', () {
    expect(
      () => StoreLocation(
        id: 'bad-lng',
        name: '테스트 매장',
        latitude: 37.5,
        longitude: 181,
        address: '서울특별시 테스트구 테스트로 1',
        burgerStyle: '테스트 버거',
      ),
      throwsArgumentError,
    );
  });

  test('dummy store fields match Phase 1 scope', () {
    for (final store in dummyStoreLocations) {
      expect(store.id, isNotEmpty);
      expect(store.name, isNotEmpty);
      expect(store.address, isNotEmpty);
      expect(store.burgerStyle, isNotEmpty);
    }
  });

  test('dummy data is clearly test data', () {
    expect(
      dummyStoreLocations.every((store) => store.name.startsWith('테스트')),
      isTrue,
    );
  });
}
