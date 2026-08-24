import 'package:burger_map_korea/features/stores/domain/google_maps_directions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uri buildUri({
    String name = 'PPS',
    String address = '서울 용산구 한강대로50길 24',
    double latitude = 37.5339891,
    double longitude = 126.992491,
  }) {
    return buildGoogleMapsDirectionsUri(
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
  }

  test('builds a Google Maps directions URL with store name and address', () {
    final uri = buildUri();

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters, {
      'api': '1',
      'destination': 'PPS, 서울 용산구 한강대로50길 24',
    });
    expect(uri.toString(), contains('destination=PPS%2C'));
    expect(uri.toString(), isNot(contains('서울 용산구')));
  });

  test('includes only the required API version and destination', () {
    final uri = buildUri();

    expect(uri.queryParameters.keys, unorderedEquals(['api', 'destination']));
    expect(uri.queryParameters, isNot(contains('origin')));
    expect(uri.queryParameters, isNot(contains('travelmode')));
    expect(uri.queryParameters, isNot(contains('dir_action')));
    expect(uri.toString(), isNot(contains('key=')));
    expect(uri.toString(), isNot(contains('store-name')));
    expect(uri.toString(), isNot(contains('store-address')));
    expect(uri.toString(), isNot(contains('internal-id')));
  });

  test('falls back to coordinates when name or address is empty', () {
    final missingName = buildUri(
      name: '  ',
      latitude: -33.8688,
      longitude: -70.6693,
    );
    final missingAddress = buildUri(
      address: '',
      latitude: -33.8688,
      longitude: -70.6693,
    );

    expect(missingName.queryParameters['destination'], '-33.8688,-70.6693');
    expect(missingAddress.queryParameters['destination'], '-33.8688,-70.6693');
  });

  test('accepts coordinate boundaries for fallback destinations', () {
    expect(
      buildGoogleMapsDirectionsUri(
        name: '',
        address: '',
        latitude: -90,
        longitude: -180,
      ).queryParameters['destination'],
      '-90,-180',
    );
    expect(
      buildGoogleMapsDirectionsUri(
        name: '',
        address: '',
        latitude: 90,
        longitude: 180,
      ).queryParameters['destination'],
      '90,180',
    );
  });

  test('rejects invalid fallback coordinates', () {
    final invalidCoordinates = <(double, double)>[
      (double.nan, 126),
      (double.infinity, 126),
      (double.negativeInfinity, 126),
      (91, 126),
      (-91, 126),
      (37, double.nan),
      (37, double.infinity),
      (37, double.negativeInfinity),
      (37, 181),
      (37, -181),
    ];

    for (final (latitude, longitude) in invalidCoordinates) {
      expect(
        () => buildGoogleMapsDirectionsUri(
          name: '',
          address: '',
          latitude: latitude,
          longitude: longitude,
        ),
        throwsA(isA<InvalidDirectionsCoordinates>()),
      );
    }
  });
}
