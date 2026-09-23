import 'package:flutter/material.dart';

import '../domain/menu_item.dart';
import '../domain/menu_repository.dart';

const menuRetryButtonKey = ValueKey<String>('menu-retry-button');

class StoreMenuSection extends StatefulWidget {
  const StoreMenuSection({
    super.key,
    required this.storeId,
    required this.repository,
  });

  final String storeId;
  final MenuRepository repository;

  @override
  State<StoreMenuSection> createState() => _StoreMenuSectionState();
}

class _StoreMenuSectionState extends State<StoreMenuSection> {
  late Future<List<MenuItem>> _menus;

  @override
  void initState() {
    super.initState();
    _menus = widget.repository.fetchMenusForStore(widget.storeId);
  }

  @override
  void didUpdateWidget(StoreMenuSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId ||
        oldWidget.repository != widget.repository) {
      _menus = widget.repository.fetchMenusForStore(widget.storeId);
    }
  }

  void _retry() {
    setState(() {
      _menus = widget.repository.fetchMenusForStore(widget.storeId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('메뉴', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        FutureBuilder<List<MenuItem>>(
          future: _menus,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Semantics(
                liveRegion: true,
                label: '메뉴 정보를 불러오는 중',
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: const Text('메뉴 정보를 불러오지 못했습니다.'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: menuRetryButtonKey,
                    onPressed: _retry,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 시도'),
                  ),
                ],
              );
            }
            final menus = snapshot.data!;
            if (menus.isEmpty) {
              return Semantics(
                liveRegion: true,
                child: const Text('등록된 메뉴 정보가 없습니다.'),
              );
            }
            return Column(
              children: [for (final menu in menus) _MenuCard(menu: menu)],
            );
          },
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.menu});

  final MenuItem menu;

  @override
  Widget build(BuildContext context) {
    final category = menu.category?.trim();
    final description = menu.description?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(menu.name, style: Theme.of(context).textTheme.titleMedium),
                if (menu.isSignature) const Chip(label: Text('대표')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              menu.price == null ? '가격 정보 없음' : formatMenuPrice(menu.price!),
            ),
            if (category != null && category.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(category),
            ],
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(description),
            ],
          ],
        ),
      ),
    );
  }
}

String formatMenuPrice(int price) {
  final digits = price.toString();
  final formatted = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  return '$formatted원';
}
