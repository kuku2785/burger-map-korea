import 'package:shared_preferences/shared_preferences.dart';

import '../domain/favorite_store_ids_store.dart';

class SharedPreferencesFavoriteStoreIdsStore implements FavoriteStoreIdsStore {
  SharedPreferencesFavoriteStoreIdsStore({this.preferences});

  static const storageKey = 'favorite_store_ids_v1';

  final SharedPreferencesAsync? preferences;

  SharedPreferencesAsync get _client => preferences ?? SharedPreferencesAsync();

  @override
  Future<Set<String>> load() async {
    final values = await _client.getStringList(storageKey);
    return Set<String>.unmodifiable(
      (values ?? const <String>[])
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty),
    );
  }

  @override
  Future<void> save(Set<String> storeIds) async {
    final values =
        storeIds
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    await _client.setStringList(storageKey, values);
  }
}
