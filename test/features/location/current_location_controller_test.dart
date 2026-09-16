import 'dart:async';

import 'package:burger_map_korea/features/location/application/current_location_controller.dart';
import 'package:burger_map_korea/features/location/domain/current_location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 9);
  CurrentLocation valid() => CurrentLocation(
    latitude: 37,
    longitude: 127,
    capturedAt: now,
    accuracyMeters: 5,
  );

  testWidgets('deadline covers service check and retry ignores late response', (
    tester,
  ) async {
    final pending = Completer<bool>();
    final service = _Service(valid)..enabled = () => pending.future;
    final controller = CurrentLocationController(service, clock: () => now);
    final first = controller.request();
    expect(identical(first, controller.request()), isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(await first, isNull);
    expect(controller.failure, CurrentLocationFailure.unavailable);
    service.enabled = () async => true;
    await controller.request();
    expect(controller.location, isNotNull);
    pending.complete(true);
    await tester.pump();
    expect(service.lookups, 1);
    expect(controller.location, isNotNull);
    controller.dispose();
  });

  testWidgets('background invalidates late success and foreground can retry', (
    tester,
  ) async {
    final pending = Completer<CurrentLocation>();
    final service = _Service(valid)..lookup = () => pending.future;
    final controller = CurrentLocationController(service, clock: () => now);
    final first = controller.request();
    await tester.pump();
    controller.enterBackground();
    controller.enterForeground();
    service.lookup = () async => valid();
    await controller.request(allowPermissionPrompt: false);
    pending.complete(valid());
    await first;
    expect(controller.location, isNotNull);
    expect(controller.loading, isFalse);
    controller.dispose();
  });

  testWidgets('expiry notifies at boundary without automatic requests', (
    tester,
  ) async {
    var clock = now;
    final service = _Service(valid);
    final controller = CurrentLocationController(service, clock: () => clock);
    await controller.request();
    var changes = 0;
    controller.addListener(() => changes++);
    clock = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    expect(controller.location, isNull);
    expect(changes, 1);
    expect(service.lookups, 1);
    controller.dispose();
  });

  testWidgets('dispose handles late errors without notification', (
    tester,
  ) async {
    final pending = Completer<CurrentLocation>();
    final service = _Service(valid)..lookup = () => pending.future;
    final controller = CurrentLocationController(service, clock: () => now);
    final request = controller.request();
    await tester.pump();
    controller.dispose();
    pending.completeError(StateError('synthetic'));
    expect(await request, isNull);
    expect(tester.takeException(), isNull);
  });

  test('unknown timestamp and invalid coordinates cannot be fresh', () {
    expect(
      const CurrentLocation(
        latitude: 37,
        longitude: 127,
      ).isFreshAt(now, const Duration(minutes: 2)),
      isFalse,
    );
    expect(
      CurrentLocation(
        latitude: double.nan,
        longitude: 127,
        capturedAt: now,
      ).isFreshAt(now, const Duration(minutes: 2)),
      isFalse,
    );
  });

  testWidgets('dispose releases a stalled attempt without waiting for timeout', (
    tester,
  ) async {
    final pending = Completer<CurrentLocation>();
    final service = _Service(valid)..lookup = () => pending.future;
    final controller = CurrentLocationController(service, clock: () => now);
    final request = controller.request();
    await tester.pump();
    controller.dispose();
    expect(await request, isNull);
    // The deadline timer has been released; the native future may still finish.
    pending.completeError(StateError('late native failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('one deadline includes service permission prompt and position', (
    tester,
  ) async {
    final permission = Completer<LocationPermissionStatus>();
    final prompt = Completer<LocationPermissionStatus>();
    final position = Completer<CurrentLocation>();
    final service = _Service(valid);
    service.permission = () => permission.future;
    service.prompt = () => prompt.future;
    service.lookup = () => position.future;
    final controller = CurrentLocationController(service, clock: () => now);
    final request = controller.request();
    await tester.pump(const Duration(seconds: 4));
    permission.complete(LocationPermissionStatus.denied);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    prompt.complete(LocationPermissionStatus.whileInUse);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(await request, isNull);
    expect(controller.loading, isFalse);
    position.completeError(StateError('late provider failure'));
    await tester.pump();
    expect(controller.location, isNull);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('permission timeout cannot open a late prompt', (tester) async {
    final permission = Completer<LocationPermissionStatus>();
    var prompts = 0;
    final service = _Service(valid);
    service.permission = () => permission.future;
    service.prompt = () async {
      prompts++;
      return LocationPermissionStatus.whileInUse;
    };
    final controller = CurrentLocationController(service, clock: () => now);
    final request = controller.request();
    await tester.pump(const Duration(seconds: 10));
    expect(await request, isNull);
    permission.complete(LocationPermissionStatus.denied);
    await tester.pump();
    expect(prompts, 0);
    expect(service.lookups, 0);
    controller.dispose();
  });

  test('denied and forever denied never query position on resume', () async {
    for (final permission in [
      LocationPermissionStatus.denied,
      LocationPermissionStatus.deniedForever,
    ]) {
      var prompts = 0;
      final service = _Service(valid);
      service.permission = () async => permission;
      service.prompt = () async {
        prompts++;
        return LocationPermissionStatus.whileInUse;
      };
      final controller = CurrentLocationController(service, clock: () => now);
      expect(await controller.request(allowPermissionPrompt: false), isNull);
      expect(service.lookups, 0);
      expect(prompts, 0);
      expect(
        controller.failure,
        permission == LocationPermissionStatus.denied
            ? CurrentLocationFailure.denied
            : CurrentLocationFailure.deniedForever,
      );
      controller.dispose();
    }
  });

  testWidgets('background and disposal prevent expiry and repeat requests', (
    tester,
  ) async {
    final service = _Service(valid);
    final controller = CurrentLocationController(service, clock: () => now);
    await controller.request();
    controller.enterBackground();
    var notifications = 0;
    controller.addListener(() => notifications++);
    expect(await controller.request(), isNull);
    await tester.pump(const Duration(minutes: 3));
    expect(notifications, 0);
    expect(service.lookups, 1);
    controller.dispose();
    expect(await controller.request(), isNull);
  });
}

class _Service implements CurrentLocationService {
  _Service(CurrentLocation Function() value) : lookup = (() async => value());
  Future<bool> Function() enabled = () async => true;
  Future<CurrentLocation> Function() lookup;
  Future<LocationPermissionStatus> Function() permission = () async =>
      LocationPermissionStatus.whileInUse;
  Future<LocationPermissionStatus> Function() prompt = () async =>
      LocationPermissionStatus.whileInUse;
  int lookups = 0;
  @override
  Future<bool> isLocationServiceEnabled() => enabled();
  @override
  Future<LocationPermissionStatus> checkPermission() => permission();
  @override
  Future<LocationPermissionStatus> requestPermission() => prompt();
  @override
  Future<CurrentLocation> getCurrentLocation() {
    lookups++;
    return lookup();
  }

  @override
  Future<bool> openAppSettings() async => true;
}
