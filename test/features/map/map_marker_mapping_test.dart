import 'package:burger_map_korea/features/stores/data/dummy_store_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dummy stores have stable marker ids and Seoul coordinates', () {
    final ids = dummyStoreLocations.map((store) => store.id).toSet();

    expect(dummyStoreLocations, hasLength(3));
    expect(ids, hasLength(3));
    expect(
      dummyStoreLocations.every((store) {
        return store.latitude >= 37.0 &&
            store.latitude <= 38.0 &&
            store.longitude >= 126.0 &&
            store.longitude <= 128.0;
      }),
      isTrue,
    );
  });

  test('dummy stores have distinct burger styles', () {
    final styles = dummyStoreLocations
        .map((store) => store.burgerStyle)
        .toSet();

    expect(styles, hasLength(3));
  });
}
