import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/domain/store_region.dart';
import 'package:burger_map_korea/features/stores/presentation/region_selection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _openRegionSelectionKey = ValueKey<String>('open-region-selection');
const _pendingRouteResult = Object();

void main() {
  final alphaOne = _region(
    sidoName: 'Alpha Province',
    sigunguName: 'Central District',
    dongName: 'River Neighborhood',
  );
  final alphaTwo = _region(
    sidoName: 'Alpha Province',
    sigunguName: 'Central District',
    dongCode: '1117010200',
    dongName: 'Garden Neighborhood',
  );
  final betaOne = _region(
    sidoCode: '22',
    sidoName: 'Beta Province',
    sigunguCode: '22110',
    sigunguName: 'North District',
    dongCode: '2211010100',
    dongName: 'Hill Neighborhood',
  );

  testWidgets('gates children and applies a sido to sigungu to dong path', (
    tester,
  ) async {
    final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[
      _store('alpha-one', alphaOne),
      _store('alpha-two', alphaTwo),
    ]);
    final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
    addTearDown(stores.dispose);
    addTearDown(routeResult.dispose);
    await tester.pumpWidget(_app(stores, routeResult: routeResult));
    await _open(tester);

    expect(_dropdown(tester, regionSigunguDropdownKey).onChanged, isNull);
    expect(_dropdown(tester, regionDongDropdownKey).onChanged, isNull);

    _dropdown(tester, regionSidoDropdownKey).onChanged!('11');
    await tester.pump();
    expect(_dropdown(tester, regionSigunguDropdownKey).onChanged, isNotNull);
    expect(_dropdown(tester, regionDongDropdownKey).onChanged, isNull);

    _dropdown(tester, regionSigunguDropdownKey).onChanged!('11/11170');
    await tester.pump();
    expect(_dropdown(tester, regionDongDropdownKey).onChanged, isNotNull);

    _dropdown(tester, regionDongDropdownKey).onChanged!('11/11170/1117010200');
    await tester.pump();
    await tester.tap(find.byKey(regionApplyButtonKey));
    await tester.pumpAndSettle();

    final result = routeResult.value! as RegionSelectionResult;
    expect(result.selection, StoreRegionFilter.dong(alphaTwo));
  });

  testWidgets('changing a parent resets the lower selections', (tester) async {
    final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[
      _store('alpha', alphaOne),
      _store('beta', betaOne),
    ]);
    final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
    addTearDown(stores.dispose);
    addTearDown(routeResult.dispose);
    await tester.pumpWidget(
      _app(
        stores,
        initialSelection: StoreRegionFilter.dong(alphaOne),
        routeResult: routeResult,
      ),
    );
    await _open(tester);

    _dropdown(tester, regionSidoDropdownKey).onChanged!('22');
    await tester.pump();

    expect(_dropdown(tester, regionDongDropdownKey).onChanged, isNull);
    expect(
      _dropdown(
        tester,
        regionSigunguDropdownKey,
      ).items!.where((item) => item.value == '11/11170'),
      isEmpty,
    );
    await tester.tap(find.byKey(regionApplyButtonKey));
    await tester.pumpAndSettle();

    final result = routeResult.value! as RegionSelectionResult;
    expect(result.selection, StoreRegionFilter.sido(betaOne));
  });

  testWidgets('cancel and back return null while clear is an explicit result', (
    tester,
  ) async {
    final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[
      _store('alpha', alphaOne),
    ]);
    final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
    addTearDown(stores.dispose);
    addTearDown(routeResult.dispose);
    await tester.pumpWidget(
      _app(
        stores,
        initialSelection: StoreRegionFilter.dong(alphaOne),
        routeResult: routeResult,
      ),
    );

    await _open(tester);
    await tester.tap(find.byKey(regionCancelButtonKey));
    await tester.pumpAndSettle();
    expect(routeResult.value, isNull);

    routeResult.value = _pendingRouteResult;
    await _open(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(routeResult.value, isNull);

    routeResult.value = _pendingRouteResult;
    await _open(tester);
    await tester.tap(find.byKey(regionClearButtonKey));
    await tester.pumpAndSettle();
    final clearResult = routeResult.value! as RegionSelectionResult;
    expect(clearResult.selection, isNull);
  });

  testWidgets(
    'a null refresh hides stale options and a missing choice stays unapplied',
    (tester) async {
      final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[
        _store('alpha', alphaOne),
      ]);
      final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
      addTearDown(stores.dispose);
      addTearDown(routeResult.dispose);
      await tester.pumpWidget(
        _app(
          stores,
          initialSelection: StoreRegionFilter.dong(alphaOne),
          routeResult: routeResult,
        ),
      );
      await _open(tester);

      await tester.tap(
        find.descendant(
          of: find.byKey(regionSidoDropdownKey),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(alphaOne.sidoName), findsWidgets);

      stores.value = null;
      await tester.pumpAndSettle();

      expect(find.text(alphaOne.sidoName), findsNothing);
      expect(find.text(alphaOne.sigunguName), findsNothing);
      expect(find.text(alphaOne.dongName), findsNothing);
      expect(_dropdown(tester, regionSidoDropdownKey).onChanged, isNull);
      expect(
        tester.widget<FilledButton>(find.byKey(regionApplyButtonKey)).onPressed,
        isNull,
      );

      stores.value = <StoreLocation>[_store('beta', betaOne)];
      await tester.pump();

      expect(_dropdown(tester, regionSidoDropdownKey).value, isNull);
      expect(
        tester.widget<FilledButton>(find.byKey(regionApplyButtonKey)).onPressed,
        isNull,
      );
      expect(routeResult.value, same(_pendingRouteResult));
    },
  );

  testWidgets('handles long dropdown labels at 320 px and 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longRegion = _region(
      sidoName: 'A Province With An Intentionally Very Long Synthetic Name',
      sigunguName: 'A District With An Intentionally Very Long Synthetic Name',
      dongName: 'A Neighborhood With An Intentionally Very Long Synthetic Name',
    );
    final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[
      _store('long-label', longRegion),
    ]);
    final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
    addTearDown(stores.dispose);
    addTearDown(routeResult.dispose);

    await tester.pumpWidget(
      _app(stores, textScale: 2, routeResult: routeResult),
    );
    await _open(tester);
    _dropdown(tester, regionSidoDropdownKey).onChanged!('11');
    await tester.pump();
    _dropdown(tester, regionSigunguDropdownKey).onChanged!('11/11170');
    await tester.pump();
    _dropdown(tester, regionDongDropdownKey).onChanged!('11/11170/1117010100');
    await tester.pump();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and unclassified stores do not create fake regions', (
    tester,
  ) async {
    final stores = ValueNotifier<List<StoreLocation>?>(<StoreLocation>[]);
    final routeResult = ValueNotifier<Object?>(_pendingRouteResult);
    addTearDown(stores.dispose);
    addTearDown(routeResult.dispose);
    await tester.pumpWidget(_app(stores, routeResult: routeResult));
    await _open(tester);

    expect(_dropdown(tester, regionSidoDropdownKey).items, hasLength(1));
    expect(_dropdown(tester, regionSigunguDropdownKey).items, isEmpty);
    expect(_dropdown(tester, regionDongDropdownKey).items, isEmpty);

    stores.value = <StoreLocation>[_store('unclassified', null)];
    await tester.pump();

    expect(_dropdown(tester, regionSidoDropdownKey).items, hasLength(1));
    expect(_dropdown(tester, regionSigunguDropdownKey).items, isEmpty);
    expect(_dropdown(tester, regionDongDropdownKey).items, isEmpty);
  });
}

