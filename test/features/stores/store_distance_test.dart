import 'package:burger_map_korea/features/stores/domain/store_distance.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identical coordinates have zero distance', () {
    expect(
      greatCircleDistanceMeters(
        fromLatitude: 37.5665,
        fromLongitude: 126.9780,
        toLatitude: 37.5665,
        toLongitude: 126.9780,
      ),
      closeTo(0, 0.000001),
    );
  });

  test('Seoul City Hall to N Seoul Tower distance is reasonable', () {
    final distance = greatCircleDistanceMeters(
      fromLatitude: 37.5665,
      fromLongitude: 126.9780,
      toLatitude: 37.5512,
      toLongitude: 126.9882,
    );

    expect(distance, inInclusiveRange(1800, 2100));
  });

  test('distance is symmetric', () {
    final forward = greatCircleDistanceMeters(
      fromLatitude: 37.5665,
      fromLongitude: 126.9780,
      toLatitude: 37.5512,
      toLongitude: 126.9882,
    );
    final reverse = greatCircleDistanceMeters(
      fromLatitude: 37.5512,
      fromLongitude: 126.9882,
      toLatitude: 37.5665,
      toLongitude: 126.9780,
    );

    expect(forward, closeTo(reverse, 0.000001));
  });

  test('sorts a nearer store before a farther store', () {
    final farther = _store('farther', 37.58, 127.02);
    final nearer = _store('nearer', 37.531, 126.991);

    expect(
      sortStoreLocationsByDistance(
        [farther, nearer],
        fromLatitude: 37.53,
        fromLongitude: 126.99,
      ),
      [nearer, farther],
    );
  });

  test('does not mutate the input list', () {
    final farther = _store('farther', 37.58, 127.02);
    final nearer = _store('nearer', 37.531, 126.991);
    final stores = [farther, nearer];

    sortStoreLocationsByDistance(
      stores,
      fromLatitude: 37.53,
      fromLongitude: 126.99,
    );

    expect(stores, [farther, nearer]);
  });

  test('preserves the original order for tied distances', () {
    final first = _store('first', 37.531, 126.991);
    final second = _store('second', 37.531, 126.991);

    expect(
      sortStoreLocationsByDistance(
        [second, first],
        fromLatitude: 37.53,
        fromLongitude: 126.99,
      ),
      [second, first],
    );
  });
}

StoreLocation _store(String id, double latitude, double longitude) {
  return StoreLocation(
    id: id,
    name: id,
    latitude: latitude,
    longitude: longitude,
    address: 'Seoul',
    burgerStyle: 'classic',
  );
}
