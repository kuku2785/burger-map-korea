import 'package:flutter/material.dart';

import '../../stores/domain/burger_style.dart';
import '../../stores/domain/store_location.dart';

/// A list of the same public, filtered snapshot used by the map. It never
/// requires a map controller to open a detail or changes the saved UUID set.
class StoreListPanel extends StatelessWidget {
  const StoreListPanel({
    super.key,
    required this.controller,
    required this.searchPanel,
    required this.stores,
    required this.favoriteIds,
    required this.favoritesReady,
    required this.emptyMessage,
    required this.onReset,
    required this.onOpen,
    required this.onShowOnMap,
  });

  final ScrollController controller;
  final Widget searchPanel;
  final List<StoreLocation> stores;
  final Set<String> favoriteIds;
  final bool favoritesReady;
  final String emptyMessage;
  final VoidCallback onReset;
  final ValueChanged<StoreLocation> onOpen;
  final ValueChanged<StoreLocation> onShowOnMap;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: CustomScrollView(
        key: const PageStorageKey<String>('public-store-list'),
        controller: controller,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(child: searchPanel),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                liveRegion: true,
                child: Text('매장 ${stores.length}개'),
              ),
            ),
          ),
          if (stores.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(emptyMessage, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: onReset,
                      child: const Text('조건 초기화'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: stores.length,
              itemBuilder: (context, index) {
                final store = stores[index];
                return Card(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        key: ValueKey<String>('store-list-item-${store.id}'),
                        title: Text(store.name),
                        subtitle: Text(
                          '${store.address}\n${BurgerStyle.parse(store.burgerStyle).displayLabel}',
                        ),
                        trailing: Icon(
                          favoritesReady && favoriteIds.contains(store.id)
                              ? Icons.star
                              : Icons.star_border,
                          semanticLabel: !favoritesReady
                              ? '즐겨찾기 확인 중'
                              : favoriteIds.contains(store.id)
                              ? '즐겨찾기됨'
                              : '즐겨찾기 안 됨',
                        ),
                        onTap: () => onOpen(store),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: ValueKey<String>('store-list-map-${store.id}'),
                          onPressed: () => onShowOnMap(store),
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('지도에서 보기'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
