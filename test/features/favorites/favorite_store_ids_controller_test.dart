import 'dart:async';

import 'package:burger_map_korea/features/favorites/application/favorite_store_ids_controller.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'retry while ready does not reread or interrupt accepted writes',
    () async {
      final store = _ControlledFavoriteStore();
      final controller = FavoriteStoreIdsController(store);
      final load = controller.initialize();
      store.completeNextLoad({'existing'});
      await load;
      final save = controller.setFavorite('new', true);
      await _flushMicrotasks();
      unawaited(controller.retry());
      expect(store._loads, isEmpty);
      expect(controller.isReady, isTrue);
      store.completeNextSave();
      await save;
      expect(controller.storeIds, {'existing', 'new'});
      controller.dispose();
    },
  );

  test(
    'disposed controller refuses new loads and drains accepted saves silently',
    () async {
      final store = _ControlledFavoriteStore();
      final controller = FavoriteStoreIdsController(store);
      final load = controller.initialize();
      store.completeNextLoad({'existing'});
      await load;
      final addA = controller.setFavorite('a', true);
      final addB = controller.setFavorite('b', true);
      await _flushMicrotasks();
      controller.dispose();
      await controller.initialize();
      expect(store._loads, isEmpty);
      await expectLater(controller.setFavorite('c', true), throwsStateError);
      store.completeNextSave();
      await addA;
      await _flushMicrotasks();
      expect(store.saveCalls.last, {'existing', 'a', 'b'});
      store.completeNextSave();
      await addB;
    },
  );

  test('queued removal uses the successful preceding additions', () async {
    final store = _PersistentFavoriteStore({'existing'});
    final controller = FavoriteStoreIdsController(store);
    await controller.initialize();
    await Future.wait([
      controller.setFavorite('a', true),
      controller.setFavorite('b', true),
      controller.setFavorite('a', false),
    ]);
    expect(await store.load(), {'existing', 'b'});
    controller.dispose();
  });
  test(
    'does not save a new favorite before a delayed load preserves stored IDs',
    () async {
      final store = _ControlledFavoriteStore();
      final controller = FavoriteStoreIdsController(store);

      final load = controller.initialize();
      await expectLater(
        controller.setFavorite('b', true),
        throwsA(isA<StateError>()),
      );
      expect(store.saveCalls, isEmpty);

      store.completeNextLoad(<String>{'a'});
      await load;

      expect(controller.loadState, FavoriteStoreIdsLoadState.ready);
      expect(controller.storeIds, <String>{'a'});
    },
  );

  test(
    'retries a failed load without replacing the stored list with empty data',
    () async {
      final store = _ControlledFavoriteStore();
      final controller = FavoriteStoreIdsController(store);

      final firstLoad = controller.initialize();
      store.failNextLoad(StateError('read failed'));
      await firstLoad;
      expect(controller.loadState, FavoriteStoreIdsLoadState.loadError);
      expect(controller.storeIds, isEmpty);

      final retry = controller.retry();
      store.completeNextLoad(<String>{'a'});
      await retry;

      expect(controller.loadState, FavoriteStoreIdsLoadState.ready);
      expect(controller.storeIds, <String>{'a'});
    },
  );

  test(
    'serializes saves from the latest successful state after navigation',
    () async {
      final store = _ControlledFavoriteStore();
      final controller = FavoriteStoreIdsController(store);
      final load = controller.initialize();
      store.completeNextLoad(<String>{});
      await load;

      final addA = controller.setFavorite('a', true);
      final addB = controller.setFavorite('b', true);
      await _flushMicrotasks();
      expect(store.saveCalls, <Set<String>>[
        <String>{'a'},
      ]);

      store.completeNextSave();
      await addA;
      await _flushMicrotasks();
      expect(store.saveCalls, <Set<String>>[
        <String>{'a'},
        <String>{'a', 'b'},
      ]);

      store.completeNextSave();
      await addB;
      expect(controller.storeIds, <String>{'a', 'b'});
    },
  );

  test('a failed save remains visible across an unrelated success', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    final load = controller.initialize();
    store.completeNextLoad(<String>{});
    await load;

    final addA = controller.setFavorite('a', true);
    final addB = controller.setFavorite('b', true);
    await _flushMicrotasks();
    store.failNextSave(StateError('write failed'));
    await expectLater(addA, throwsA(isA<StateError>()));
    expect(controller.failedStoreIds, <String>{'a'});
    expect(controller.hasSaveErrors, isTrue);
    await _flushMicrotasks();
    expect(store.saveCalls.last, <String>{'b'});

    store.completeNextSave();
    await addB;
    expect(controller.storeIds, <String>{'b'});
    expect(controller.failedStoreIds, <String>{'a'});
    expect(controller.hasSaveErrors, isTrue);

    final retryA = controller.setFavorite('a', true);
    await _flushMicrotasks();
    expect(store.saveCalls.last, <String>{'a', 'b'});
    store.completeNextSave();
    await retryA;
    expect(controller.storeIds, <String>{'a', 'b'});
    expect(controller.failedStoreIds, isEmpty);
    controller.dispose();
  });

  test('retry preserves failed add and remove intents', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    final load = controller.initialize();
    store.completeNextLoad(<String>{'remove'});
    await load;

    final add = controller.setFavorite('add', true);
    await _flushMicrotasks();
    store.failNextSave(StateError('add failed'));
    await expectLater(add, throwsStateError);

    final remove = controller.setFavorite('remove', false);
    await _flushMicrotasks();
    store.failNextSave(StateError('remove failed'));
    await expectLater(remove, throwsStateError);
    expect(controller.failedStoreIds, <String>{'add', 'remove'});

    final retry = controller.retryFailedSaves();
    await _flushMicrotasks();
    expect(controller.isSavingAny, isTrue);
    expect(store.saveCalls.last, <String>{'remove', 'add'});
    store.completeNextSave();
    await _flushMicrotasks();
    expect(store.saveCalls.last, <String>{'add'});
    store.completeNextSave();
    await retry;

    expect(controller.storeIds, <String>{'add'});
    expect(store.saveCalls.last, <String>{'add'});
    expect(controller.failedStoreIds, isEmpty);
    expect(controller.hasSaveErrors, isFalse);
    expect(controller.isSavingAny, isFalse);
    controller.dispose();
  });

  test('a failed retry remains available and can recover', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    final load = controller.initialize();
    store.completeNextLoad(<String>{});
    await load;

    final add = controller.setFavorite('a', true);
    await _flushMicrotasks();
    store.failNextSave(StateError('write failed'));
    await expectLater(add, throwsStateError);

    final failedRetry = controller.retryFailedSaves();
    await _flushMicrotasks();
    store.failNextSave(StateError('retry failed'));
    await failedRetry;
    expect(controller.failedStoreIds, <String>{'a'});
    expect(controller.storeIds, isEmpty);

    final recoveredRetry = controller.retryFailedSaves();
    await _flushMicrotasks();
    store.completeNextSave();
    await recoveredRetry;
    expect(controller.storeIds, <String>{'a'});
    expect(controller.failedStoreIds, isEmpty);
    controller.dispose();
  });

  test('an explicit successful no-op supersedes a prior failure', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    final load = controller.initialize();
    store.completeNextLoad(<String>{});
    await load;

    final add = controller.setFavorite('a', true);
    await _flushMicrotasks();
    store.failNextSave(StateError('write failed'));
    await expectLater(add, throwsStateError);
    expect(controller.failedStoreIds, <String>{'a'});

    final latestChoice = controller.setFavorite('a', false);
    final obsoleteRetry = controller.retryFailedSaves();
    await Future.wait([latestChoice, obsoleteRetry]);
    expect(controller.storeIds, isEmpty);
    expect(controller.failedStoreIds, isEmpty);
    expect(store.saveCalls, hasLength(1));
    controller.dispose();
  });

  test('retry is silent after disposal and accepted retry drains', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    final load = controller.initialize();
    store.completeNextLoad(<String>{});
    await load;

    final add = controller.setFavorite('a', true);
    await _flushMicrotasks();
    store.failNextSave(StateError('write failed'));
    await expectLater(add, throwsStateError);

    var notifications = 0;
    controller.addListener(() => notifications++);
    final retry = controller.retryFailedSaves();
    await _flushMicrotasks();
    expect(store.saveCalls, hasLength(2));
    controller.dispose();
    store.completeNextSave();
    await retry;
    expect(notifications, 1);

    await controller.retryFailedSaves();
    expect(store.saveCalls, hasLength(2));
  });

  test('restores saved UUIDs when the controller is recreated', () async {
    final store = _PersistentFavoriteStore(<String>{
      '11111111-1111-4111-8111-111111111111',
    });
    final first = FavoriteStoreIdsController(store);
    await first.initialize();
    await first.setFavorite('22222222-2222-4222-8222-222222222222', true);
    first.dispose();

    final recreated = FavoriteStoreIdsController(store);
    await recreated.initialize();

    expect(recreated.storeIds, <String>{
      '11111111-1111-4111-8111-111111111111',
      '22222222-2222-4222-8222-222222222222',
    });
  });

  test('ignores delayed completion after disposal', () async {
    final store = _ControlledFavoriteStore();
    final controller = FavoriteStoreIdsController(store);
    var notifications = 0;
    controller.addListener(() => notifications++);

    final load = controller.initialize();
    controller.dispose();
    store.completeNextLoad(<String>{'a'});
    await load;

    expect(notifications, 1);
    expect(controller.storeIds, isEmpty);
  });
}

