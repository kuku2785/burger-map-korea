class InvalidDirectionsCoordinates implements Exception {
  const InvalidDirectionsCoordinates();
}

Uri buildGoogleMapsDirectionsUri({
  required String name,
  required String address,
  required double latitude,
  required double longitude,
}) {
  final normalizedName = name.trim();
  final normalizedAddress = address.trim();
  final destination = normalizedName.isNotEmpty && normalizedAddress.isNotEmpty
      ? '$normalizedName, $normalizedAddress'
      : _coordinateDestination(latitude, longitude);

  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
  });
}

String _coordinateDestination(double latitude, double longitude) {
  if (!latitude.isFinite || latitude < -90 || latitude > 90) {
    throw const InvalidDirectionsCoordinates();
  }
  if (!longitude.isFinite || longitude < -180 || longitude > 180) {
    throw const InvalidDirectionsCoordinates();
  }

  return '${_formatCoordinate(latitude)},${_formatCoordinate(longitude)}';
}

String _formatCoordinate(double value) {
  final fixed = value.toStringAsFixed(12);
  final withoutTrailingZeros = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return withoutTrailingZeros == '-0' ? '0' : withoutTrailingZeros;
}
