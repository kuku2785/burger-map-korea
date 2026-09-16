import 'dart:async';

import 'package:burger_map_korea/features/stores/application/public_store_controller.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late _FakeRefreshScheduler scheduler;

  setUp(() {
    now = DateTime.utc(2026, 9, 7, 12);
    scheduler = _FakeRefreshScheduler();
  });

  StoreLocation store(String id, {String? name}) {
    return StoreLocation(
      id: id,
      name: name ?? 'Store $id',
      address: 'Yongsan $id',
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: 'classic',
      verificationStatus: 'verified',
    );
  }

  PublicStoreController controller(PublicStoreLoader loader) {
    return PublicStoreController(
      loader,
      requestTimeout: const Duration(seconds: 1),
      refreshInterval: const Duration(minutes: 5),
      clock: () => now,
      scheduler: scheduler.schedule,
    );
  }

  test(
    'refresh hides the old snapshot and commits only the new snapshot',
    () async {
      final refresh = Completer<List<StoreLocation>>();
      var calls = 0;
      final subject = controller(() {
        calls += 1;
        return calls == 1 ? Future.value([store('a')]) : refresh.future;
      });
      addTearDown(subject.dispose);

      await subject.initialize();
      expect(subject.loadState, PublicStoreLoadState.ready);
      expect(subject.storeById('a')?.name, 'Store a');

      final firstRefresh = subject.refresh();
      final duplicateRefresh = subject.refresh();
      expect(calls, 2);
      expect(subject.loadState, PublicStoreLoadState.refreshing);
      expect(subject.stores, isNull);
      expect(subject.storeIds, isEmpty);

      refresh.complete([store('a', name: 'Updated A'), store('b')]);
      await Future.wait([firstRefresh, duplicateRefresh]);
      expect(subject.loadState, PublicStoreLoadState.ready);
      expect(subject.storeById('a')?.name, 'Updated A');
      expect(subject.storeIds, {'a', 'b'});
    },
  );

  test('an empty snapshot can be refreshed into a normal snapshot', () async {
    var calls = 0;
    final subject = controller(() async {
      calls += 1;
      return calls == 1 ? const [] : [store('a')];
    });
    addTearDown(subject.dispose);

    await subject.initialize();
    expect(subject.loadState, PublicStoreLoadState.empty);
    await subject.refresh();
    expect(subject.loadState, PublicStoreLoadState.ready);
    expect(subject.storeIds, {'a'});
  });

  test(
    'a failed refresh never restores stale data and manual retry recovers',
    () async {
      var calls = 0;
      final subject = controller(() async {
        calls += 1;
        if (calls == 1) {
          return [store('old')];
        }
        if (calls == 2) {
          throw StateError('offline');
        }
        return [store('new')];
      });
      addTearDown(subject.dispose);

      await subject.initialize();
      await subject.refresh();
      expect(subject.loadState, PublicStoreLoadState.error);
      expect(subject.stores, isNull);
      expect(subject.storeIds, isEmpty);
      expect(scheduler.activeTasks, isEmpty);

      await subject.refresh();
      expect(subject.loadState, PublicStoreLoadState.ready);
      expect(subject.storeIds, {'new'});
    },
  );

  test('expiry refreshes once, while background cancels scheduling', () async {
    final secondLoad = Completer<List<StoreLocation>>();
    var calls = 0;
    final subject = controller(() {
      calls += 1;
      return calls == 1 ? Future.value([store('a')]) : secondLoad.future;
    });
    addTearDown(subject.dispose);

    await subject.initialize();
    expect(scheduler.activeTasks, hasLength(1));
    subject.enterBackground();
    expect(scheduler.activeTasks, isEmpty);
    scheduler.tasks.single.fireEvenIfCancelled();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);

    now = now.add(const Duration(minutes: 5));
    final resumed = subject.enterForeground();
    expect(calls, 2);
    expect(subject.loadState, PublicStoreLoadState.refreshing);
    secondLoad.complete([store('b')]);
    await resumed;
    expect(subject.storeIds, {'b'});
  });

  test('a foreground expiry callback does not start duplicate work', () async {
    final secondLoad = Completer<List<StoreLocation>>();
    var calls = 0;
    final subject = controller(() {
      calls += 1;
      return calls == 1 ? Future.value([store('a')]) : secondLoad.future;
    });
    addTearDown(subject.dispose);

    await subject.initialize();
    now = now.add(const Duration(minutes: 5));
    scheduler.activeTasks.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    subject.refresh();
    scheduler.tasks.last.fireEvenIfCancelled();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);

    secondLoad.complete([store('b')]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(subject.storeIds, {'b'});
  });

  test(
    'resume at load completion still schedules the next validation',
    () async {
      final pending = Completer<List<StoreLocation>>();
      final subject = controller(() => pending.future);
      addTearDown(subject.dispose);
      Future<void>? resumed;
      subject.addListener(() {
        if (subject.loadState == PublicStoreLoadState.ready &&
            resumed == null) {
          resumed = subject.enterForeground();
        }
      });

      final load = subject.initialize();
      subject.enterBackground();
      pending.complete([store('a')]);
      await load;
      expect(resumed, isNotNull);
      await resumed!;

      expect(scheduler.activeTasks, hasLength(1));
      expect(scheduler.activeTasks.single.delay, const Duration(minutes: 5));
    },
  );

  test('late completion after dispose cannot publish state or throw', () async {
    final pending = Completer<List<StoreLocation>>();
    final subject = controller(() => pending.future);
    var notifications = 0;
    subject.addListener(() => notifications += 1);
    final load = subject.initialize();
    expect(notifications, 1);

    subject.dispose();
    pending.complete([store('a')]);
    await load;
    expect(notifications, 1);
  });
}

class _FakeRefreshScheduler {
  final List<_FakeRefreshTask> tasks = <_FakeRefreshTask>[];

  List<_FakeRefreshTask> get activeTasks =>
      tasks.where((task) => task.isActive).toList(growable: false);

  PublicStoreRefreshTask schedule(Duration delay, void Function() callback) {
    final task = _FakeRefreshTask(delay, callback);
    tasks.add(task);
    return task;
  }
}

class _FakeRefreshTask implements PublicStoreRefreshTask {
  _FakeRefreshTask(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  void cancel() {
    _isActive = false;
  }

  void fire() {
    if (!_isActive) {
      return;
    }
    fireEvenIfCancelled();
  }

  void fireEvenIfCancelled() {
    _isActive = false;
    _callback();
  }
}
