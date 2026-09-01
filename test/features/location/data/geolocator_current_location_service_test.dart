import 'dart:async';

import 'package:burger_map_korea/features/location/data/geolocator_current_location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geolocator;

void main() {
  group('GeolocatorCurrentLocationService.getCurrentLocation', () {
    final now = DateTime.utc(2026, 9, 1, 12);

    test(
      'returns a recent cache without requesting a fresh position',
      () async {
        var freshPositionCalls = 0;
        final service = GeolocatorCurrentLocationService(
          lastKnownPositionLoader: () async => _position(
            latitude: 37.5665,
            longitude: 126.9780,
            timestamp: now.subtract(const Duration(minutes: 1)),
          ),
          currentPositionLoader: (settings) async {
            freshPositionCalls += 1;
            return _position(timestamp: now);
          },
          currentTimeProvider: () => now,
        );

        final location = await service.getCurrentLocation();

        expect(location.latitude, 37.5665);
        expect(location.longitude, 126.9780);
        expect(freshPositionCalls, 0);
      },
    );

    test(
      'requests and returns a fresh position when the cache is null',
      () async {
        geolocator.LocationSettings? requestedSettings;
        final service = GeolocatorCurrentLocationService(
          lastKnownPositionLoader: () async => null,
          currentPositionLoader: (settings) async {
            requestedSettings = settings;
            return _position(
              latitude: 35.1796,
              longitude: 129.0756,
              timestamp: now,
            );
          },
          currentTimeProvider: () => now,
        );

        final location = await service.getCurrentLocation();

        expect(location.latitude, 35.1796);
        expect(location.longitude, 129.0756);
        expect(requestedSettings?.accuracy, geolocator.LocationAccuracy.high);
        expect(requestedSettings?.timeLimit, const Duration(seconds: 10));
      },
    );

    test('replaces a stale cache with a fresh position', () async {
      var freshPositionCalls = 0;
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () async => _position(
          latitude: 0,
          longitude: 0,
          timestamp: now.subtract(const Duration(minutes: 3)),
        ),
        currentPositionLoader: (settings) async {
          freshPositionCalls += 1;
          return _position(
            latitude: 33.4996,
            longitude: 126.5312,
            timestamp: now,
          );
        },
        currentTimeProvider: () => now,
      );

      final location = await service.getCurrentLocation();

      expect(location.latitude, 33.4996);
      expect(location.longitude, 126.5312);
      expect(freshPositionCalls, 1);
    });

    test('propagates a fresh position failure', () async {
      final failure = StateError('fresh position failed');
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () async => null,
        currentPositionLoader: (settings) => Future.error(failure),
        currentTimeProvider: () => now,
      );

      await expectLater(service.getCurrentLocation(), throwsA(same(failure)));
    });

    test(
      'times out a fresh position request instead of waiting forever',
      () async {
        final pendingPosition = Completer<geolocator.Position>();
        final service = GeolocatorCurrentLocationService(
          lastKnownPositionLoader: () async => null,
          currentPositionLoader: (settings) => pendingPosition.future,
          currentTimeProvider: () => now,
          freshLocationTimeout: const Duration(milliseconds: 20),
        );

        await expectLater(
          service.getCurrentLocation(),
          throwsA(isA<TimeoutException>()),
        );
      },
    );
  });
}

geolocator.Position _position({
  double latitude = 37.0,
  double longitude = 127.0,
  required DateTime timestamp,
}) {
  return geolocator.Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
