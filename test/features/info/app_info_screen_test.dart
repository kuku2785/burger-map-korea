import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/features/info/presentation/app_info_screen.dart';
import 'package:burger_map_korea/features/stores/data/external_uri_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget infoApp({
    String supportUrl = '',
    String privacyPolicyUrl = '',
    String operatorName = '',
    ExternalUriLauncher externalUriLauncher =
        const AppInfoExternalUriLauncher(),
    Duration externalLaunchTimeout = const Duration(seconds: 10),
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: AppInfoScreen(
          supportUrl: supportUrl,
          privacyPolicyUrl: privacyPolicyUrl,
          operatorName: operatorName,
          externalUriLauncher: externalUriLauncher,
          externalLaunchTimeout: externalLaunchTimeout,
        ),
      ),
    );
  }

  testWidgets('explains scope, data handling, and external SDK limits', (
    tester,
  ) async {
    await tester.pumpWidget(infoApp());

    expect(find.text('용산구 우선 안내'), findsOneWidget);
    expect(find.textContaining('방문 시점의 영업을 보증하지 않습니다'), findsOneWidget);
    expect(find.textContaining('매장 식별자만 이 기기에 저장'), findsOneWidget);
    expect(find.textContaining('전경에서 사용'), findsOneWidget);
    expect(find.textContaining('좌표를 영구 저장하지 않습니다'), findsOneWidget);
    expect(find.textContaining('외부 SDK'), findsOneWidget);
    expect(find.textContaining('현재 위치 좌표는 문의에 자동으로 포함되지 않습니다'), findsOneWidget);
  });

  testWidgets('shows honest notices when configuration is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(infoApp());

    expect(find.text('운영자 정보가 아직 준비되지 않았습니다.'), findsOneWidget);
    expect(find.text('지원 경로가 아직 준비되지 않았습니다.'), findsOneWidget);
    expect(find.text('개인정보처리방침 연결이 아직 준비되지 않았습니다.'), findsOneWidget);
    expect(find.byKey(appInfoSupportLinkKey), findsNothing);
    expect(find.byKey(appInfoPrivacyPolicyLinkKey), findsNothing);
  });

  testWidgets('opens configured HTTPS policy and mail support links', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher();
    await tester.pumpWidget(
      infoApp(
        supportUrl: 'mailto:help@example.com?subject=Burger%20Map',
        privacyPolicyUrl: 'https://example.com/privacy',
        operatorName: 'Example Operator',
        externalUriLauncher: launcher,
      ),
    );

    await tester.ensureVisible(find.byKey(appInfoPrivacyPolicyLinkKey));
    await tester.tap(find.byKey(appInfoPrivacyPolicyLinkKey));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(appInfoSupportLinkKey));
    await tester.tap(find.byKey(appInfoSupportLinkKey));
    await tester.pumpAndSettle();

    expect(find.text('운영자: Example Operator'), findsOneWidget);
    expect(launcher.launchedUris, [
      Uri.parse('https://example.com/privacy'),
      Uri.parse('mailto:help@example.com?subject=Burger%20Map'),
    ]);
  });

  testWidgets('does not expose HTTP or unsupported configured links', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher();
    await tester.pumpWidget(
      infoApp(
        supportUrl: 'tel:01012345678',
        privacyPolicyUrl: 'http://example.com/privacy',
        externalUriLauncher: launcher,
      ),
    );

    expect(find.byKey(appInfoSupportLinkKey), findsNothing);
    expect(find.byKey(appInfoPrivacyPolicyLinkKey), findsNothing);
    expect(launcher.launchedUris, isEmpty);
  });

  testWidgets('rejects malformed mail support links', (tester) async {
    final launcher = _FakeExternalUriLauncher();
    const malformedMailLinks = [
      'mailto:invalid-email',
      'mailto:first@example.com,second@example.com',
      'mailto://example.com/help@example.com',
      'mailto:help @example.com',
      'mailto:help%20desk@example.com',
      'mailto:help%0Adesk@example.com',
    ];

    for (final supportUrl in malformedMailLinks) {
      await tester.pumpWidget(
        infoApp(supportUrl: supportUrl, externalUriLauncher: launcher),
      );

      expect(
        find.text('지원 경로가 아직 준비되지 않았습니다.'),
        findsOneWidget,
        reason: supportUrl,
      );
      expect(find.byKey(appInfoSupportLinkKey), findsNothing);
    }
    expect(launcher.launchedUris, isEmpty);
  });

  testWidgets('shows a safe message when external launch fails', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher(error: StateError('private'));
    await tester.pumpWidget(
      infoApp(
        supportUrl: 'https://example.com/support',
        externalUriLauncher: launcher,
      ),
    );

    await tester.ensureVisible(find.byKey(appInfoSupportLinkKey));
    await tester.tap(find.byKey(appInfoSupportLinkKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('private'), findsNothing);
    expect(find.text('지원 경로를 열 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('prevents duplicate launches while a link is opening', (
    tester,
  ) async {
    final pendingResult = Completer<bool>();
    final launcher = _FakeExternalUriLauncher(pendingResult: pendingResult);
    await tester.pumpWidget(
      infoApp(
        privacyPolicyUrl: 'https://example.com/privacy',
        externalUriLauncher: launcher,
      ),
    );

    await tester.ensureVisible(find.byKey(appInfoPrivacyPolicyLinkKey));
    await tester.tap(find.byKey(appInfoPrivacyPolicyLinkKey));
    await tester.pump();
    await tester.tap(find.byKey(appInfoPrivacyPolicyLinkKey));
    await tester.pump();

    expect(launcher.launchedUris, hasLength(1));
    pendingResult.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('times out a link that does not complete', (tester) async {
    final launcher = _FakeExternalUriLauncher(pendingResult: Completer<bool>());
    await tester.pumpWidget(
      infoApp(
        supportUrl: 'https://example.com/support',
        externalUriLauncher: launcher,
        externalLaunchTimeout: const Duration(milliseconds: 1),
      ),
    );

    await tester.ensureVisible(find.byKey(appInfoSupportLinkKey));
    await tester.tap(find.byKey(appInfoSupportLinkKey));
    await tester.pump(const Duration(milliseconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('지원 경로를 열 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('launch returning false allows a later user retry', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher(result: false);
    await tester.pumpWidget(
      infoApp(
        supportUrl: 'https://example.com/support',
        externalUriLauncher: launcher,
      ),
    );
    await tester.ensureVisible(find.byKey(appInfoSupportLinkKey));
    await tester.tap(find.byKey(appInfoSupportLinkKey));
    await tester.pumpAndSettle();
    expect(find.text('지원 경로를 열 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
    launcher.result = true;
    await tester.tap(find.byKey(appInfoSupportLinkKey));
    await tester.pumpAndSettle();
    expect(launcher.launchedUris, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late external failure after disposal does not update the screen',
    (tester) async {
      final pending = Completer<bool>();
      await tester.pumpWidget(
        infoApp(
          supportUrl: 'https://example.com/support',
          externalUriLauncher: _FakeExternalUriLauncher(pendingResult: pending),
        ),
      );
      await tester.ensureVisible(find.byKey(appInfoSupportLinkKey));
      await tester.tap(find.byKey(appInfoSupportLinkKey));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.completeError(StateError('late private failure'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('opens the Flutter open-source license page', (tester) async {
    await tester.pumpWidget(infoApp());

    await tester.scrollUntilVisible(
      find.byKey(appInfoLicensesLinkKey),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(appInfoLicensesLinkKey));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('버거맵 코리아'), findsWidgets);
  });

  testWidgets('remains scrollable at 320px width and 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      infoApp(
        supportUrl: 'mailto:help@example.com',
        privacyPolicyUrl: 'https://example.com/privacy',
        operatorName: 'Example Operator',
        textScale: 2,
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(appInfoLicensesLinkKey),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(appInfoLicensesLinkKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  _FakeExternalUriLauncher({
    this.error,
    this.pendingResult,
    this.result = true,
  });

  final Object? error;
  final Completer<bool>? pendingResult;
  bool result;
  final List<Uri> launchedUris = <Uri>[];

  @override
  Future<bool> launch(Uri uri) {
    launchedUris.add(uri);
    final launchError = error;
    if (launchError != null) {
      throw launchError;
    }
    return pendingResult?.future ?? Future<bool>.value(result);
  }
}
