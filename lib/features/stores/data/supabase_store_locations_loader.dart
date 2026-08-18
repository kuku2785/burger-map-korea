import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/store_location.dart';

const supabaseStoreSelectColumns =
    'id,name,address,latitude,longitude,burger_style,verification_status';
const supabasePublicVerificationStatus = 'verified';
const supabasePublicIsActive = true;
const supabaseStoreOrderColumn = 'name';

typedef SupabaseClientInitializer =
    Future<SupabaseClient> Function({
      required String url,
      required String publishableKey,
    });
typedef SupabaseStoreRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(SupabaseClient client);
typedef SupabaseDiagnosticLogger = void Function(String message);

enum SupabaseStoreLoadStage { initialization, select, mapping, unknown }

class SupabaseStoreLoadException implements Exception {
  const SupabaseStoreLoadException({
    this.stage = SupabaseStoreLoadStage.unknown,
    this.diagnosticCode = 'store_load_failed',
  });

  final SupabaseStoreLoadStage stage;
  final String diagnosticCode;

  @override
  String toString() => '공개 매장 정보를 불러오지 못했습니다.';
}

class SupabaseStoreLocationsLoader {
  SupabaseStoreLocationsLoader({
    required this.url,
    required this.publishableKey,
    SupabaseClientInitializer? initializer,
    SupabaseStoreRowsFetcher? rowsFetcher,
    this.enableDebugDiagnostics = false,
    SupabaseDiagnosticLogger? diagnosticLogger,
  }) : _initializer = initializer ?? initializeSupabaseClient,
       _rowsFetcher = rowsFetcher ?? fetchPublicSupabaseStoreRows,
       _diagnosticLogger = diagnosticLogger ?? _defaultDiagnosticLogger;

  final String url;
  final String publishableKey;
  final SupabaseClientInitializer _initializer;
  final SupabaseStoreRowsFetcher _rowsFetcher;
  final bool enableDebugDiagnostics;
  final SupabaseDiagnosticLogger _diagnosticLogger;

  SupabaseClient? _client;

  Future<List<StoreLocation>> load() async {
    late final SupabaseClient client;
    try {
      client = _client ??= await _initializer(
        url: url.trim(),
        publishableKey: publishableKey.trim(),
      );
    } on Object catch (error) {
      throw _safeFailure(SupabaseStoreLoadStage.initialization, error);
    }

    late final List<Map<String, dynamic>> rows;
    try {
      rows = await _rowsFetcher(client);
    } on Object catch (error) {
      throw _safeFailure(SupabaseStoreLoadStage.select, error);
    }

    try {
      return mapSupabaseStoreRows(rows);
    } on Object catch (error) {
      throw _safeFailure(SupabaseStoreLoadStage.mapping, error);
    }
  }

  SupabaseStoreLoadException _safeFailure(
    SupabaseStoreLoadStage stage,
    Object error,
  ) {
    final code = _safeDiagnosticCode(stage, error);
    if (enableDebugDiagnostics && kDebugMode) {
      _diagnosticLogger(
        '[SupabaseStoreLoader] stage=${stage.name} '
        'type=${_safeTypeName(error)} code=$code',
      );
    }
    return SupabaseStoreLoadException(stage: stage, diagnosticCode: code);
  }
}

Future<SupabaseClient> initializeSupabaseClient({
  required String url,
  required String publishableKey,
}) async {
  final supabase = await Supabase.initialize(
    url: url.trim(),
    publishableKey: publishableKey.trim(),
    debug: false,
  );
  return supabase.client;
}

void _defaultDiagnosticLogger(String message) {
  debugPrint(message);
}

String _safeTypeName(Object error) {
  final typeName = error.runtimeType.toString();
  return RegExp(r'^[A-Za-z0-9_]{1,80}$').hasMatch(typeName)
      ? typeName
      : 'UnknownException';
}

String _safeDiagnosticCode(SupabaseStoreLoadStage stage, Object error) {
  if (error is PostgrestException) {
    final code = error.code;
    if (code != null && RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(code)) {
      return code;
    }
    return 'postgrest_error';
  }
  if (error is TimeoutException) {
    return 'timeout';
  }
  if (error is SocketException) {
    return 'network_io';
  }
  if (error is FormatException) {
    return 'invalid_response';
  }
  if (error is ArgumentError) {
    return 'invalid_configuration';
  }

  return switch (stage) {
    SupabaseStoreLoadStage.initialization => 'client_initialization_failed',
    SupabaseStoreLoadStage.select => 'store_select_failed',
    SupabaseStoreLoadStage.mapping => 'store_mapping_failed',
    SupabaseStoreLoadStage.unknown => 'store_load_failed',
  };
}

Future<List<Map<String, dynamic>>> fetchPublicSupabaseStoreRows(
  SupabaseClient client,
) async {
  final response = await client
      .from('stores')
      .select(supabaseStoreSelectColumns)
      .eq('verification_status', supabasePublicVerificationStatus)
      .eq('is_active', supabasePublicIsActive)
      .order(supabaseStoreOrderColumn, ascending: true);

  return response
      .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);
}

List<StoreLocation> mapSupabaseStoreRows(List<Map<String, dynamic>> rows) {
  final stores = rows.map(_mapSupabaseStoreRow).toList(growable: false);
  return List.unmodifiable(stores);
}

StoreLocation _mapSupabaseStoreRow(Map<String, dynamic> row) {
  final id = row['id']?.toString().trim() ?? '';
  final name = row['name'];
  final address = row['address'];
  final latitude = row['latitude'];
  final longitude = row['longitude'];
  final burgerStyleValue = row['burger_style'];
  final verificationStatus = row['verification_status'];

  if (id.isEmpty ||
      name is! String ||
      name.trim().isEmpty ||
      address is! String ||
      address.trim().isEmpty ||
      latitude is! num ||
      longitude is! num ||
      verificationStatus != supabasePublicVerificationStatus) {
    throw const FormatException('공개 매장 데이터 형식이 올바르지 않습니다.');
  }

  final burgerStyle = burgerStyleValue is String ? burgerStyleValue.trim() : '';

  return StoreLocation(
    id: id,
    name: name.trim(),
    latitude: latitude.toDouble(),
    longitude: longitude.toDouble(),
    address: address.trim(),
    burgerStyle: burgerStyle.isEmpty ? '미분류' : burgerStyle,
    verificationStatus: verificationStatus as String,
  );
}