class _ControlledFavoriteStore implements FavoriteStoreIdsStore {
  final List<Completer<Set<String>>> _loads = <Completer<Set<String>>>[];
  final List<Completer<void>> _saves = <Completer<void>>[];
  final List<Set<String>> saveCalls = <Set<String>>[];

  @override
  Future<Set<String>> load() {
    final completer = Completer<Set<String>>();
    _loads.add(completer);
    return completer.future;
  }

  @override
  Future<void> save(Set<String> storeIds) {
    saveCalls.add(Set<String>.of(storeIds));
    final completer = Completer<void>();
    _saves.add(completer);
    return completer.future;
  }

  void completeNextLoad(Set<String> storeIds) {
    _loads.removeAt(0).complete(storeIds);
  }

  void failNextLoad(Object error) {
    _loads.removeAt(0).completeError(error);
  }

  void completeNextSave() {
    _saves.removeAt(0).complete();
  }

  void failNextSave(Object error) {
    _saves.removeAt(0).completeError(error);
  }
}

class _PersistentFavoriteStore implements FavoriteStoreIdsStore {
  _PersistentFavoriteStore(this._storeIds);

  Set<String> _storeIds;

  @override
  Future<Set<String>> load() async => Set<String>.of(_storeIds);

  @override
  Future<void> save(Set<String> storeIds) async {
    _storeIds = Set<String>.of(storeIds);
  }
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);
