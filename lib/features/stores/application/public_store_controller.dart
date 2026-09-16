import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/supabase_store_locations_loader.dart';
import '../domain/store_location.dart';

const defaultPublicStoreRefreshInterval = Duration(minutes: 5);

typedef PublicStoreLoader = Future<List<StoreLocation>> Function();
typedef PublicStoreClock = DateTime Function();
typedef PublicStoreRefreshScheduler =
    PublicStoreRefreshTask Function(Duration delay, void Function() callback);

abstract interface class PublicStoreRefreshTask {
  bool get isActive;

  void cancel();
}

enum PublicStoreLoadState { initialLoading, refreshing, ready, empty, error }

class PublicStoreController extends ChangeNotifier {
  PublicStoreController(
    this._loader, {
    this.requestTimeout = defaultSupabaseStoreLoadTimeout,
    this.refreshInterval = defaultPublicStoreRefreshInterval,
    PublicStoreClock? clock,
    PublicStoreRefreshScheduler? scheduler,
  }) : _clock = clock ?? DateTime.now,
       _scheduler = scheduler ?? _scheduleWithTimer;

  final PublicStoreLoader _loader;
  final Duration requestTimeout;
  final Duration refreshInterval;
  final PublicStoreClock _clock;
  final PublicStoreRefreshScheduler _scheduler;

  PublicStoreLoadState _loadState = PublicStoreLoadState.initialLoading;
  List<StoreLocation>? _stores;
  Map<String, StoreLocation> _storesById = const <String, StoreLocation>{};
  Object? _error;
  DateTime? _lastSuccessfulLoadAt;
  Future<void>? _inFlight;
  PublicStoreRefreshTask? _refreshTask;
  int _requestId = 0;
  int _scheduleId = 0;
  bool _hasSuccessfulLoad = false;
  bool _isForeground = true;
  bool _disposed = false;

  PublicStoreLoadState get loadState => _loadState;
  List<StoreLocation>? get stores => _stores;
  Object? get error => _error;
  DateTime? get lastSuccessfulLoadAt => _lastSuccessfulLoadAt;
  bool get isLoading => _inFlight != null;
  bool get hasSuccessfulLoad => _hasSuccessfulLoad;
  Set<String> get storeIds => Set<String>.unmodifiable(_storesById.keys);

  StoreLocation? storeById(String id) => _storesById[id];

  Future<void> initialize() {
    if (_disposed || _hasSuccessfulLoad) {
      return Future<void>.value();
    }
    return _startLoad();
  }

  Future<void> refresh() {
    if (_disposed) {
      return Future<void>.value();
    }
    return _startLoad();
  }

  void enterBackground() {
    if (_disposed || !_isForeground) {
      return;
    }
    _isForeground = false;
    _cancelScheduledRefresh();
  }

  Future<void> enterForeground() {
    if (_disposed || _isForeground) {
      return Future<void>.value();
    }
    _isForeground = true;
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight.whenComplete(() {
        if (!_disposed &&
            _isForeground &&
            (_loadState == PublicStoreLoadState.ready ||
                _loadState == PublicStoreLoadState.empty)) {
          _scheduleRefresh();
        }
      });
    }
    if (!_hasSuccessfulLoad) {
      return Future<void>.value();
    }

    final lastSuccessfulLoadAt = _lastSuccessfulLoadAt;
    if (lastSuccessfulLoadAt == null ||
        !_clock().isBefore(lastSuccessfulLoadAt.add(refreshInterval))) {
      return _startLoad();
    }
    _scheduleRefresh();
    return Future<void>.value();
  }

  Future<void> _startLoad() {
    final existing = _inFlight;
    if (existing != null) {
      return existing;
    }

    _cancelScheduledRefresh();
    final requestId = ++_requestId;
    _loadState = _hasSuccessfulLoad
        ? PublicStoreLoadState.refreshing
        : PublicStoreLoadState.initialLoading;
    _stores = null;
    _storesById = const <String, StoreLocation>{};
    _error = null;
    notifyListeners();

    final attempt = _runLoad(requestId);
    _inFlight = attempt;
    unawaited(
      attempt.whenComplete(() {
        if (identical(_inFlight, attempt)) {
          _inFlight = null;
        }
      }),
    );
    return attempt;
  }

  Future<void> _runLoad(int requestId) async {
    try {
      final stores = await _loader().timeout(
        requestTimeout,
        onTimeout: () => throw TimeoutException(
          'Public store load deadline exceeded',
          requestTimeout,
        ),
      );
      if (!_canApply(requestId)) {
        return;
      }

      final snapshot = List<StoreLocation>.unmodifiable(stores);
      _stores = snapshot;
      _storesById = Map<String, StoreLocation>.unmodifiable({
        for (final store in snapshot) store.id: store,
      });
      _loadState = snapshot.isEmpty
          ? PublicStoreLoadState.empty
          : PublicStoreLoadState.ready;
      _error = null;
      _hasSuccessfulLoad = true;
      _lastSuccessfulLoadAt = _clock();
      notifyListeners();
      _scheduleRefresh();
    } on Object catch (error) {
      if (!_canApply(requestId)) {
        return;
      }
      _stores = null;
      _storesById = const <String, StoreLocation>{};
      _loadState = PublicStoreLoadState.error;
      _error = error;
      notifyListeners();
    }
  }

  bool _canApply(int requestId) => !_disposed && requestId == _requestId;

  void _scheduleRefresh() {
    _cancelScheduledRefresh();
    if (_disposed || !_isForeground || !_hasSuccessfulLoad) {
      return;
    }

    final lastSuccessfulLoadAt = _lastSuccessfulLoadAt;
    if (lastSuccessfulLoadAt == null) {
      return;
    }
    final validUntil = lastSuccessfulLoadAt.add(refreshInterval);
    final remaining = validUntil.difference(_clock());
    final scheduleId = _scheduleId;
    _refreshTask = _scheduler(
      remaining.isNegative ? Duration.zero : remaining,
      () {
        if (_disposed || !_isForeground || scheduleId != _scheduleId) {
          return;
        }
        _refreshTask = null;
        unawaited(_startLoad());
      },
    );
  }

  void _cancelScheduledRefresh() {
    _scheduleId += 1;
    _refreshTask?.cancel();
    _refreshTask = null;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _requestId += 1;
    _cancelScheduledRefresh();
    super.dispose();
  }
}

PublicStoreRefreshTask _scheduleWithTimer(
  Duration delay,
  void Function() callback,
) {
  return _TimerRefreshTask(Timer(delay, callback));
}

class _TimerRefreshTask implements PublicStoreRefreshTask {
  _TimerRefreshTask(this._timer);

  final Timer _timer;

  @override
  bool get isActive => _timer.isActive;

  @override
  void cancel() => _timer.cancel();
}
