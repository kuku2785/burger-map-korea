import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/favorites/domain/favorite_store_ids_store.dart';
import '../features/map/presentation/map_screen.dart';
import '../features/menu/domain/menu_repository.dart';
import 'app_theme.dart';

typedef AuthControllerLoader = Future<AuthController> Function();

class BurgerMapApp extends StatelessWidget {
  const BurgerMapApp({
    super.key,
    required this.config,
    this.supabaseStoreLoader,
    this.favoriteStoreIdsStore,
    this.mapSurfaceBuilder,
    this.authControllerLoader,
    this.menuRepository,
  });

  final AppConfig config;
  final SupabaseStoreLoader? supabaseStoreLoader;
  final FavoriteStoreIdsStore? favoriteStoreIdsStore;
  final StoreMapSurfaceBuilder? mapSurfaceBuilder;
  final AuthControllerLoader? authControllerLoader;
  final MenuRepository? menuRepository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burger Map Korea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: authControllerLoader == null
          ? _buildMapScreen()
          : AuthGate(
              controllerLoader: authControllerLoader!,
              publicBuilder:
                  (context, onSignIn, onSignOut, onSetNickname, onRetryAuth) =>
                      _buildMapScreen(
                        onSignIn: onSignIn,
                        onSignOut: onSignOut,
                        onSetNickname: onSetNickname,
                        onRetryAuth: onRetryAuth,
                      ),
            ),
    );
  }

  Widget _buildMapScreen({
    VoidCallback? onSignIn,
    Future<void> Function()? onSignOut,
    VoidCallback? onSetNickname,
    VoidCallback? onRetryAuth,
  }) => MapScreen(
    config: config,
    supabaseStoreLoader: supabaseStoreLoader,
    favoriteStoreIdsStore: favoriteStoreIdsStore,
    mapSurfaceBuilder: mapSurfaceBuilder,
    onSignIn: onSignIn,
    onSignOut: onSignOut,
    onSetNickname: onSetNickname,
    onRetryAuth: onRetryAuth,
    menuRepository: menuRepository,
  );
}
