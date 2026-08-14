import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('itaewon pilot data contains exactly three stores', () {
    expect(itaewonStoreLocations, hasLength(3));
  });

  test('itaewon pilot store ids are unique', () {
    final ids = itaewonStoreLocations.map((store) => store.id).toSet();

    expect(ids, hasLength(itaewonStoreLocations.length));
  });

  test('itaewon pilot coordinates are valid', () {
    expect(
      itaewonStoreLocations.every((store) {
        return store.latitude >= -90 &&
            store.latitude <= 90 &&
            store.longitude >= -180 &&
            store.longitude <= 180;
      }),
      isTrue,
    );
  });

  test('itaewon pilot names and addresses are not empty', () {
    for (final store in itaewonStoreLocations) {
      expect(store.name.trim(), isNotEmpty);
      expect(store.address.trim(), isNotEmpty);
    }
  });
}
