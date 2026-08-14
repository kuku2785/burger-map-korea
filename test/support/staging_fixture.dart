import 'dart:io';

import 'package:burger_map_korea/features/stores/data/staging_store_locations_loader.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';

const stagingFixturePath = 'test/fixtures/virtual_staging_store_locations.json';

List<StoreLocation> loadStagingFixture() {
  return parseYongsanStagingStoreLocations(
    File(stagingFixturePath).readAsStringSync(),
  );
}
