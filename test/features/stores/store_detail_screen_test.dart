import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/features/stores/data/external_uri_launcher.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  StoreLocation store({
    String id = 'internal-id-not-for-display',
    String name = 'Alpha Burger',
    String address = 'Seoul Yongsan Alpha-ro 1',
    String burgerStyle = '스매시버거',
    String? verificationStatus = 'verified',
  }) {
    return StoreLocation(
      id: id,
      name: name,
      address: address,
      latitude: 37.53,
      longitude: 126.99,
      burgerStyle: burgerStyle,
      verificationStatus: verificationStatus,
    );
  }

  Widget detailApp(
    StoreLocation store, {
    ExternalUriLauncher? externalUriLauncher,
    bool isFavorite = false,
    StoreFavoriteChanged? onFavoriteChanged,
    double textScale = 1,
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        );
      },
      home: StoreDetailScreen(
        store: store,
        externalUriLauncher:
            externalUriLauncher ?? const UrlLauncherExternalUriLauncher(),
        isFavorite: isFavorite,
        onFavoriteChanged: onFavoriteChanged,
      ),
    );
  }

  testWidgets('shows only the available public store information', (
    tester,
  ) async {
    final selectedStore = store();
    await tester.pumpWidget(detailApp(selectedStore));

    expect(find.text(selectedStore.name), findsOneWidget);
    expect(find.text(selectedStore.address), findsOneWidget);
    expect(find.text('스매시'), findsOneWidget);
    expect(find.text(selectedStore.burgerStyle), findsNothing);
    expect(find.text('검수 완료'), findsOneWidget);
    expect(find.text(selectedStore.id), findsNothing);
    expect(find.text('verified'), findsNothing);
    expect(find.textContaining('Place ID'), findsNothing);
    expect(find.textContaining('sourceType'), findsNothing);
    expect(find.textContaining('영업시간'), findsNothing);
    expect(find.textContaining('리뷰'), findsNothing);
    expect(find.textContaining('평점'), findsNothing);
  });

  test('maps verification statuses to conservative Korean labels', () {
    expect(storeVerificationStatusLabel('verified'), '검수 완료');
    expect(storeVerificationStatusLabel('pending'), '검수 중');
    expect(storeVerificationStatusLabel('needs_recheck'), '재확인 필요');
    expect(storeVerificationStatusLabel('unexpected'), '검수 상태 확인 중');
    expect(storeVerificationStatusLabel(null), '검수 상태 확인 중');
  });

  test('uses a natural label for unavailable burger style', () {
    expect(storeBurgerStyleLabel(''), '아직 분류되지 않았습니다.');
    expect(storeBurgerStyleLabel('미분류'), '아직 분류되지 않았습니다.');
    expect(storeBurgerStyleLabel('  스매시버거  '), '스매시');
  });

  testWidgets('copies the address and shows a success message', (tester) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    final selectedStore = store();
    await tester.pumpWidget(detailApp(selectedStore));

    await tester.tap(find.byKey(storeAddressCopyButtonKey));
    await tester.pump();

    expect(copiedText, selectedStore.address);
    expect(find.text('주소를 복사했습니다.'), findsOneWidget);
  });

  testWidgets('adds and removes a store favorite from the detail screen', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      detailApp(
        store(),
        onFavoriteChanged: (isFavorite) async {
          changes.add(isFavorite);
        },
      ),
    );

    expect(find.byIcon(Icons.star_border), findsOneWidget);
    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pumpAndSettle();
    expect(changes, [true]);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.text('즐겨찾기에 추가했습니다.'), findsOneWidget);

    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    expect(find.byIcon(Icons.star_border), findsOneWidget);
    expect(find.text('즐겨찾기에서 해제했습니다.'), findsOneWidget);
  });

  testWidgets(
    'launches the same named destination on the first three completed taps',
    (tester) async {
      final launcher = _FakeExternalUriLauncher();
      final selectedStore = store();
      await tester.pumpWidget(
        detailApp(selectedStore, externalUriLauncher: launcher),
      );

      expect(find.byKey(storeDirectionsButtonKey), findsOneWidget);
      for (var expectedCalls = 1; expectedCalls <= 3; expectedCalls += 1) {
        await tester.tap(find.byKey(storeDirectionsButtonKey));
        await tester.pumpAndSettle();
        expect(launcher.callCount, expectedCalls);
      }

      expect(launcher.launchedUris, hasLength(3));
      expect(
        launcher.launchedUris.map((uri) => uri.queryParameters['destination']),
        everyElement('${selectedStore.name}, ${selectedStore.address}'),
      );
      expect(find.textContaining('지도 앱을 열 수 없습니다.'), findsNothing);
    },
  );

  testWidgets('shows a general error when the launcher returns false', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher(result: false);
    await tester.pumpWidget(detailApp(store(), externalUriLauncher: launcher));

    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pumpAndSettle();

    expect(launcher.callCount, 1);
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(find.text('지도 앱을 열 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('allows another launch after a failed completed attempt', (
    tester,
  ) async {
    final launcher = _FakeExternalUriLauncher(result: false);
    await tester.pumpWidget(detailApp(store(), externalUriLauncher: launcher));

    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pumpAndSettle();

    expect(launcher.callCount, 2);
  });

  testWidgets('shows a general error when the launcher throws', (tester) async {
    final launcher = _FakeExternalUriLauncher(error: StateError('private'));
    await tester.pumpWidget(detailApp(store(), externalUriLauncher: launcher));

    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pumpAndSettle();

    expect(launcher.callCount, 1);
    expect(find.byType(StoreDetailScreen), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(find.text('지도 앱을 열 수 없습니다. 잠시 후 다시 시도해 주세요.'), findsOneWidget);
  });

  testWidgets('prevents duplicate launches while a request is in progress', (
    tester,
  ) async {
    final pendingResult = Completer<bool>();
    final launcher = _FakeExternalUriLauncher(pendingResult: pendingResult);
    await tester.pumpWidget(detailApp(store(), externalUriLauncher: launcher));

    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(storeDirectionsButtonKey));
    await tester.pump();

    expect(launcher.callCount, 1);
    pendingResult.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('handles an empty address without writing to the clipboard', (
    tester,
  ) async {
    var clipboardCalls = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardCalls += 1;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
    await tester.pumpWidget(detailApp(store(address: '')));

    await tester.tap(find.byKey(storeAddressCopyButtonKey));
    await tester.pump();

    expect(clipboardCalls, 0);
    expect(find.text('주소 정보가 없습니다.'), findsOneWidget);
    expect(find.text('복사할 주소가 없습니다.'), findsOneWidget);
  });

  testWidgets('long content is scrollable without overflowing a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      detailApp(
        store(
          name: 'A very long burger store name that must remain fully readable',
          address:
              'A very long address that should wrap across multiple lines '
              'instead of being clipped on a compact mobile screen',
          burgerStyle: '미분류',
        ),
        textScale: 2,
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeExternalUriLauncher implements ExternalUriLauncher {
  _FakeExternalUriLauncher({
    this.result = true,
    this.error,
    this.pendingResult,
  });

  final bool result;
  final Object? error;
  final Completer<bool>? pendingResult;
  int callCount = 0;
  final List<Uri> launchedUris = <Uri>[];

  @override
  Future<bool> launch(Uri uri) {
    callCount += 1;
    launchedUris.add(uri);
    final launchError = error;
    if (launchError != null) {
      throw launchError;
    }
    return pendingResult?.future ?? Future<bool>.value(result);
  }
}
