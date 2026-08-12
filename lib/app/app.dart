import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/map/presentation/map_screen.dart';
import 'app_theme.dart';

class BurgerMapApp extends StatelessWidget {
  const BurgerMapApp({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Burger Map Korea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MapScreen(config: config),
    );
  }
}
