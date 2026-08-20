import 'package:flutter/material.dart';

import '../../stores/domain/store_location.dart';

const storePreviewDetailsButtonKey = ValueKey<String>(
  'store-preview-details-button',
);

class StorePreviewCard extends StatelessWidget {
  const StorePreviewCard({
    super.key,
    required this.store,
    required this.onViewDetails,
  });

  final StoreLocation store;
  final VoidCallback onViewDetails;

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
              '검수 데이터',
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
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Tooltip(
                message: '매장 상세보기',
                child: TextButton.icon(
                  key: storePreviewDetailsButtonKey,
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('상세보기'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
