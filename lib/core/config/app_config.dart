import 'package:flutter/foundation.dart';

enum AppEnvironment {
  development,
  staging,
  production;

  static AppEnvironment parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
      case 'release':
        return AppEnvironment.production;
      case 'development':
      case 'dev':
      default:
        return AppEnvironment.development;
    }
  }
}

enum StoreDataMode {
  pilot,
  staging;

  static StoreDataMode parse(String value) {
    return value.trim().toLowerCase() == 'staging'
        ? StoreDataMode.staging
        : StoreDataMode.pilot;
  }
}

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.googleMapsApiKey,
    this.storeDataMode = StoreDataMode.pilot,
  });

  factory AppConfig.fromDartDefines() {
    return AppConfig(
      environment: AppEnvironment.parse(
        const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
      ),
      googleMapsApiKey: const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
      storeDataMode: StoreDataMode.parse(
        const String.fromEnvironment('STORE_DATA_MODE', defaultValue: 'pilot'),
      ),
    );
  }

  final AppEnvironment environment;
  final String googleMapsApiKey;
  final StoreDataMode storeDataMode;

  bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;

  bool get usesStagingStoreData =>
      !kReleaseMode &&
      environment == AppEnvironment.development &&
      storeDataMode == StoreDataMode.staging;

  StoreDataMode get effectiveStoreDataMode =>
      usesStagingStoreData ? StoreDataMode.staging : StoreDataMode.pilot;

  String get environmentLabel {
    switch (environment) {
      case AppEnvironment.development:
        return 'Development';
      case AppEnvironment.staging:
        return 'Staging';
      case AppEnvironment.production:
        return 'Production';
    }
  }
}
