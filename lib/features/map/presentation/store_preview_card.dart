import 'package:flutter/material.dart';

import '../../stores/domain/store_location.dart';

class StorePreviewCard extends StatelessWidget {
  const StorePreviewCard({super.key, required this.store});

  final StoreLocation store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '테스트 데이터',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(store.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(store.address),
            const SizedBox(height: 4),
            Text(store.burgerStyle),
          ],
        ),
      ),
    );
  }
}
