import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AppEnvironment {
  development,
  staging,
  production;

  static AppEnvironment parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
      case 'release':
        return AppEnvironment.production;
      case 'development':
      case 'dev':
      default:
        return AppEnvironment.development;
    }
  }
}

enum StoreDataMode {
  pilot,
  staging,
  supabase;

  static StoreDataMode parse(String value) {
    switch (value.trim().toLowerCase()) {
      case 'staging':
        return StoreDataMode.staging;
      case 'supabase':
        return StoreDataMode.supabase;
      default:
        return StoreDataMode.pilot;
    }
  }
}

class RuntimePolicy {
  const RuntimePolicy({
    required this.environment,
    required this.storeDataMode,
    required this.dataModeWasOverridden,
  });

  final AppEnvironment environment;
  final StoreDataMode storeDataMode;
  final bool dataModeWasOverridden;

  bool get isDevelopment => environment == AppEnvironment.development;
}

RuntimePolicy resolveRuntimePolicy({
  required AppEnvironment requestedEnvironment,
  required StoreDataMode requestedStoreDataMode,
  required bool isReleaseMode,
}) {
  if (isReleaseMode) {
    return RuntimePolicy(
      environment: AppEnvironment.production,
      storeDataMode: StoreDataMode.supabase,
      dataModeWasOverridden:
          requestedEnvironment != AppEnvironment.production ||
          requestedStoreDataMode != StoreDataMode.supabase,
    );
  }

  if (requestedEnvironment == AppEnvironment.development) {
    return RuntimePolicy(
      environment: AppEnvironment.development,
      storeDataMode: requestedStoreDataMode,
      dataModeWasOverridden: false,
    );
  }

  return RuntimePolicy(
    environment: requestedEnvironment,
    storeDataMode: StoreDataMode.supabase,
    dataModeWasOverridden: requestedStoreDataMode != StoreDataMode.supabase,
  );
}

enum SupabaseConfigIssue {
  missingUrl('missing_supabase_url'),
  missingPublishableKey('missing_publishable_key'),
  invalidUrl('invalid_supabase_url'),
  urlHasRestPath('url_has_rest_path'),
  disallowedPrivilegedKey('disallowed_privileged_key');

  const SupabaseConfigIssue(this.code);

  final String code;
}

class SupabaseConfigValidation {
  const SupabaseConfigValidation({
    required this.url,
    required this.publishableKey,
    required this.issues,
  });

  final String url;
  final String publishableKey;
  final List<SupabaseConfigIssue> issues;

  bool get isValid => issues.isEmpty;
}

SupabaseConfigValidation validateSupabaseConfiguration({
  required String url,
  required String publishableKey,
}) {
  final normalizedUrl = url.trim();
  final normalizedKey = publishableKey.trim();
  final issues = <SupabaseConfigIssue>[];

  if (normalizedUrl.isEmpty) {
    issues.add(SupabaseConfigIssue.missingUrl);
  } else {
    final parsedUrl = Uri.tryParse(normalizedUrl);
    if (parsedUrl == null ||
        parsedUrl.scheme.toLowerCase() != 'https' ||
        parsedUrl.host.isEmpty ||
        parsedUrl.userInfo.isNotEmpty ||
        parsedUrl.hasQuery ||
        parsedUrl.hasFragment) {
      issues.add(SupabaseConfigIssue.invalidUrl);
    } else {
      final normalizedPath = parsedUrl.path.toLowerCase().replaceAll(
        RegExp(r'/+$'),
        '',
      );
      if (normalizedPath == '/rest/v1' ||
          normalizedPath.startsWith('/rest/v1/')) {
        issues.add(SupabaseConfigIssue.urlHasRestPath);
      } else if (normalizedPath.isNotEmpty) {
        issues.add(SupabaseConfigIssue.invalidUrl);
      }
    }
  }

  if (normalizedKey.isEmpty) {
    issues.add(SupabaseConfigIssue.missingPublishableKey);
  } else if (_looksLikePrivilegedSupabaseKey(normalizedKey)) {
    issues.add(SupabaseConfigIssue.disallowedPrivilegedKey);
  }

  return SupabaseConfigValidation(
    url: normalizedUrl,
    publishableKey: normalizedKey,
    issues: List.unmodifiable(issues),
  );
}

