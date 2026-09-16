import 'dart:math' as math;

import 'store_location.dart';

const _earthRadiusMeters = 6371000.0;
const _distanceTieToleranceMeters = 0.01;

double greatCircleDistanceMeters({
  required double fromLatitude,
  required double fromLongitude,
  required double toLatitude,
  required double toLongitude,
}) {
  final latitudeDelta = _toRadians(toLatitude - fromLatitude);
  final longitudeDelta = _toRadians(toLongitude - fromLongitude);
  final fromLatitudeRadians = _toRadians(fromLatitude);
  final toLatitudeRadians = _toRadians(toLatitude);

  final rawHaversine =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(fromLatitudeRadians) *
          math.cos(toLatitudeRadians) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  final haversine = rawHaversine.clamp(0.0, 1.0).toDouble();
  final centralAngle =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return _earthRadiusMeters * centralAngle;
}

List<StoreLocation> sortStoreLocationsByDistance(
  List<StoreLocation> stores, {
  required double fromLatitude,
  required double fromLongitude,
}) {
  final rankedStores =
      <_RankedStore>[
        for (var index = 0; index < stores.length; index += 1)
          _RankedStore(
            store: stores[index],
            originalIndex: index,
            distanceMeters: greatCircleDistanceMeters(
              fromLatitude: fromLatitude,
              fromLongitude: fromLongitude,
              toLatitude: stores[index].latitude,
              toLongitude: stores[index].longitude,
            ),
          ),
      ]..sort((first, second) {
        final distanceDelta = first.distanceMeters - second.distanceMeters;
        if (distanceDelta.abs() > _distanceTieToleranceMeters) {
          return first.distanceMeters.compareTo(second.distanceMeters);
        }
        return first.originalIndex.compareTo(second.originalIndex);
      });

  return List<StoreLocation>.unmodifiable(
    rankedStores.map((rankedStore) => rankedStore.store),
  );
}

double _toRadians(double degrees) => degrees * math.pi / 180;

class _RankedStore {
  const _RankedStore({
    required this.store,
    required this.originalIndex,
    required this.distanceMeters,
  });

  final StoreLocation store;
  final int originalIndex;
  final double distanceMeters;
}
