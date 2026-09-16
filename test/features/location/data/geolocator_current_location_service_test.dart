import 'dart:async';

import 'package:burger_map_korea/features/location/data/geolocator_current_location_service.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
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
          locationAccuracyStatusLoader: () async =>
              geolocator.LocationAccuracyStatus.precise,
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
          locationAccuracyStatusLoader: () async =>
              geolocator.LocationAccuracyStatus.precise,
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
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
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
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
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
          locationAccuracyStatusLoader: () async =>
              geolocator.LocationAccuracyStatus.precise,
          freshLocationTimeout: const Duration(milliseconds: 20),
        );

        await expectLater(
          service.getCurrentLocation(),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('cache failure falls through to a fresh position', () async {
      var freshPositionCalls = 0;
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () =>
            Future.error(StateError('synthetic cache failure')),
        currentPositionLoader: (settings) async {
          freshPositionCalls += 1;
          return _position(latitude: 37.532, longitude: 126.99, timestamp: now);
        },
        currentTimeProvider: () => now,
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
      );

      final location = await service.getCurrentLocation();

      expect(location.latitude, 37.532);
      expect(freshPositionCalls, 1);
    });

    test('cache timeout falls through to a fresh position', () async {
      final pendingCache = Completer<geolocator.Position?>();
      var freshPositionCalls = 0;
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () => pendingCache.future,
        currentPositionLoader: (settings) async {
          freshPositionCalls += 1;
          return _position(timestamp: now);
        },
        currentTimeProvider: () => now,
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
        cachedLocationTimeout: const Duration(milliseconds: 10),
        freshLocationTimeout: const Duration(milliseconds: 100),
      );

      await service.getCurrentLocation();

      expect(freshPositionCalls, 1);
    });

    test('future-dated cache is replaced by a fresh position', () async {
      var freshPositionCalls = 0;
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () async => _position(
          latitude: 0,
          longitude: 0,
          timestamp: now.add(const Duration(seconds: 1)),
        ),
        currentPositionLoader: (settings) async {
          freshPositionCalls += 1;
          return _position(latitude: 37.532, longitude: 126.99, timestamp: now);
        },
        currentTimeProvider: () => now,
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
      );

      final location = await service.getCurrentLocation();

      expect(location.latitude, 37.532);
      expect(freshPositionCalls, 1);
    });

    test('returns capture time accuracy and reduced precision', () async {
      final service = GeolocatorCurrentLocationService(
        lastKnownPositionLoader: () async => null,
        currentPositionLoader: (settings) async =>
            _position(timestamp: now, accuracy: 1350),
        currentTimeProvider: () => now,
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.reduced,
      );

      final location = await service.getCurrentLocation();

      expect(location.capturedAt, now);
      expect(location.accuracyMeters, 1350);
      expect(location.precision, CurrentLocationPrecision.approximate);
      expect(location.hasWideAccuracy, isTrue);
    });

    test(
      'approximate permission skips precise cache and requests low accuracy',
      () async {
        var cacheCalls = 0;
        geolocator.LocationSettings? requested;
        final service = GeolocatorCurrentLocationService(
          currentTimeProvider: () => now,
          locationAccuracyStatusLoader: () async =>
              geolocator.LocationAccuracyStatus.reduced,
          lastKnownPositionLoader: () async {
            cacheCalls++;
            return _position(timestamp: now);
          },
          currentPositionLoader: (settings) async {
            requested = settings;
            return _position(timestamp: now, accuracy: 1500);
          },
        );
        final value = await service.getCurrentLocation();
        expect(cacheCalls, 0);
        expect(requested!.accuracy, geolocator.LocationAccuracy.low);
        expect(value.precision, CurrentLocationPrecision.approximate);
      },
    );

    test(
      'fresh provider results with invalid coordinates or time fail',
      () async {
        for (final invalid in [
          _position(latitude: double.nan, timestamp: now),
          _position(latitude: 91, timestamp: now),
          _position(longitude: 181, timestamp: now),
          _position(timestamp: now, accuracy: -1),
          _position(timestamp: now.add(const Duration(seconds: 1))),
          _position(timestamp: now.subtract(const Duration(minutes: 2))),
        ]) {
          final service = GeolocatorCurrentLocationService(
            currentTimeProvider: () => now,
            locationAccuracyStatusLoader: () async =>
                geolocator.LocationAccuracyStatus.precise,
            lastKnownPositionLoader: () async => null,
            currentPositionLoader: (_) async => invalid,
          );
          await expectLater(service.getCurrentLocation(), throwsStateError);
        }
      },
    );

    testWidgets('invalidation during cache wait prevents fresh native query', (
      tester,
    ) async {
      final cache = Completer<geolocator.Position?>();
      var freshCalls = 0;
      final service = GeolocatorCurrentLocationService(
        currentTimeProvider: () => now,
        locationAccuracyStatusLoader: () async =>
            geolocator.LocationAccuracyStatus.precise,
        lastKnownPositionLoader: () => cache.future,
        currentPositionLoader: (_) async {
          freshCalls++;
          return _position(timestamp: now);
        },
      );
      final attempt = service.getCurrentLocation();
      final checked = expectLater(attempt, throwsStateError);
      await tester.pump();
      service.invalidateLocationAttempt();
      cache.complete(null);
      await checked;
      expect(freshCalls, 0);
    });
  });
}

geolocator.Position _position({
  double latitude = 37.0,
  double longitude = 127.0,
  double accuracy = 0,
  required DateTime timestamp,
}) {
  return geolocator.Position(
    longitude: longitude,
    latitude: latitude,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
