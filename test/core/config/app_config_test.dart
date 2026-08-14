import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment', () {
    test('parses known environment names', () {
      expect(AppEnvironment.parse('development'), AppEnvironment.development);
      expect(AppEnvironment.parse('staging'), AppEnvironment.staging);
      expect(AppEnvironment.parse('production'), AppEnvironment.production);
      expect(AppEnvironment.parse('release'), AppEnvironment.production);
    });

    test('defaults unknown values to development', () {
      expect(AppEnvironment.parse('unknown'), AppEnvironment.development);
    });
  });

  test('detects missing Google Maps API key', () {
    const config = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: '',
    );

    expect(config.hasGoogleMapsApiKey, isFalse);
  });

  test('detects configured Google Maps API key', () {
    const config = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: 'test-key',
    );

    expect(config.hasGoogleMapsApiKey, isTrue);
  });

  group('StoreDataMode', () {
    test('parses staging and defaults all other values to pilot', () {
      expect(StoreDataMode.parse('staging'), StoreDataMode.staging);
      expect(StoreDataMode.parse('pilot'), StoreDataMode.pilot);
      expect(StoreDataMode.parse('unknown'), StoreDataMode.pilot);
    });

    test('defaults AppConfig data mode to pilot', () {
      const config = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
      );

      expect(config.storeDataMode, StoreDataMode.pilot);
      expect(config.effectiveStoreDataMode, StoreDataMode.pilot);
    });

    test('enables staging data only in development environment', () {
      const development = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.staging,
      );
      const stagingEnvironment = AppConfig(
        environment: AppEnvironment.staging,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.staging,
      );
      const production = AppConfig(
        environment: AppEnvironment.production,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.staging,
      );

      expect(development.usesStagingStoreData, isTrue);
      expect(development.effectiveStoreDataMode, StoreDataMode.staging);
      expect(stagingEnvironment.usesStagingStoreData, isFalse);
      expect(stagingEnvironment.effectiveStoreDataMode, StoreDataMode.pilot);
      expect(production.usesStagingStoreData, isFalse);
      expect(production.effectiveStoreDataMode, StoreDataMode.pilot);
    });
  });
}
