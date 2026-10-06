import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

const accountDeleteEntryKey = ValueKey('account-delete-entry');
const accountDeleteConfirmKey = ValueKey('account-delete-confirm');
const accountDeleteCancelKey = ValueKey('account-delete-cancel');

class AccountDeletionButton extends StatefulWidget {
  const AccountDeletionButton({super.key, required this.controller});

  final AuthController controller;

  @override
  State<AccountDeletionButton> createState() => _AccountDeletionButtonState();
}

class _AccountDeletionButtonState extends State<AccountDeletionButton> {
  bool _dialogOpen = false;

  Future<void> _confirm() async {
    final controller = widget.controller;
    if (_dialogOpen || controller.deletingAccount || !controller.hasSession) {
      return;
    }
    final expectedUser = controller.currentUserId;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final busy = controller.deletingAccount;
            final sameUser = controller.currentUserId == expectedUser;
            return PopScope(
              canPop: !busy,
              child: AlertDialog(
                title: const Text('계정을 삭제할까요?'),
                scrollable: true,
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '버거맵 계정을 삭제하면 프로필, 작성한 리뷰와 신고, '
                      '내 리뷰에 연결된 신고가 삭제되며 복구할 수 없습니다.\n\n'
                      'Google 계정은 삭제되지 않습니다. 이 기기의 즐겨찾기는 유지됩니다.',
                    ),
                    if (busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          label: '계정 삭제 처리 중',
                          child: const LinearProgressIndicator(),
                        ),
                      ),
                    if (!busy && controller.message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(controller.message!),
                        ),
                      ),
                    if (!sameUser && !busy)
                      const Text('로그인 상태가 변경되었습니다. 이 창을 닫아 주세요.'),
                  ],
                ),
                actions: [
                  TextButton(
                    key: accountDeleteCancelKey,
                    autofocus: true,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: busy
                        ? null
                        : () => Navigator.of(dialogContext).pop(),
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    key: accountDeleteConfirmKey,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed:
                        busy ||
                            !sameUser ||
                            controller.signingOut ||
                            controller.submittingNickname
                        ? null
                        : () async {
                            final deleted = await controller.deleteAccount();
                            if (!dialogContext.mounted) return;
                            if (deleted ||
                                controller.currentUserId != expectedUser) {
                              if (!deleted && controller.message != null) {
                                ScaffoldMessenger.of(
                                  dialogContext,
                                ).showSnackBar(
                                  SnackBar(content: Text(controller.message!)),
                                );
                              }
                              Navigator.of(dialogContext).pop();
                            }
                          },
                    child: const Text('계정 삭제'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (!controller.hasSession) return const SizedBox.shrink();
      return Semantics(
        hint: '복구할 수 없는 계정 삭제의 확인창을 엽니다',
        child: IconButton(
          key: accountDeleteEntryKey,
          tooltip: '계정 삭제',
          color: Theme.of(context).colorScheme.error,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          icon: const Icon(Icons.person_remove_outlined),
          onPressed:
              controller.deletingAccount ||
                  controller.signingOut ||
                  controller.submittingNickname
              ? null
              : _confirm,
        ),
      );
    },
  );
}
