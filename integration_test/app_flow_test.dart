import 'package:burger_map_korea/app/app.dart';
import 'package:burger_map_korea/core/config/app_config.dart';
import 'package:burger_map_korea/features/favorites/domain/favorite_store_ids_store.dart';
import 'package:burger_map_korea/features/map/presentation/map_screen.dart';
import 'package:burger_map_korea/features/map/presentation/store_preview_card.dart';
import 'package:burger_map_korea/features/stores/domain/burger_style.dart';
import 'package:burger_map_korea/features/stores/domain/store_location.dart';
import 'package:burger_map_korea/features/stores/presentation/store_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:integration_test/integration_test.dart';

const _testConfig = AppConfig(
  environment: AppEnvironment.development,
  googleMapsApiKey: 'integration-test-key',
  storeDataMode: StoreDataMode.supabase,
  supabaseUrl: 'https://integration-test.invalid',
  supabasePublishableKey: 'integration-test-publishable-key',
);

final _testStores = <StoreLocation>[
  StoreLocation(
    id: 'integration-alpha',
    name: 'Alpha Test Burger',
    address: 'Seoul Yongsan Test-ro 1',
    latitude: 37.530,
    longitude: 126.990,
    burgerStyle: BurgerStyle.smash.code,
    verificationStatus: 'verified',
  ),
  StoreLocation(
    id: 'integration-beta',
    name: 'Beta Test Kitchen',
    address: 'Seoul Yongsan Test-ro 2',
    latitude: 37.535,
    longitude: 126.995,
    burgerStyle: BurgerStyle.classic.code,
    verificationStatus: 'verified',
  ),
  StoreLocation(
    id: 'integration-gamma',
    name: 'Gamma Test Grill',
    address: 'Seoul Mapo Test-ro 3',
    latitude: 37.550,
    longitude: 126.910,
    burgerStyle: BurgerStyle.smash.code,
    verificationStatus: 'verified',
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search and burger style filter show only matching stores', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.enterText(find.byKey(storeSearchFieldKey), 'Yongsan');
    await tester.pumpAndSettle();

    expect(_mapMarker('integration-alpha'), findsOneWidget);
    expect(_mapMarker('integration-beta'), findsOneWidget);
    expect(_mapMarker('integration-gamma'), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final smashFilter = find.byKey(burgerStyleFilterKey(BurgerStyle.smash));
    final burgerStyleFilters = find.ancestor(
      of: find.byKey(burgerStyleAllFilterKey),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(burgerStyleFilters, findsOneWidget);
    await tester.dragUntilVisible(
      smashFilter,
      burgerStyleFilters,
      const Offset(-160, 0),
    );
    expect(smashFilter, findsOneWidget);
    await tester.tap(smashFilter);
    await tester.pumpAndSettle();

    expect(_mapMarker('integration-alpha'), findsOneWidget);
    expect(_mapMarker('integration-beta'), findsNothing);
    expect(_mapMarker('integration-gamma'), findsNothing);
    expect(_searchResultText('Alpha Test Burger'), findsOneWidget);
    expect(_searchResultText('Beta Test Kitchen'), findsNothing);
    expect(_searchResultText('Gamma Test Grill'), findsNothing);
  });

  testWidgets('store detail shows selected data and returns to the map', (
    tester,
  ) async {
    await _pumpTestApp(tester);

    await tester.tap(_mapMarker('integration-alpha'));
    await tester.pumpAndSettle();
    expect(find.byType(StorePreviewCard), findsOneWidget);

    await _tapVisibleButton(tester, find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(StoreDetailScreen), findsOneWidget);
    final detailScreen = find.byType(StoreDetailScreen);
    expect(
      find.descendant(
        of: detailScreen,
        matching: find.text('Alpha Test Burger'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailScreen,
        matching: find.text('Seoul Yongsan Test-ro 1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: detailScreen, matching: find.text('스매시')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: detailScreen,
        matching: find.text('Beta Test Kitchen'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(storeDetailBackButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(MapScreen), findsOneWidget);
    expect(find.byType(StoreDetailScreen), findsNothing);
    expect(find.byType(StorePreviewCard), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(StorePreviewCard),
        matching: find.text('Alpha Test Burger'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('favorite can be added, filtered, and removed', (tester) async {
    final favorites = _MemoryFavoriteStoreIdsStore();
    await _pumpTestApp(tester, favorites: favorites);

    await tester.tap(_mapMarker('integration-alpha'));
    await tester.pumpAndSettle();
    await _tapVisibleButton(tester, find.byKey(storePreviewDetailsButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pumpAndSettle();

    expect(favorites.storeIds, {'integration-alpha'});
    expect(find.byIcon(Icons.star), findsOneWidget);

    await tester.tap(find.byKey(storeDetailBackButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pumpAndSettle();

    expect(_mapMarker('integration-alpha'), findsOneWidget);
    expect(_mapMarker('integration-beta'), findsNothing);
    expect(_mapMarker('integration-gamma'), findsNothing);
    expect(find.text('Alpha Test Burger'), findsWidgets);

    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await _tapVisibleButton(tester, find.byKey(storePreviewDetailsButtonKey));
    await tester.tap(find.byKey(storeFavoriteButtonKey));
    await tester.pumpAndSettle();

    expect(favorites.storeIds, isEmpty);
    expect(find.byIcon(Icons.star_border), findsOneWidget);

    await tester.tap(find.byKey(storeDetailBackButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(favoritesOnlyFilterKey));
    await tester.pumpAndSettle();

    expect(_mapMarker('integration-alpha'), findsNothing);
    expect(_mapMarker('integration-beta'), findsNothing);
    expect(_mapMarker('integration-gamma'), findsNothing);
    expect(find.byKey(storeSearchResultsKey), findsOneWidget);
    expect(find.byType(StorePreviewCard), findsNothing);
  });
}

Future<void> _pumpTestApp(
  WidgetTester tester, {
  _MemoryFavoriteStoreIdsStore? favorites,
}) async {
  await tester.pumpWidget(
    BurgerMapApp(
      config: _testConfig,
      supabaseStoreLoader: () async => List.unmodifiable(_testStores),
      favoriteStoreIdsStore: favorites ?? _MemoryFavoriteStoreIdsStore(),
      mapSurfaceBuilder: (markers, onMapTap) {
        return _TestMapSurface(markers: markers, onMapTap: onMapTap);
      },
    ),
  );
  await tester.pumpAndSettle();

  expect(find.byType(MapScreen), findsOneWidget);
  expect(_mapMarker('integration-alpha'), findsOneWidget);
  expect(_mapMarker('integration-beta'), findsOneWidget);
  expect(_mapMarker('integration-gamma'), findsOneWidget);
}

Finder _mapMarker(String storeId) {
  return find.byKey(ValueKey<String>('integration-map-marker-$storeId'));
}

Finder _searchResultText(String text) {
  return find.descendant(
    of: find.byKey(storeSearchResultsKey),
    matching: find.text(text),
  );
}

Future<void> _tapVisibleButton(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  final rect = tester.getRect(finder);
  await tester.tapAt(Offset(rect.center.dx, rect.top + 8));
  await tester.pumpAndSettle();
}

class _TestMapSurface extends StatelessWidget {
  const _TestMapSurface({required this.markers, required this.onMapTap});

  final Set<Marker> markers;
  final ValueChanged<LatLng> onMapTap;

  @override
  Widget build(BuildContext context) {
    final sortedMarkers = markers.toList()
      ..sort((left, right) {
        return left.markerId.value.compareTo(right.markerId.value);
      });

    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Center(
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final marker in sortedMarkers)
              FilledButton.tonalIcon(
                key: ValueKey<String>(
                  'integration-map-marker-${marker.markerId.value}',
                ),
                onPressed: marker.onTap,
                icon: const Icon(Icons.location_on_outlined),
                label: Text(marker.infoWindow.title ?? marker.markerId.value),
              ),
            IconButton(
              key: const ValueKey<String>('integration-map-background'),
              onPressed: () => onMapTap(const LatLng(0, 0)),
              tooltip: 'Clear selected store',
              icon: const Icon(Icons.layers_clear_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryFavoriteStoreIdsStore implements FavoriteStoreIdsStore {
  Set<String> storeIds = <String>{};

  @override
  Future<Set<String>> load() async => Set.unmodifiable(storeIds);

  @override
  Future<void> save(Set<String> storeIds) async {
    this.storeIds = Set.of(storeIds);
  }
}
