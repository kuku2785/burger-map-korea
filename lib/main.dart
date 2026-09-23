import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/auth/data/supabase_auth_repository.dart';
import 'features/menu/data/supabase_menu_repository.dart';
import 'features/stores/data/supabase_store_locations_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromDartDefines();
  logDevelopmentConfigurationDiagnostics(config);
  SupabaseClient? sharedClient;
  Future<SupabaseClient>? clientInitialization;
  Future<SupabaseClient> loadSupabaseClient() {
    final client = sharedClient;
    if (client != null) return Future<SupabaseClient>.value(client);
    final current = clientInitialization;
    if (current != null) return current;

    late final Future<SupabaseClient> attempt;
    attempt =
        initializeSupabaseClient(
              url: config.normalizedSupabaseUrl,
              publishableKey: config.normalizedSupabasePublishableKey,
            )
            .then((value) {
              sharedClient = value;
              return value;
            })
            .whenComplete(() {
              if (identical(clientInitialization, attempt)) {
                clientInitialization = null;
              }
            });
    clientInitialization = attempt;
    return attempt;
  }

  final supabaseLoader =
      config.usesSupabaseStoreData && config.hasSupabaseConfiguration
      ? SupabaseStoreLocationsLoader(
          url: config.normalizedSupabaseUrl,
          publishableKey: config.normalizedSupabasePublishableKey,
          initializer: ({required url, required publishableKey}) =>
              loadSupabaseClient(),
          enableDebugDiagnostics: config.showsDevelopmentDiagnostics,
          enableStoreRegions: config.enableStoreRegions,
        )
      : null;
  final authControllerLoader = config.hasSupabaseConfiguration
      ? () async =>
            AuthController(SupabaseAuthRepository(await loadSupabaseClient()))
      : null;
  final menuRepository =
      config.usesSupabaseStoreData && config.hasSupabaseConfiguration
      ? SupabaseMenuRepository(clientLoader: loadSupabaseClient)
      : null;

  runApp(
    BurgerMapApp(
      config: config,
      supabaseStoreLoader: supabaseLoader?.load,
      authControllerLoader: authControllerLoader,
      menuRepository: menuRepository,
    ),
  );
}
