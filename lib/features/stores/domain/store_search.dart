import 'burger_style.dart';
import 'store_location.dart';

String normalizeStoreSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

List<StoreLocation> filterStoreLocations(
  List<StoreLocation> stores,
  String query, {
  BurgerStyle? burgerStyle,
}) {
  final normalizedQuery = normalizeStoreSearchText(query);
  if (normalizedQuery.isEmpty && burgerStyle == null) {
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
      return matchesQuery && matchesBurgerStyle;
    }),
  );
}
