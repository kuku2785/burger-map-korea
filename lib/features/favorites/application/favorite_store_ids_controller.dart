import 'package:flutter/foundation.dart';

import '../domain/favorite_store_ids_store.dart';

enum FavoriteStoreIdsLoadState { loading, ready, loadError }

class FavoriteStoreIdsController extends ChangeNotifier {
  FavoriteStoreIdsController(this._store);

  final FavoriteStoreIdsStore _store;

  Set<String> _storeIds = const <String>{};
  FavoriteStoreIdsLoadState _loadState = FavoriteStoreIdsLoadState.loading;
  Future<void>? _loadFuture;
  Future<void> _saveTail = Future<void>.value();
  final Set<String> _savingStoreIds = <String>{};
  final Map<String, bool> _failedSaveValues = <String, bool>{};
  bool _isDisposed = false;

  Set<String> get storeIds => _storeIds;
  FavoriteStoreIdsLoadState get loadState => _loadState;
  bool get isReady =>
      !_isDisposed && _loadState == FavoriteStoreIdsLoadState.ready;
  bool isSaving(String storeId) => _savingStoreIds.contains(storeId);
  bool get isSavingAny => _savingStoreIds.isNotEmpty;
  Set<String> get failedStoreIds =>
      Set<String>.unmodifiable(_failedSaveValues.keys);
  bool get hasSaveErrors => _failedSaveValues.isNotEmpty;

  Future<void> initialize() {
    if (_isDisposed || isReady) {
      return Future<void>.value();
    }
    return _loadFuture ?? _startLoad();
  }

  Future<void> retry() {
    return initialize();
  }

  Future<void> _startLoad() {
    late final Future<void> attempt;
    attempt = _load().whenComplete(() {
      if (identical(_loadFuture, attempt)) {
        _loadFuture = null;
      }
    });
    _loadFuture = attempt;
    return attempt;
  }

  Future<void> _load() async {
    _loadState = FavoriteStoreIdsLoadState.loading;
    _notifyListeners();
    try {
      final loadedStoreIds = await _store.load();
      if (_isDisposed) {
        return;
      }
      _storeIds = Set<String>.unmodifiable(loadedStoreIds);
      _loadState = FavoriteStoreIdsLoadState.ready;
    } on Object {
      if (_isDisposed) {
        return;
      }
      _loadState = FavoriteStoreIdsLoadState.loadError;
    }
    _notifyListeners();
  }

  Future<void> setFavorite(String storeId, bool isFavorite) {
    if (!isReady) {
      return Future<void>.error(
        StateError('Favorites are not ready to be saved.'),
      );
    }

    return _enqueueSave(storeId, isFavorite);
  }

  Future<void> retryFailedSaves() async {
    if (!isReady || _failedSaveValues.isEmpty) {
      return;
    }

    final failedSaves = Map<String, bool>.of(_failedSaveValues);
    final retries = <Future<void>>[];
    for (final MapEntry(key: storeId, value: isFavorite)
        in failedSaves.entries) {
      retries.add(
        _enqueueSave(
          storeId,
          isFavorite,
          retryExpectedValue: isFavorite,
        ).catchError((Object _) {}),
      );
    }
    await Future.wait(retries);
  }

  Future<void> _enqueueSave(
    String storeId,
    bool isFavorite, {
    bool? retryExpectedValue,
  }) {
    final operation = _saveTail.then<void>((_) async {
      // Accepted writes belong to this queue, even when its UI is disposed.
      // New writes are rejected above; completing the queue preserves its data.
      if (retryExpectedValue != null &&
          _failedSaveValues[storeId] != retryExpectedValue) {
        return;
      }

      final nextStoreIds = Set<String>.of(_storeIds);
      if (isFavorite) {
        nextStoreIds.add(storeId);
      } else {
        nextStoreIds.remove(storeId);
      }
      if (setEquals(nextStoreIds, _storeIds)) {
        if (_failedSaveValues.remove(storeId) != null) {
          _notifyListeners();
        }
        return;
      }

      _savingStoreIds.add(storeId);
      _notifyListeners();
      try {
        await _store.save(nextStoreIds);
        _storeIds = Set<String>.unmodifiable(nextStoreIds);
        _failedSaveValues.remove(storeId);
      } on Object {
        _failedSaveValues[storeId] = isFavorite;
        rethrow;
      } finally {
        _savingStoreIds.remove(storeId);
        _notifyListeners();
      }
    });

    _saveTail = operation.catchError((Object _) {});
    return operation;
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
