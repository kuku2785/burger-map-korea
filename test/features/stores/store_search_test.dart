import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/domain/store_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stores = <StoreLocation>[
    StoreLocation(
      id: 'alpha',
      name: 'Alpha Burger',
      address: 'Seoul Yongsan Alpha-ro 1',
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: '미분류',
    ),
    StoreLocation(
      id: 'beta',
      name: 'Beta Kitchen',
      address: 'Seoul Itaewon Burger-gil 2',
      latitude: 37.54,
      longitude: 127.0,
      burgerStyle: '미분류',
    ),
  ];

  test('normalizes leading, trailing, repeated spaces, and letter case', () {
    expect(normalizeStoreSearchText('  ALPHA   Burger  '), 'alpha burger');
  });

  test('finds stores by a partial name', () {
    expect(filterStoreLocations(stores, 'pha bur'), [stores.first]);
  });

  test('finds stores by a partial address', () {
    expect(filterStoreLocations(stores, 'itaewon burger'), [stores.last]);
  });

  test('an empty normalized query returns every loaded store', () {
    expect(filterStoreLocations(stores, '   '), stores);
  });

  test('returns an empty list when no store matches', () {
    expect(filterStoreLocations(stores, 'not present'), isEmpty);
  });
}
