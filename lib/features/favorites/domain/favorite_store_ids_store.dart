abstract interface class FavoriteStoreIdsStore {
  Future<Set<String>> load();

  Future<void> save(Set<String> storeIds);
}
