import 'dart:async';

import 'package:burger_map_korea/features/menu/domain/menu_item.dart';
import 'package:burger_map_korea/features/menu/domain/menu_repository.dart';
import 'package:burger_map_korea/features/menu/presentation/store_menu_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  MenuItem menu({
    String id = 'menu-a',
    String storeId = 'store-a',
    String name = '더블 치즈버거',
    int? price = 12900,
    bool isSignature = true,
    String? category = '버거',
    String? description = '체다치즈',
  }) => MenuItem(
    id: id,
    storeId: storeId,
    name: name,
    price: price,
    category: category,
    description: description,
    isSignature: isSignature,
    displayOrder: 0,
  );

  Widget app(
    String storeId,
    MenuRepository repository, {
    double textScale = 1,
  }) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StoreMenuSection(storeId: storeId, repository: repository),
      ),
    ),
  );

  testWidgets('loading keeps section visible, then shows priced signature', (
    tester,
  ) async {
    final pending = Completer<List<MenuItem>>();
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', pending.future);
    await tester.pumpWidget(app('store-a', repository));

    expect(find.text('메뉴'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('더블 치즈버거'), findsNothing);

    pending.complete([menu()]);
    await tester.pumpAndSettle();
    expect(find.text('더블 치즈버거'), findsOneWidget);
    expect(find.text('대표'), findsOneWidget);
    expect(find.text('12,900원'), findsOneWidget);
    expect(find.text('체다치즈'), findsOneWidget);
    expect(repository.requestedStoreIds, ['store-a']);
  });

  testWidgets('empty, multiple and nullable price have distinct display', (
    tester,
  ) async {
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', Future.value([]))
      ..enqueue(
        'store-b',
        Future.value([
          menu(storeId: 'store-b', price: null, isSignature: false),
          menu(id: 'menu-b', storeId: 'store-b', name: '치킨버거'),
        ]),
      );
    await tester.pumpWidget(app('store-a', repository));
    await tester.pumpAndSettle();
    expect(find.text('등록된 메뉴 정보가 없습니다.'), findsOneWidget);
    expect(find.text('메뉴 정보를 불러오지 못했습니다.'), findsNothing);

    await tester.pumpWidget(app('store-b', repository));
    await tester.pumpAndSettle();
    expect(find.text('더블 치즈버거'), findsOneWidget);
    expect(find.text('치킨버거'), findsOneWidget);
    expect(find.text('가격 정보 없음'), findsOneWidget);
    expect(find.text('대표'), findsOneWidget);
  });

  testWidgets('error stays inside section and retry can recover', (
    tester,
  ) async {
    final failed = Completer<List<MenuItem>>();
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', failed.future)
      ..enqueue('store-a', Future.value([menu()]));
    await tester.pumpWidget(app('store-a', repository));
    failed.completeError(StateError('private backend detail'));
    await tester.pumpAndSettle();
    expect(find.text('메뉴 정보를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('private backend detail'), findsNothing);
    expect(
      tester.getSize(find.byKey(menuRetryButtonKey)).height,
      greaterThanOrEqualTo(48),
    );

    await tester.tap(find.byKey(menuRetryButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('더블 치즈버거'), findsOneWidget);
    expect(repository.requestedStoreIds, ['store-a', 'store-a']);
  });

  testWidgets('late A result cannot replace B, even when A fails', (
    tester,
  ) async {
    final lateA = Completer<List<MenuItem>>();
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', lateA.future)
      ..enqueue(
        'store-b',
        Future.value([menu(storeId: 'store-b', name: 'B 메뉴')]),
      );
    await tester.pumpWidget(app('store-a', repository));
    await tester.pumpWidget(app('store-b', repository));
    await tester.pumpAndSettle();
    expect(find.text('B 메뉴'), findsOneWidget);

    lateA.completeError(StateError('old request failed'));
    await tester.pumpAndSettle();
    expect(find.text('B 메뉴'), findsOneWidget);
    expect(find.text('메뉴 정보를 불러오지 못했습니다.'), findsNothing);
    expect(repository.requestedStoreIds, ['store-a', 'store-b']);
  });

  testWidgets('late A success cannot replace B menus', (tester) async {
    final lateA = Completer<List<MenuItem>>();
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', lateA.future)
      ..enqueue(
        'store-b',
        Future.value([menu(storeId: 'store-b', name: 'B 메뉴')]),
      );
    await tester.pumpWidget(app('store-a', repository));
    await tester.pumpWidget(app('store-b', repository));
    await tester.pumpAndSettle();

    lateA.complete([menu(storeId: 'store-a', name: 'A 메뉴')]);
    await tester.pumpAndSettle();
    expect(find.text('B 메뉴'), findsOneWidget);
    expect(find.text('A 메뉴'), findsNothing);
  });

  testWidgets('dispose ignores a pending menu response', (tester) async {
    final pending = Completer<List<MenuItem>>();
    final repository = _FakeMenuRepository()
      ..enqueue('store-a', pending.future);
    await tester.pumpWidget(app('store-a', repository));
    await tester.pumpWidget(const SizedBox.shrink());

    pending.complete([menu()]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('long name fits narrow screen with large text and dispose', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeMenuRepository()
      ..enqueue(
        'store-a',
        Future.value([menu(name: '아주 긴 버거 메뉴 이름이 좁은 화면에서도 모두 읽히도록 줄바꿈되는 메뉴')]),
      );
    await tester.pumpWidget(app('store-a', repository, textScale: 2));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(
        tester.element(find.textContaining('아주 긴 버거 메뉴 이름')),
      ).scale(10),
      20,
    );
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  test('formats KRW prices with groups of three digits', () {
    expect(formatMenuPrice(0), '0원');
    expect(formatMenuPrice(1000), '1,000원');
    expect(formatMenuPrice(12900), '12,900원');
    expect(formatMenuPrice(1000000), '1,000,000원');
  });
}

class _FakeMenuRepository implements MenuRepository {
  final requestedStoreIds = <String>[];
  final _responses = <String, List<Future<List<MenuItem>>>>{};

  void enqueue(String storeId, Future<List<MenuItem>> response) {
    _responses.putIfAbsent(storeId, () => []).add(response);
  }

  @override
  Future<List<MenuItem>> fetchMenusForStore(String storeId) {
    requestedStoreIds.add(storeId);
    return _responses[storeId]!.removeAt(0);
  }
}
