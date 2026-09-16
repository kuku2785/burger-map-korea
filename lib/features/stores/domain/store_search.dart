import 'burger_style.dart';
import 'store_location.dart';
import 'store_region.dart';

String normalizeStoreSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<StoreLocation> filterStoreLocations(
  List<StoreLocation> stores,
  String query, {
  BurgerStyle? burgerStyle,
  Set<String> favoriteStoreIds = const <String>{},
  bool favoritesOnly = false,
  StoreRegionFilter? regionFilter,
}) {
  final normalizedQuery = normalizeStoreSearchText(query);
  if (normalizedQuery.isEmpty &&
      burgerStyle == null &&
      !favoritesOnly &&
      regionFilter == null) {
    return List<StoreLocation>.unmodifiable(stores);
  }

  return List<StoreLocation>.unmodifiable(
    stores.where((store) {
      final matchesQuery =
          normalizedQuery.isEmpty ||
          normalizeStoreSearchText(store.name).contains(normalizedQuery) ||
          normalizeStoreSearchText(store.address).contains(normalizedQuery);
      final matchesBurgerStyle =
          burgerStyle == null ||
          BurgerStyle.parse(store.burgerStyle) == burgerStyle;
      final matchesFavorite =
          !favoritesOnly || favoriteStoreIds.contains(store.id);
      final matchesRegion = regionFilter?.matches(store.region) ?? true;
      return matchesQuery &&
          matchesBurgerStyle &&
          matchesFavorite &&
          matchesRegion;
    }),
  );
}
