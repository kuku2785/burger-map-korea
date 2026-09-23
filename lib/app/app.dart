import 'dart:async';

import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/favorites/domain/favorite_store_ids_store.dart';
import '../features/map/presentation/map_screen.dart';
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
  });

  final AppConfig config;
  final SupabaseStoreLoader? supabaseStoreLoader;
  final FavoriteStoreIdsStore? favoriteStoreIdsStore;
  final StoreMapSurfaceBuilder? mapSurfaceBuilder;
  final AuthControllerLoader? authControllerLoader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burger Map Korea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: authControllerLoader == null
          ? _buildMapScreen()
          : _AuthBootstrap(
              loader: authControllerLoader!,
              signedInBuilder: (context, signOut) =>
                  _buildMapScreen(onSignOut: signOut),
            ),
    );
  }

  Widget _buildMapScreen({Future<void> Function()? onSignOut}) => MapScreen(
    config: config,
    supabaseStoreLoader: supabaseStoreLoader,
    favoriteStoreIdsStore: favoriteStoreIdsStore,
    mapSurfaceBuilder: mapSurfaceBuilder,
    onSignOut: onSignOut,
  );
}

class _AuthBootstrap extends StatefulWidget {
  const _AuthBootstrap({required this.loader, required this.signedInBuilder});

  final AuthControllerLoader loader;
  final Widget Function(BuildContext, Future<void> Function()) signedInBuilder;

  @override
  State<_AuthBootstrap> createState() => _AuthBootstrapState();
}

class _AuthBootstrapState extends State<_AuthBootstrap> {
  AuthController? _controller;
  bool _loading = true;
  bool _loadInProgress = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_loadInProgress) return;
    _loadInProgress = true;
    if (!_loading) setState(() => _loading = true);
    try {
      final controller = await widget.loader();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _controller = null;
        _loading = false;
      });
    } finally {
      _loadInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) {
      return AuthGate(
        controller: controller,
        signedInBuilder: widget.signedInBuilder,
      );
    }
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Semantics(
            liveRegion: true,
            label: '로그인 기능 준비 중',
            child: const CircularProgressIndicator(),
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '로그인 기능을 준비하지 못했습니다. 네트워크 연결을 확인해 주세요.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _load,
                      child: const Text('다시 시도'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