StoreRegion _region({
  String sidoCode = '11',
  required String sidoName,
  String sigunguCode = '11170',
  required String sigunguName,
  String dongCode = '1117010100',
  required String dongName,
}) {
  return StoreRegion(
    sidoCode: sidoCode,
    sidoName: sidoName,
    sigunguCode: sigunguCode,
    sigunguName: sigunguName,
    dongCode: dongCode,
    dongName: dongName,
  );
}

StoreLocation _store(String id, StoreRegion? region) {
  return StoreLocation(
    id: id,
    name: 'Synthetic Store $id',
    latitude: 0,
    longitude: 0,
    address: 'Synthetic address $id',
    burgerStyle: 'synthetic-style',
    region: region,
  );
}

Widget _app(
  ValueNotifier<List<StoreLocation>?> stores, {
  StoreRegionFilter? initialSelection,
  required ValueNotifier<Object?> routeResult,
  double textScale = 1,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: _openRegionSelectionKey,
            onPressed: () async {
              routeResult.value = await Navigator.of(context)
                  .push<RegionSelectionResult>(
                    MaterialPageRoute<RegionSelectionResult>(
                      builder: (_) => RegionSelectionScreen(
                        storesListenable: stores,
                        initialSelection: initialSelection,
                      ),
                    ),
                  );
            },
            child: const Text('Open region selection'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(_openRegionSelectionKey));
  await tester.pumpAndSettle();
}

DropdownButton<String> _dropdown(WidgetTester tester, Key wrapperKey) {
  return tester.widget<DropdownButton<String>>(
    find.descendant(
      of: find.byKey(wrapperKey),
      matching: find.byType(DropdownButton<String>),
    ),
  );
}
