class StoreLocation {
  StoreLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.burgerStyle,
    this.verificationStatus,
  }) {
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'Latitude must be between -90 and 90.',
      );
    }

    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'Longitude must be between -180 and 180.',
      );
    }
  }

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String address;
  final String burgerStyle;
  final String? verificationStatus;
}
