import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:burger_map_korea/features/stores/data/supabase_store_locations_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/staging_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('itaewon stores have stable marker ids and Seoul coordinates', () {
    final ids = itaewonStoreLocations.map((store) => store.id).toSet();

    expect(itaewonStoreLocations, hasLength(3));
    expect(ids, hasLength(3));
    expect(
      itaewonStoreLocations.every((store) {
        return store.latitude >= 37.0 &&
            store.latitude <= 38.0 &&
            store.longitude >= 126.0 &&
            store.longitude <= 128.0;
      }),
      isTrue,
    );
  });

  test('map marker creation target is exactly three stores', () {
    expect(itaewonStoreLocations, hasLength(3));
  });

  test(
    'staging stores map to exactly 24 markers using candidate ids',
    () async {
      final stores = loadStagingFixture();
      String? selectedId;
      final markers = buildStoreMarkers(stores, (store) {
        selectedId = store.id;
      });

      expect(markers, hasLength(24));
      expect(
        markers.map((marker) => marker.markerId.value).toSet(),
        stores.map((store) => store.id).toSet(),
      );
      markers.first.onTap?.call();
      expect(selectedId, markers.first.markerId.value);

      final camera = cameraPositionForStores(stores);
      final latitudes = stores.map((store) => store.latitude);
      final longitudes = stores.map((store) => store.longitude);
      expect(
        camera.target.latitude,
        inInclusiveRange(
          latitudes.reduce((left, right) => left < right ? left : right),
          latitudes.reduce((left, right) => left > right ? left : right),
        ),
      );
      expect(
        camera.target.longitude,
        inInclusiveRange(
          longitudes.reduce((left, right) => left < right ? left : right),
          longitudes.reduce((left, right) => left > right ? left : right),
        ),
      );
    },
  );

  test('Supabase store rows map to markers using internal UUIDs', () {
    final stores = mapSupabaseStoreRows([
      {
        'id': '11111111-1111-4111-8111-111111111111',
        'name': 'Alpha Burger',
        'address': 'Seoul test address',
        'latitude': 37.51,
        'longitude': 126.98,
        'burger_style': null,
        'verification_status': 'verified',
      },
    ]);

    final markers = buildStoreMarkers(stores, (_) {});

    expect(markers, hasLength(1));
    expect(
      markers.single.markerId.value,
      '11111111-1111-4111-8111-111111111111',
    );
  });
}
