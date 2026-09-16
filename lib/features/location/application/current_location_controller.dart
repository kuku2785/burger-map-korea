import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/current_location_service.dart';

enum CurrentLocationFailure {
  serviceDisabled,
  denied,
  deniedForever,
  unavailable,
}

/// Owns the foreground location attempt and its short-lived memory value.
/// Invalidating an attempt does not imply native request cancellation.
class CurrentLocationController extends ChangeNotifier {
  CurrentLocationController(
    this.service, {
    this.requestTimeout = const Duration(seconds: 10),
    this.maximumAge = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CurrentLocationService service;
  final Duration requestTimeout;
  final Duration maximumAge;
  final DateTime Function() _clock;
  CurrentLocation? _location;
  CurrentLocationFailure? failure;
  bool loading = false;
  bool _foreground = true;
  bool _disposed = false;
  int _generation = 0;
  Timer? _expiry;
  Future<CurrentLocation?>? _pending;
  Completer<CurrentLocation?>? _abortAttempt;

  CurrentLocation? get location {
    final value = _location;
    return value != null && value.isFreshAt(_clock(), maximumAge)
        ? value
        : null;
  }

  bool _active(int generation) =>
      !_disposed && _foreground && generation == _generation;

  Future<CurrentLocation?> request({bool allowPermissionPrompt = true}) {
    if (_disposed || !_foreground) return Future.value();
    final pending = _pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    loading = true;
    failure = null;
    _expiry?.cancel();
    _location = null;
    // Store the future before notifying listeners so reentrant requests coalesce.
    final completer = Completer<CurrentLocation?>();
    final abort = Completer<CurrentLocation?>();
    _abortAttempt = abort;
    _pending = completer.future;
    notifyListeners();
    unawaited(
      _run(
        generation,
        allowPermissionPrompt,
        abort.future,
      ).then(completer.complete),
    );
    return completer.future;
  }

  Future<CurrentLocation?> _run(
    int generation,
    bool prompt,
    Future<CurrentLocation?> aborted,
  ) async {
    CurrentLocation? result;
    try {
      result = await Future.any([
        _resolve(generation, prompt),
        aborted,
      ]).timeout(requestTimeout);
      if (!_active(generation)) return null;
      if (result == null || !result.isFreshAt(_clock(), maximumAge)) {
        throw StateError('Invalid location result');
      }
      _location = result;
      final remaining = result.capturedAt!.add(maximumAge).difference(_clock());
      _expiry = Timer(remaining, () {
        if (!_active(generation)) return;
        _location = null;
        notifyListeners();
      });
    } on Object catch (error) {
      if (!_active(generation)) return null;
      _invalidateService();
      failure = error is CurrentLocationFailure
          ? error
          : CurrentLocationFailure.unavailable;
      result = null;
      _location = null;
    } finally {
      if (_active(generation)) {
        // loading=false also prevents a timed-out continuation advancing.
        loading = false;
        _pending = null;
        _abortAttempt = null;
        notifyListeners();
      }
    }
    return result;
  }

  Future<CurrentLocation?> _resolve(int generation, bool prompt) async {
    if (!_active(generation) || !loading) return null;
    final enabled = await service.isLocationServiceEnabled();
    if (!_active(generation) || !loading) return null;
    if (!enabled) throw CurrentLocationFailure.serviceDisabled;
    var permission = await service.checkPermission();
    if (!_active(generation) || !loading) return null;
    if (permission == LocationPermissionStatus.denied && prompt) {
      permission = await service.requestPermission();
      if (!_active(generation) || !loading) return null;
    }
    if (permission == LocationPermissionStatus.deniedForever) {
      throw CurrentLocationFailure.deniedForever;
    }
    if (permission != LocationPermissionStatus.whileInUse &&
        permission != LocationPermissionStatus.always) {
      throw CurrentLocationFailure.denied;
    }
    final value = await service.getCurrentLocation();
    return _active(generation) && loading ? value : null;
  }

  void enterBackground() {
    if (_disposed || !_foreground) return;
    _foreground = false;
    _invalidate();
    notifyListeners();
  }

  void enterForeground() {
    if (_disposed) return;
    _foreground = true;
  }

  void _invalidate() {
    ++_generation;
    _abortAttempt?.complete(null);
    _abortAttempt = null;
    _invalidateService();
    _expiry?.cancel();
    _location = null;
    loading = false;
    _pending = null;
    failure = null;
  }

  void _invalidateService() {
    final target = service;
    if (target is CurrentLocationAttemptInvalidator) {
      (target as CurrentLocationAttemptInvalidator).invalidateLocationAttempt();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    super.dispose();
  }
}
