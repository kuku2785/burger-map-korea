import 'package:geolocator/geolocator.dart' as geolocator;

import '../domain/current_location_service.dart';

class GeolocatorCurrentLocationService implements CurrentLocationService {
  const GeolocatorCurrentLocationService();

  static const _maximumCachedLocationAge = Duration(minutes: 2);

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
    // Android 16 emulator LocationManager cleanup can block on NMEA callbacks.
    // A recent system location avoids starting that update path.
    final position = await geolocator.Geolocator.getLastKnownPosition();
    if (position == null ||
        DateTime.now().toUtc().difference(position.timestamp.toUtc()) >
            _maximumCachedLocationAge) {
      throw StateError('No recent device location is available.');
    }
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
