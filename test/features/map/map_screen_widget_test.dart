import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/staging_fixture.dart';

void main() {
  Widget testApp(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: child),
    );
  }

  testWidgets('does not show preview card when no store is selected', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapScreen(
          config: AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
          ),
        ),
      ),
    );

    expect(find.byType(StorePreviewCard), findsNothing);
    expect(find.text('Google Maps API 키가 설정되지 않았습니다'), findsOneWidget);
  });

  testWidgets('shows store name, address, and burger style in preview card', (
    tester,
  ) async {
    final store = itaewonStoreLocations.first;

    await tester.pumpWidget(testApp(StorePreviewCard(store: store)));

    expect(find.text('검수 데이터'), findsOneWidget);
    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(find.text(store.burgerStyle), findsOneWidget);
  });

  testWidgets('shows missing API key guidance', (tester) async {
    await tester.pumpWidget(testApp(const MissingApiKeyView()));

    expect(find.text('Google Maps API 키가 설정되지 않았습니다'), findsOneWidget);
    expect(find.textContaining('GOOGLE_MAPS_API_KEY'), findsOneWidget);
    expect(find.text(itaewonStoreLocations.first.name), findsOneWidget);
  });

  testWidgets('shows map error guidance', (tester) async {
    await tester.pumpWidget(testApp(const MapErrorView(error: 'boom')));

    expect(find.textContaining('지도를 불러오지 못했습니다.'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('shows staging JSON errors without building the map', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.staging,
          ),
          stagingStoreLoader: () async {
            throw const FormatException('invalid staging json');
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MapErrorView), findsOneWidget);
    expect(find.textContaining('invalid staging json'), findsOneWidget);
  });

  testWidgets('staging store information appears in existing preview card', (
    tester,
  ) async {
    final stores = loadStagingFixture();
    final store = stores.first;

    await tester.pumpWidget(testApp(StorePreviewCard(store: store)));

    expect(find.text(store.name), findsOneWidget);
    expect(find.text(store.address), findsOneWidget);
    expect(find.text('미분류'), findsOneWidget);
  });
}
