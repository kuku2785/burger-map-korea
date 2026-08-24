import 'package:burger_map_korea/features/stores/data/external_uri_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': 'PPS, 서울 용산구 한강대로50길 24',
  });

  test('does not use fallback when a non-browser app launches', () async {
    final calls = <LaunchMode>[];
    final launcher = UrlLauncherExternalUriLauncher(
      launchOperation: (launchedUri, mode) async {
        expect(launchedUri, uri);
        calls.add(mode);
        return true;
      },
    );

    expect(await launcher.launch(uri), isTrue);
    expect(calls, [LaunchMode.externalNonBrowserApplication]);
  });

  test('uses external application fallback after primary false', () async {
    final calls = <LaunchMode>[];
    final launcher = UrlLauncherExternalUriLauncher(
      launchOperation: (launchedUri, mode) async {
        calls.add(mode);
        return mode == LaunchMode.externalApplication;
      },
    );

    expect(await launcher.launch(uri), isTrue);
    expect(calls, [
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.externalApplication,
    ]);
  });

  test('uses fallback after a primary exception', () async {
    final calls = <LaunchMode>[];
    final launcher = UrlLauncherExternalUriLauncher(
      launchOperation: (launchedUri, mode) async {
        calls.add(mode);
        if (mode == LaunchMode.externalNonBrowserApplication) {
          throw StateError('no non-browser handler');
        }
        return true;
      },
    );

    expect(await launcher.launch(uri), isTrue);
    expect(calls, [
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.externalApplication,
    ]);
  });

  test('returns false when primary and fallback both fail', () async {
    final calls = <LaunchMode>[];
    final launcher = UrlLauncherExternalUriLauncher(
      launchOperation: (launchedUri, mode) async {
        calls.add(mode);
        return false;
      },
    );

    expect(await launcher.launch(uri), isFalse);
    expect(calls, [
      LaunchMode.externalNonBrowserApplication,
      LaunchMode.externalApplication,
    ]);
  });

  test('propagates a fallback exception to the UI boundary', () async {
    final launcher = UrlLauncherExternalUriLauncher(
      launchOperation: (launchedUri, mode) async {
        if (mode == LaunchMode.externalNonBrowserApplication) {
          return false;
        }
        throw StateError('fallback failed');
      },
    );

    await expectLater(launcher.launch(uri), throwsA(isA<StateError>()));
  });
}