bool _looksLikePrivilegedSupabaseKey(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.startsWith('sb_secret_') ||
      normalized.contains('service_role')) {
    return true;
  }

  final segments = value.split('.');
  if (segments.length != 3) {
    return false;
  }

  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(segments[1])),
    );
    final claims = jsonDecode(payload);
    if (claims is! Map<String, dynamic>) {
      return false;
    }
    final role = claims['role']?.toString().toLowerCase();
    return role == 'service_role' || role == 'supabase_admin';
  } on Object {
    return false;
  }
}

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.googleMapsApiKey,
    this.storeDataMode = StoreDataMode.pilot,
    this.supabaseUrl = '',
    this.supabasePublishableKey = '',
    this.isReleaseMode = false,
  });

  factory AppConfig.fromDartDefines() {
    return AppConfig(
      environment: AppEnvironment.parse(
        const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
      ),
      googleMapsApiKey: const String.fromEnvironment('GOOGLE_MAPS_API_KEY'),
      storeDataMode: StoreDataMode.parse(
        const String.fromEnvironment('STORE_DATA_MODE', defaultValue: 'pilot'),
      ),
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      isReleaseMode: kReleaseMode,
    );
  }

  final AppEnvironment environment;
  final String googleMapsApiKey;
  final StoreDataMode storeDataMode;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final bool isReleaseMode;

  RuntimePolicy get runtimePolicy => resolveRuntimePolicy(
    requestedEnvironment: environment,
    requestedStoreDataMode: storeDataMode,
    isReleaseMode: isReleaseMode,
  );

  SupabaseConfigValidation get supabaseConfiguration =>
      validateSupabaseConfiguration(
        url: supabaseUrl,
        publishableKey: supabasePublishableKey,
      );

  AppEnvironment get effectiveEnvironment => runtimePolicy.environment;
  StoreDataMode get effectiveStoreDataMode => runtimePolicy.storeDataMode;
  String get normalizedSupabaseUrl => supabaseConfiguration.url;
  String get normalizedSupabasePublishableKey =>
      supabaseConfiguration.publishableKey;

  bool get hasGoogleMapsApiKey => googleMapsApiKey.trim().isNotEmpty;
  bool get hasSupabaseUrl => normalizedSupabaseUrl.isNotEmpty;
  bool get hasSupabasePublishableKey =>
      normalizedSupabasePublishableKey.isNotEmpty;
  bool get hasSupabaseConfiguration => supabaseConfiguration.isValid;
  bool get usesStagingStoreData =>
      effectiveStoreDataMode == StoreDataMode.staging;
  bool get usesSupabaseStoreData =>
      effectiveStoreDataMode == StoreDataMode.supabase;
  bool get showsDevelopmentDiagnostics =>
      runtimePolicy.isDevelopment && !isReleaseMode;

  List<String> get safeDiagnosticCodes {
    final codes = <String>[
      if (runtimePolicy.dataModeWasOverridden) 'disallowed_data_mode',
      if (usesSupabaseStoreData)
        ...supabaseConfiguration.issues.map((issue) => issue.code),
    ];
    return List.unmodifiable(codes);
  }

  String get environmentLabel {
    switch (effectiveEnvironment) {
      case AppEnvironment.development:
        return 'Development';
      case AppEnvironment.staging:
        return 'Staging';
      case AppEnvironment.production:
        return 'Production';
    }
  }
}

void logDevelopmentConfigurationDiagnostics(
  AppConfig config, {
  void Function(String message)? logger,
}) {
  if (!config.showsDevelopmentDiagnostics) {
    return;
  }
  final diagnosticLogger = logger ?? debugPrint;
  for (final code in config.safeDiagnosticCodes) {
    diagnosticLogger('[AppConfig] code=$code');
  }
}
