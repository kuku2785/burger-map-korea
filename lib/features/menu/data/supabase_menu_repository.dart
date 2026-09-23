import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/menu_item.dart';
import '../domain/menu_repository.dart';

const menuSelectColumns =
    'id,store_id,name,price,category,description,is_signature,display_order';
const defaultMenuLoadTimeout = Duration(seconds: 10);

class MenuLoadException implements Exception {
  const MenuLoadException();
}

class SupabaseMenuRepository implements MenuRepository {
  SupabaseMenuRepository({
    required this.clientLoader,
    this.timeout = defaultMenuLoadTimeout,
  });

  final Future<SupabaseClient> Function() clientLoader;
  final Duration timeout;

  @override
  Future<List<MenuItem>> fetchMenusForStore(String storeId) async {
    try {
      return await (() async {
        final client = await clientLoader();
        final rows = await fetchPublicMenuRows(client, storeId);
        return mapMenuRows(rows);
      })().timeout(timeout);
    } on Object {
      // Neither database details nor a failed request become an empty menu.
      throw const MenuLoadException();
    }
  }
}

Future<List<Map<String, dynamic>>> fetchPublicMenuRows(
  SupabaseClient client,
  String storeId,
) async {
  final response = await client
      .from('menus')
      .select(menuSelectColumns)
      .eq('store_id', storeId)
      .eq('is_active', true)
      .order('display_order', ascending: true)
      .order('id', ascending: true);
  return response
      .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}
