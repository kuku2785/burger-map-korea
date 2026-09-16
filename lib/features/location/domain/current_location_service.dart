class CurrentLocation {
  const CurrentLocation({
    required this.latitude,
    required this.longitude,
    this.capturedAt,
    this.accuracyMeters = 0,
    this.precision = CurrentLocationPrecision.unknown,
  });

  final double latitude;
  final double longitude;
  final DateTime? capturedAt;
  final double accuracyMeters;
  final CurrentLocationPrecision precision;

  bool get isApproximate => precision == CurrentLocationPrecision.approximate;

  bool get hasWideAccuracy => accuracyMeters > 1000;

  bool isFreshAt(DateTime now, Duration maximumAge) {
    final capturedAt = this.capturedAt;
    if (capturedAt == null ||
        !latitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        !longitude.isFinite ||
        longitude < -180 ||
        longitude > 180 ||
        !accuracyMeters.isFinite ||
        accuracyMeters < 0) {
      return false;
    }
    final age = now.toUtc().difference(capturedAt.toUtc());
    return !age.isNegative && age < maximumAge;
  }

  CurrentLocation withCapturedAt(DateTime value) {
    return CurrentLocation(
      latitude: latitude,
      longitude: longitude,
      capturedAt: value,
      accuracyMeters: accuracyMeters,
      precision: precision,
    );
  }
}

enum CurrentLocationPrecision { approximate, precise, unknown }

enum LocationPermissionStatus { denied, deniedForever, whileInUse, always }

abstract interface class CurrentLocationService {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermissionStatus> checkPermission();

  Future<LocationPermissionStatus> requestPermission();

  Future<CurrentLocation> getCurrentLocation();

  Future<bool> openAppSettings();
}

/// Optional invalidation of follow-up work; not a native cancellation guarantee.
abstract interface class CurrentLocationAttemptInvalidator {
  void invalidateLocationAttempt();
}
