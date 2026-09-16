import 'package:burger_map_korea/features/favorites/application/favorite_store_ids_controller.dart';
import 'package:burger_map_korea/features/favorites/data/shared_preferences_favorite_store_ids_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Async preferences keep the v1 UUID key across failure and recreation',
    () async {
      const a = '11111111-1111-4111-8111-111111111111';
      const b = '22222222-2222-4222-8222-222222222222';
      final preferences = _Preferences();
      preferences.values['favorite_store_ids_v1'] = [a];
      final store = SharedPreferencesFavoriteStoreIdsStore(
        preferences: preferences,
      );
      final controller = FavoriteStoreIdsController(store);
      await controller.initialize();
      expect(controller.storeIds, {a});
      preferences.writeErrors.add(PlatformException(code: 'write_failed'));
      await expectLater(
        controller.setFavorite(b, true),
        throwsA(isA<PlatformException>()),
      );
      expect(controller.storeIds, {a});
      expect(preferences.values['favorite_store_ids_v1'], [a]);
      await controller.setFavorite(b, true);
      controller.dispose();
      final restored = FavoriteStoreIdsController(
        SharedPreferencesFavoriteStoreIdsStore(preferences: preferences),
      );
      await restored.initialize();
      expect(restored.storeIds, {a, b});
      expect(preferences.values.keys, ['favorite_store_ids_v1']);
      restored.dispose();
    },
  );
}

// The app uses SharedPreferencesAsync: setStringList returns Future<void>,
// not the legacy SharedPreferences Future<bool>. Failure is an exception.
class _Preferences extends Fake implements SharedPreferencesAsync {
  final Map<String, List<String>> values = {};
  final List<PlatformException> writeErrors = [];
  @override
  Future<List<String>?> getStringList(String key) async =>
      values[key]?.toList();
  @override
  Future<void> setStringList(String key, List<String> value) async {
    if (writeErrors.isNotEmpty) {
      throw writeErrors.removeAt(0);
    }
    values[key] = value.toList();
  }
}
