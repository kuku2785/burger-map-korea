import 'menu_item.dart';

abstract interface class MenuRepository {
  Future<List<MenuItem>> fetchMenusForStore(String storeId);
}
