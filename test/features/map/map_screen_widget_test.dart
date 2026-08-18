import 'dart:async';

import 'package:burger_map_korea/app/app_theme.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/data/itaewon_store_locations.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
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

  testWidgets('shows missing Supabase URL without starting a load', (
    tester,
  ) async {
    var loadCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
            storeDataMode: StoreDataMode.supabase,
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async {
            loadCalls += 1;
            return [];
          },
        ),
      ),
    );

    expect(find.byType(MissingSupabaseConfigView), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(loadCalls, 0);
  });

  testWidgets('shows missing Supabase publishable key', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MapScreen(
          config: AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: '',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
          ),
        ),
      ),
    );

    expect(find.byType(MissingSupabaseConfigView), findsOneWidget);
    expect(find.textContaining('SUPABASE_PUBLISHABLE_KEY'), findsOneWidget);
  });

  testWidgets('shows loading while Supabase rows are pending', (tester) async {
    final completer = Completer<List<StoreLocation>>();
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () => completer.future,
        ),
      ),
    );

    expect(find.byType(StoreDataLoadingView), findsOneWidget);
    completer.complete([]);
    await tester.pump();
  });

  testWidgets('shows an empty state for zero public Supabase stores', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async => [],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StoreDataEmptyView), findsOneWidget);
    expect(find.text('현재 공개된 매장이 없습니다.'), findsOneWidget);
    expect(find.text(itaewonStoreLocations.first.name), findsNothing);
  });

  testWidgets('hides Supabase error details and retries the load', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MapScreen(
          config: const AppConfig(
            environment: AppEnvironment.development,
            googleMapsApiKey: 'test-key',
            storeDataMode: StoreDataMode.supabase,
            supabaseUrl: 'https://unit.invalid',
            supabasePublishableKey: 'publishable-test-value',
          ),
          supabaseStoreLoader: () async {
            attempts += 1;
            if (attempts == 1) {
              throw StateError('private server response');
            }
            return [];
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StoreDataErrorView), findsOneWidget);
    expect(find.textContaining('private server response'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(attempts, 2);
    expect(find.byType(StoreDataEmptyView), findsOneWidget);
  });
}
