import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/store_location.dart';

const yongsanStagingAssetPath = 'assets/dev/yongsan_burger_stores_staging.json';
const _expectedStagingStoreCount = 24;
const _allowedFields = {
  'id',
  'name',
  'address',
  'latitude',
  'longitude',
  'burgerStyle',
  'verificationStatus',
};

Future<List<StoreLocation>> loadYongsanStagingStoreLocations({
  AssetBundle? bundle,
}) async {
  final jsonText = await (bundle ?? rootBundle).loadString(
    yongsanStagingAssetPath,
  );
  return parseYongsanStagingStoreLocations(jsonText);
}

List<StoreLocation> parseYongsanStagingStoreLocations(String jsonText) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonText);
  } on FormatException catch (error) {
    throw FormatException('staging 매장 JSON 형식이 올바르지 않습니다.', error);
  }
  if (decoded is! List || decoded.length != _expectedStagingStoreCount) {
    throw const FormatException('staging 매장 데이터는 정확히 24개여야 합니다.');
  }

  final stores = <StoreLocation>[];
  final ids = <String>{};
  for (final item in decoded) {
    if (item is! Map<String, dynamic> ||
        item.keys.toSet().difference(_allowedFields).isNotEmpty ||
        _allowedFields.difference(item.keys.toSet()).isNotEmpty) {
      throw const FormatException('staging 매장 JSON 필드가 올바르지 않습니다.');
    }
    final id = item['id'];
    final name = item['name'];
    final address = item['address'];
    final latitude = item['latitude'];
    final longitude = item['longitude'];
    final burgerStyle = item['burgerStyle'];
    final verificationStatus = item['verificationStatus'];
    if (id is! String ||
        id.trim().isEmpty ||
        !ids.add(id) ||
        name is! String ||
        name.trim().isEmpty ||
        address is! String ||
        address.trim().isEmpty ||
        latitude is! num ||
        longitude is! num ||
        latitude == 0 ||
        longitude == 0 ||
        burgerStyle is! String ||
        burgerStyle.trim().isEmpty ||
        verificationStatus != 'pending') {
      throw const FormatException('staging 매장 값이 올바르지 않습니다.');
    }
    stores.add(
      StoreLocation(
        id: id,
        name: name,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        address: address,
        burgerStyle: burgerStyle,
        verificationStatus: verificationStatus as String,
      ),
    );
  }
  return List.unmodifiable(stores);
}
