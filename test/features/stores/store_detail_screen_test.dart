import 'package:burger_map_korea/app/app_theme.dart';
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

  Widget detailApp(StoreLocation store) {
    return MaterialApp(
      theme: AppTheme.light,
      home: StoreDetailScreen(store: store),
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
      ),
    );

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
