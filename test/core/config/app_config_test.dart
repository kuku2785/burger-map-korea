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

  group('runtime policy', () {
    test('debug development honors pilot, staging, and supabase', () {
      for (final mode in StoreDataMode.values) {
        final policy = resolveRuntimePolicy(
          requestedEnvironment: AppEnvironment.development,
          requestedStoreDataMode: mode,
          isReleaseMode: false,
        );

        expect(policy.environment, AppEnvironment.development);
        expect(policy.storeDataMode, mode);
        expect(policy.dataModeWasOverridden, isFalse);
      }
    });

    test('debug production always resolves to supabase', () {
      for (final mode in StoreDataMode.values) {
        final policy = resolveRuntimePolicy(
          requestedEnvironment: AppEnvironment.production,
          requestedStoreDataMode: mode,
          isReleaseMode: false,
        );

        expect(policy.environment, AppEnvironment.production);
        expect(policy.storeDataMode, StoreDataMode.supabase);
        expect(policy.dataModeWasOverridden, mode != StoreDataMode.supabase);
      }
    });

    test('release always resolves to production supabase', () {
      for (final environment in AppEnvironment.values) {
        for (final mode in StoreDataMode.values) {
          final policy = resolveRuntimePolicy(
            requestedEnvironment: environment,
            requestedStoreDataMode: mode,
            isReleaseMode: true,
          );

          expect(policy.environment, AppEnvironment.production);
          expect(policy.storeDataMode, StoreDataMode.supabase);
        }
      }
    });

    test('AppConfig defaults debug execution to development pilot', () {
      const config = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
      );

      expect(config.effectiveEnvironment, AppEnvironment.development);
      expect(config.effectiveStoreDataMode, StoreDataMode.pilot);
      expect(config.usesStagingStoreData, isFalse);
      expect(config.usesSupabaseStoreData, isFalse);
      expect(config.showsDevelopmentDiagnostics, isTrue);
    });

    test('release AppConfig cannot select pilot or staging data', () {
      const pilotRequest = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        isReleaseMode: true,
      );
      const stagingRequest = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.staging,
        isReleaseMode: true,
      );

      for (final config in [pilotRequest, stagingRequest]) {
        expect(config.effectiveEnvironment, AppEnvironment.production);
        expect(config.effectiveStoreDataMode, StoreDataMode.supabase);
        expect(config.usesStagingStoreData, isFalse);
        expect(config.usesSupabaseStoreData, isTrue);
        expect(config.showsDevelopmentDiagnostics, isFalse);
        expect(config.safeDiagnosticCodes, contains('disallowed_data_mode'));
      }
    });
  });

  group('Supabase configuration', () {
    test('trims a valid base URL and publishable key', () {
      final validation = validateSupabaseConfiguration(
        url: '  https://unit.invalid/  ',
        publishableKey: '  public-test-value  ',
      );

      expect(validation.isValid, isTrue);
      expect(validation.url, 'https://unit.invalid/');
      expect(validation.publishableKey, 'public-test-value');
    });

    test('reports missing URL and publishable key separately', () {
      final validation = validateSupabaseConfiguration(
        url: '   ',
        publishableKey: '',
      );

      expect(
        validation.issues,
        containsAll([
          SupabaseConfigIssue.missingUrl,
          SupabaseConfigIssue.missingPublishableKey,
        ]),
      );
    });

    test('rejects http and non-base URLs', () {
      for (final url in [
        'http://unit.invalid',
        'https://unit.invalid/functions/v1',
        'https://user@unit.invalid',
        'https://unit.invalid?query=value',
        'https://unit.invalid#fragment',
      ]) {
        final validation = validateSupabaseConfiguration(
          url: url,
          publishableKey: 'public-test-value',
        );

        expect(
          validation.issues,
          contains(SupabaseConfigIssue.invalidUrl),
          reason: url,
        );
      }
    });

    test('rejects URLs containing the REST API path', () {
      for (final url in [
        'https://unit.invalid/rest/v1',
        'https://unit.invalid/rest/v1/',
        'https://unit.invalid/rest/v1/stores',
      ]) {
        final validation = validateSupabaseConfiguration(
          url: url,
          publishableKey: 'public-test-value',
        );

        expect(
          validation.issues,
          contains(SupabaseConfigIssue.urlHasRestPath),
          reason: url,
        );
      }
    });

    test('rejects obvious secret and service-role keys', () {
      const legacyServiceRoleJwt =
          'header.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature';
      for (final key in [
        'sb_secret_test-placeholder',
        'service_role_test-placeholder',
        legacyServiceRoleJwt,
      ]) {
        final validation = validateSupabaseConfiguration(
          url: 'https://unit.invalid',
          publishableKey: key,
        );

        expect(
          validation.issues,
          contains(SupabaseConfigIssue.disallowedPrivilegedKey),
        );
      }
    });

    test('does not overfit future publishable key formats', () {
      final validation = validateSupabaseConfiguration(
        url: 'https://unit.invalid',
        publishableKey: 'future-public-client-format',
      );

      expect(validation.isValid, isTrue);
    });

    test('AppConfig exposes validated normalized values', () {
      const config = AppConfig(
        environment: AppEnvironment.development,
        googleMapsApiKey: '',
        storeDataMode: StoreDataMode.supabase,
        supabaseUrl: '  https://unit.invalid  ',
        supabasePublishableKey: '  public-test-value  ',
      );

      expect(config.hasSupabaseConfiguration, isTrue);
      expect(config.normalizedSupabaseUrl, 'https://unit.invalid');
      expect(config.normalizedSupabasePublishableKey, 'public-test-value');
    });
  });

  test('detects missing and configured Google Maps API keys', () {
    const missing = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: '  ',
    );
    const configured = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: 'test-key',
    );

    expect(missing.hasGoogleMapsApiKey, isFalse);
    expect(configured.hasGoogleMapsApiKey, isTrue);
  });

  test('pilot and staging do not require Supabase configuration', () {
    const pilot = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: '',
    );
    const staging = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: '',
      storeDataMode: StoreDataMode.staging,
    );

    expect(pilot.effectiveStoreDataMode, StoreDataMode.pilot);
    expect(staging.effectiveStoreDataMode, StoreDataMode.staging);
  });

  test('development diagnostics contain codes but no configured values', () {
    const secretValue = 'service_role_private-placeholder';
    const config = AppConfig(
      environment: AppEnvironment.development,
      googleMapsApiKey: '',
      storeDataMode: StoreDataMode.supabase,
      supabaseUrl: 'http://private-host.invalid',
      supabasePublishableKey: secretValue,
    );
    final logs = <String>[];

    logDevelopmentConfigurationDiagnostics(config, logger: logs.add);

    expect(logs, isNotEmpty);
    expect(logs.join(), contains('invalid_supabase_url'));
    expect(logs.join(), contains('disallowed_privileged_key'));
    expect(logs.join(), isNot(contains('private-host')));
    expect(logs.join(), isNot(contains(secretValue)));
  });

  test('production does not emit configuration diagnostics', () {
    const config = AppConfig(
      environment: AppEnvironment.production,
      googleMapsApiKey: '',
      storeDataMode: StoreDataMode.pilot,
    );
    final logs = <String>[];

    logDevelopmentConfigurationDiagnostics(config, logger: logs.add);

    expect(logs, isEmpty);
  });
}
