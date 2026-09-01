import 'package:geolocator/geolocator.dart' as geolocator;

import '../domain/current_location_service.dart';

typedef LastKnownPositionLoader = Future<geolocator.Position?> Function();
typedef CurrentPositionLoader =
    Future<geolocator.Position> Function(
      geolocator.LocationSettings locationSettings,
    );
typedef CurrentTimeProvider = DateTime Function();

class GeolocatorCurrentLocationService implements CurrentLocationService {
  const GeolocatorCurrentLocationService({
    this.lastKnownPositionLoader = _loadLastKnownPosition,
    this.currentPositionLoader = _loadCurrentPosition,
    this.currentTimeProvider = _currentTime,
    this.maximumCachedLocationAge = const Duration(minutes: 2),
    this.freshLocationTimeout = const Duration(seconds: 10),
  });

  final LastKnownPositionLoader lastKnownPositionLoader;
  final CurrentPositionLoader currentPositionLoader;
  final CurrentTimeProvider currentTimeProvider;
  final Duration maximumCachedLocationAge;
  final Duration freshLocationTimeout;

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
    final cachedPosition = await lastKnownPositionLoader();
    if (cachedPosition != null &&
        currentTimeProvider().toUtc().difference(
              cachedPosition.timestamp.toUtc(),
            ) <=
            maximumCachedLocationAge) {
      return _toCurrentLocation(cachedPosition);
    }

    final position = await currentPositionLoader(
      geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.high,
        timeLimit: freshLocationTimeout,
      ),
    ).timeout(freshLocationTimeout);
    return _toCurrentLocation(position);
  }

  CurrentLocation _toCurrentLocation(geolocator.Position position) {
    return CurrentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
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
