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
        return AppEnvironment.production;
      case 'development':
      case 'dev':
      default:
        return AppEnvironment.development;
    }
  }
}

class AppConfig {
  const AppConfig({required this.environment, required this.googleMapsApiKey});

  factory AppConfig.fromDartDefines() {
    return AppConfig(
      environment: AppEnvironment.parse(
        const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
      ),
      googleMapsApiKey: const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
    );
  }

  final AppEnvironment environment;
  final String googleMapsApiKey;

  bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;

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
