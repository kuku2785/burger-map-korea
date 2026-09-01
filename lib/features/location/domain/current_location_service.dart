class CurrentLocation {
  const CurrentLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

enum LocationPermissionStatus { denied, deniedForever, whileInUse, always }

abstract interface class CurrentLocationService {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<CurrentLocation> getCurrentLocation();

  Future<bool> openAppSettings();
}
