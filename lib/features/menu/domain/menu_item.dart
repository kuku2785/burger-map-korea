class MenuItem {
  const MenuItem({
    required this.id,
    required this.storeId,
    required this.name,
    required this.price,
    required this.category,
    required this.description,
    required this.isSignature,
    required this.displayOrder,
  });

  final String id;
  final String storeId;
  final String name;
  final int? price;
  final String? category;
  final String? description;
  final bool isSignature;
  final int displayOrder;

  factory MenuItem.fromJson(Map<String, dynamic> row) {
    final id = row['id'];
    final storeId = row['store_id'];
    final name = row['name'];
    final price = row['price'];
    final category = row['category'];
    final description = row['description'];
    final isSignature = row['is_signature'];
    final displayOrder = row['display_order'];

    if (id is! String ||
        id.isEmpty ||
        storeId is! String ||
        storeId.isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        (price != null && (price is! int || price < 0)) ||
        (category != null && category is! String) ||
        (description != null && description is! String) ||
        isSignature is! bool ||
        displayOrder is! int ||
        displayOrder < 0) {
      throw const FormatException('Invalid menu row');
    }

    return MenuItem(
      id: id,
      storeId: storeId,
      name: name,
      price: price as int?,
      category: category as String?,
      description: description as String?,
      isSignature: isSignature,
      displayOrder: displayOrder,
    );
  }
}

List<MenuItem> mapMenuRows(List<Map<String, dynamic>> rows) {
  final menus = rows.map(MenuItem.fromJson).toList()
    ..sort((a, b) {
      final order = a.displayOrder.compareTo(b.displayOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  return List.unmodifiable(menus);
}
