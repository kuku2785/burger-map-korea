import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'features/stores/data/supabase_store_locations_loader.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromDartDefines();
  final supabaseLoader =
      config.usesSupabaseStoreData && config.hasSupabaseConfiguration
      ? SupabaseStoreLocationsLoader(
          url: config.supabaseUrl,
          publishableKey: config.supabasePublishableKey,
          enableDebugDiagnostics: true,
        )
      : null;

  runApp(
    BurgerMapApp(config: config, supabaseStoreLoader: supabaseLoader?.load),
  );
}
