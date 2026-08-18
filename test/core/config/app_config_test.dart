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
    test(
      'parses staging and supabase and defaults unknown values to pilot',
      () {
        expect(StoreDataMode.parse('staging'), StoreDataMode.staging);
        expect(StoreDataMode.parse('supabase'), StoreDataMode.supabase);
        expect(StoreDataMode.parse('pilot'), StoreDataMode.pilot);
        expect(StoreDataMode.parse('unknown'), StoreDataMode.pilot);
      },
    );

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

    test('enables supabase data only in development environment', () {
      const development = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.supabase,
      );
      const production = AppConfig(
        environment: AppEnvironment.production,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.supabase,
      );

      expect(development.usesSupabaseStoreData, isTrue);
      expect(development.effectiveStoreDataMode, StoreDataMode.supabase);
      expect(production.usesSupabaseStoreData, isFalse);
      expect(production.effectiveStoreDataMode, StoreDataMode.pilot);
    });

    test('detects missing Supabase URL and publishable key separately', () {
      const missingUrl = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        supabasePublishableKey: 'publishable-test-value',
      );
      const missingKey = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        supabaseUrl: 'https://unit.invalid',
      );
      const configured = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        supabaseUrl: 'https://unit.invalid',
        supabasePublishableKey: 'publishable-test-value',
      );

      expect(missingUrl.hasSupabaseUrl, isFalse);
      expect(missingUrl.hasSupabaseConfiguration, isFalse);
      expect(missingKey.hasSupabasePublishableKey, isFalse);
      expect(missingKey.hasSupabaseConfiguration, isFalse);
      expect(configured.hasSupabaseConfiguration, isTrue);
    });

    test('pilot and staging modes do not require Supabase configuration', () {
      const pilot = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
      );
      const staging = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.staging,
      );

      expect(pilot.hasSupabaseConfiguration, isFalse);
      expect(pilot.effectiveStoreDataMode, StoreDataMode.pilot);
      expect(staging.hasSupabaseConfiguration, isFalse);
      expect(staging.effectiveStoreDataMode, StoreDataMode.staging);
    });
  });
}
