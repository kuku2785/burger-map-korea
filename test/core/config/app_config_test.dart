import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEnvironment', () {
    test('parses known environment names', () {
      expect(AppEnvironment.parse('development'), AppEnvironment.development);
      expect(AppEnvironment.parse('staging'), AppEnvironment.staging);
      expect(AppEnvironment.parse('production'), AppEnvironment.production);
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
}
