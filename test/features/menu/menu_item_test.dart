import 'package:burger_map_korea/features/menu/domain/menu_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> row({
    String id = 'menu-b',
    int? price = 12900,
    String? category = '버거',
    String? description = '체다치즈',
    bool isSignature = true,
    int displayOrder = 2,
  }) => {
    'id': id,
    'store_id': 'store-a',
    'name': '더블 치즈버거',
    'price': price,
    'category': category,
    'description': description,
    'is_signature': isSignature,
    'display_order': displayOrder,
  };

  test('parses complete and nullable menu rows', () {
    final complete = MenuItem.fromJson(row());
    expect(complete.id, 'menu-b');
    expect(complete.storeId, 'store-a');
    expect(complete.name, '더블 치즈버거');
    expect(complete.price, 12900);
    expect(complete.category, '버거');
    expect(complete.description, '체다치즈');
    expect(complete.isSignature, isTrue);
    expect(complete.displayOrder, 2);

    final nullable = MenuItem.fromJson(
      row(price: null, category: null, description: null, isSignature: false),
    );
    expect(nullable.price, isNull);
    expect(nullable.category, isNull);
    expect(nullable.description, isNull);
    expect(nullable.isSignature, isFalse);
  });

  test('rejects malformed required fields and invalid price', () {
    for (final invalid in [
      {...row(), 'id': null},
      {...row(), 'store_id': ''},
      {...row(), 'name': '   '},
      {...row(), 'is_signature': null},
      {...row(), 'display_order': -1},
      {...row(), 'price': -1},
      {...row(), 'price': '12900'},
    ]) {
      expect(() => MenuItem.fromJson(invalid), throwsFormatException);
    }
  });

  test('orders by display_order then stable id, independent of signature', () {
    final menus = mapMenuRows([
      row(id: 'menu-z', displayOrder: 2),
      row(id: 'menu-b', displayOrder: 1),
      row(id: 'menu-a', displayOrder: 1, isSignature: false),
    ]);
    expect(menus.map((menu) => menu.id), ['menu-a', 'menu-b', 'menu-z']);
    expect(() => menus.clear(), throwsUnsupportedError);
  });
}
