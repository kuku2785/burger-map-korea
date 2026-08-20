import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/burger_style.dart';
import '../domain/store_location.dart';

const storeDetailBackButtonKey = ValueKey<String>('store-detail-back-button');
const storeAddressCopyButtonKey = ValueKey<String>('store-address-copy-button');

class StoreDetailScreen extends StatelessWidget {
  const StoreDetailScreen({super.key, required this.store});

  final StoreLocation store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: storeDetailBackButtonKey,
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: '뒤로가기',
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('매장 상세'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              _VerificationBadge(status: store.verificationStatus),
              const SizedBox(height: 32),
              _StoreDetailSection(
                icon: Icons.location_on_outlined,
                label: '주소',
                value: store.address.trim().isEmpty
                    ? '주소 정보가 없습니다.'
                    : store.address,
              ),
              const SizedBox(height: 12),
              Tooltip(
                message: '주소 복사',
                child: FilledButton.icon(
                  key: storeAddressCopyButtonKey,
                  onPressed: () => _copyAddress(context),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('주소 복사'),
                ),
              ),
              const SizedBox(height: 32),
              _StoreDetailSection(
                icon: Icons.lunch_dining_outlined,
                label: '버거 스타일',
                value: storeBurgerStyleLabel(store.burgerStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _copyAddress(BuildContext context) async {
    final address = store.address.trim();
    if (address.isEmpty) {
      _showMessage(context, '복사할 주소가 없습니다.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) {
      return;
    }
    _showMessage(context, '주소를 복사했습니다.');
  }

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

String storeBurgerStyleLabel(String value) {
  return BurgerStyle.parse(value).detailLabel;
}

String storeVerificationStatusLabel(String? status) {
  return switch (status?.trim().toLowerCase()) {
    'verified' => '검수 완료',
    'pending' => '검수 중',
    'needs_recheck' => '재확인 필요',
    _ => '검수 상태 확인 중',
  };
}

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final isVerified = status?.trim().toLowerCase() == 'verified';
    final colorScheme = Theme.of(context).colorScheme;
    final foregroundColor = isVerified
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      label: '검수 상태: ${storeVerificationStatusLabel(status)}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isVerified
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVerified
                    ? Icons.verified_outlined
                    : Icons.fact_check_outlined,
                size: 18,
                color: foregroundColor,
              ),
              const SizedBox(width: 6),
              Text(
                storeVerificationStatusLabel(status),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foregroundColor,
                  fontWeight: isVerified ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoreDetailSection extends StatelessWidget {
  const _StoreDetailSection({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );
  }
}
