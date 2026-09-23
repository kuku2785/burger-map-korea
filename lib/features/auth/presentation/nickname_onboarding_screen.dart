import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

const nicknameFieldKey = ValueKey<String>('nickname-field');
const nicknameSubmitButtonKey = ValueKey<String>('nickname-submit');
const nicknameMessageKey = ValueKey<String>('nickname-message');

class NicknameOnboardingScreen extends StatefulWidget {
  const NicknameOnboardingScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<NicknameOnboardingScreen> createState() =>
      _NicknameOnboardingScreenState();
}

class _NicknameOnboardingScreenState extends State<NicknameOnboardingScreen> {
  final _nicknameController = TextEditingController();

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('닉네임 설정'),
        actions: [
          IconButton(
            tooltip: '로그아웃',
            onPressed: widget.controller.signingOut
                ? null
                : widget.controller.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '사용할 닉네임을 정해 주세요',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '2~20자의 한글, 영문, 숫자, 밑줄(_)을 사용할 수 있습니다. '
                    '운영자를 뜻하는 표현은 사용할 수 없습니다.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: nicknameFieldKey,
                    controller: _nicknameController,
                    enabled: !widget.controller.submittingNickname,
                    maxLength: 20,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: '닉네임',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: widget.controller.submittingNickname
                        ? null
                        : (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    enabled: !widget.controller.submittingNickname,
                    label: widget.controller.submittingNickname
                        ? '닉네임 저장 중'
                        : '닉네임 저장',
                    child: SizedBox(
                      height: 52,
                      child: FilledButton(
                        key: nicknameSubmitButtonKey,
                        onPressed: widget.controller.submittingNickname
                            ? null
                            : _submit,
                        child: widget.controller.submittingNickname
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('시작하기'),
                      ),
                    ),
                  ),
                  if (widget.controller.message != null) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        widget.controller.message!,
                        key: nicknameMessageKey,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    widget.controller.submitNickname(_nicknameController.text);
  }
}
