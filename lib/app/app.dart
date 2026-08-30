import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/favorites/domain/favorite_store_ids_store.dart';
import '../features/map/presentation/map_screen.dart';
import 'app_theme.dart';

class BurgerMapApp extends StatelessWidget {
  const BurgerMapApp({
    super.key,
    required this.config,
    this.supabaseStoreLoader,
    this.favoriteStoreIdsStore,
    this.mapSurfaceBuilder,
  });

  final AppConfig config;
  final SupabaseStoreLoader? supabaseStoreLoader;
  final FavoriteStoreIdsStore? favoriteStoreIdsStore;
  final StoreMapSurfaceBuilder? mapSurfaceBuilder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burger Map Korea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MapScreen(
        config: config,
        supabaseStoreLoader: supabaseStoreLoader,
        favoriteStoreIdsStore: favoriteStoreIdsStore,
        mapSurfaceBuilder: mapSurfaceBuilder,
      ),
    );
  }
}
