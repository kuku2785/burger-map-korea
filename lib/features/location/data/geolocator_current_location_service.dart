import 'package:geolocator/geolocator.dart' as geolocator;

import '../domain/current_location_service.dart';

typedef LastKnownPositionLoader = Future<geolocator.Position?> Function();
typedef CurrentPositionLoader =
    Future<geolocator.Position> Function(
      geolocator.LocationSettings locationSettings,
    );
typedef CurrentTimeProvider = DateTime Function();
typedef LocationAccuracyStatusLoader =
    Future<geolocator.LocationAccuracyStatus> Function();

class GeolocatorCurrentLocationService
    implements CurrentLocationService, CurrentLocationAttemptInvalidator {
  GeolocatorCurrentLocationService({
    this.lastKnownPositionLoader = _loadLastKnownPosition,
    this.currentPositionLoader = _loadCurrentPosition,
    this.currentTimeProvider = _currentTime,
    this.locationAccuracyStatusLoader = _loadLocationAccuracyStatus,
    this.maximumCachedLocationAge = const Duration(minutes: 2),
    this.cachedLocationTimeout = const Duration(seconds: 1),
    this.locationAccuracyTimeout = const Duration(seconds: 1),
    this.freshLocationTimeout = const Duration(seconds: 10),
  });

  final LastKnownPositionLoader lastKnownPositionLoader;
  final CurrentPositionLoader currentPositionLoader;
  final CurrentTimeProvider currentTimeProvider;
  final LocationAccuracyStatusLoader locationAccuracyStatusLoader;
  final Duration maximumCachedLocationAge;
  final Duration cachedLocationTimeout;
  final Duration locationAccuracyTimeout;
  final Duration freshLocationTimeout;
  int _generation = 0;

  @override
  void invalidateLocationAttempt() {
    ++_generation;
  }

  void _checkAttempt(int generation) {
    if (generation != _generation) {
      throw StateError('Location attempt invalidated');
    }
  }

  @override
  Future<bool> isLocationServiceEnabled() {
    return geolocator.Geolocator.isLocationServiceEnabled();
  }

  @override
  Future<LocationPermissionStatus> checkPermission() async {
    return _mapPermission(await geolocator.Geolocator.checkPermission());
  }

  @override
  Future<LocationPermissionStatus> requestPermission() async {
    return _mapPermission(await geolocator.Geolocator.requestPermission());
  }

  @override
  Future<CurrentLocation> getCurrentLocation() async {
    final generation = ++_generation;
    try {
      return await _resolveCurrentLocation(
        generation,
      ).timeout(freshLocationTimeout);
    } finally {
      if (generation == _generation) ++_generation;
    }
  }

  Future<CurrentLocation> _resolveCurrentLocation(int generation) async {
    var precision = CurrentLocationPrecision.unknown;
    try {
      final status = await locationAccuracyStatusLoader().timeout(
        locationAccuracyTimeout,
      );
      precision = switch (status) {
        geolocator.LocationAccuracyStatus.reduced =>
          CurrentLocationPrecision.approximate,
        geolocator.LocationAccuracyStatus.precise =>
          CurrentLocationPrecision.precise,
        geolocator.LocationAccuracyStatus.unknown =>
          CurrentLocationPrecision.unknown,
      };
    } on Object {
      /* Unknown precision remains explicit. */
    }
    _checkAttempt(generation);
    geolocator.Position? cachedPosition;
    try {
      // A previously precise cache must not bypass an approximate-only grant.
      if (precision == CurrentLocationPrecision.precise) {
        cachedPosition = await lastKnownPositionLoader().timeout(
          cachedLocationTimeout,
        );
      }
    } on Object {
      cachedPosition = null;
    }
    _checkAttempt(generation);
    final now = currentTimeProvider().toUtc();
    if (cachedPosition != null && _isUsableCache(cachedPosition, now)) {
      return _toCurrentLocation(cachedPosition, precision);
    }

    final position = await currentPositionLoader(
      geolocator.LocationSettings(
        accuracy: precision == CurrentLocationPrecision.approximate
            ? geolocator.LocationAccuracy.low
            : geolocator.LocationAccuracy.high,
        timeLimit: freshLocationTimeout,
      ),
    );
    _checkAttempt(generation);
    final location = _toCurrentLocation(position, precision);
    if (!location.isFreshAt(currentTimeProvider(), maximumCachedLocationAge)) {
      throw StateError('Invalid location result');
    }
    return location;
  }

  bool _isUsableCache(geolocator.Position position, DateTime now) {
    return _toCurrentLocation(
      position,
      CurrentLocationPrecision.precise,
    ).isFreshAt(now, maximumCachedLocationAge);
  }

  CurrentLocation _toCurrentLocation(
    geolocator.Position position,
    CurrentLocationPrecision precision,
  ) {
    return CurrentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      capturedAt: position.timestamp,
      accuracyMeters: position.accuracy,
      precision: precision,
    );
  }

  @override
  Future<bool> openAppSettings() {
    return geolocator.Geolocator.openAppSettings();
  }
}

Future<geolocator.Position?> _loadLastKnownPosition() {
  return geolocator.Geolocator.getLastKnownPosition();
}

Future<geolocator.Position> _loadCurrentPosition(
  geolocator.LocationSettings locationSettings,
) {
  return geolocator.Geolocator.getCurrentPosition(
    locationSettings: locationSettings,
  );
}

Future<geolocator.LocationAccuracyStatus> _loadLocationAccuracyStatus() {
  return geolocator.Geolocator.getLocationAccuracy();
}

DateTime _currentTime() => DateTime.now();

LocationPermissionStatus _mapPermission(
  geolocator.LocationPermission permission,
) {
  return switch (permission) {
    geolocator.LocationPermission.denied => LocationPermissionStatus.denied,
    geolocator.LocationPermission.deniedForever =>
      LocationPermissionStatus.deniedForever,
    geolocator.LocationPermission.whileInUse =>
      LocationPermissionStatus.whileInUse,
    geolocator.LocationPermission.always => LocationPermissionStatus.always,
    geolocator.LocationPermission.unableToDetermine =>
      LocationPermissionStatus.denied,
  };
}
