import 'store_location.dart';

String normalizeStoreSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<StoreLocation> filterStoreLocations(
  List<StoreLocation> stores,
  String query,
) {
  final normalizedQuery = normalizeStoreSearchText(query);
  if (normalizedQuery.isEmpty) {
    return List<StoreLocation>.unmodifiable(stores);
  }

  return List<StoreLocation>.unmodifiable(
    stores.where((store) {
      return normalizeStoreSearchText(store.name).contains(normalizedQuery) ||
          normalizeStoreSearchText(store.address).contains(normalizedQuery);
    }),
  );
}
