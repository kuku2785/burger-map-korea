import 'package:flutter/material.dart';

import '../application/auth_controller.dart';

const authEmailFieldKey = ValueKey<String>('auth-email-field');
const authEmailSubmitButtonKey = ValueKey<String>('auth-email-submit');
const authMessageKey = ValueKey<String>('auth-message');

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AuthController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('로그인'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '버거맵 코리아',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '이메일로 받은 로그인 링크를 열면 앱으로 돌아옵니다.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      key: authEmailFieldKey,
                      controller: _emailController,
                      enabled: !widget.controller.sendingMagicLink,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: '이메일',
                        hintText: 'name@example.com',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: widget.controller.sendingMagicLink
                          ? null
                          : (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      button: true,
                      enabled: !widget.controller.sendingMagicLink,
                      label: widget.controller.sendingMagicLink
                          ? '로그인 링크 전송 중'
                          : '이메일로 로그인 링크 받기',
                      child: SizedBox(
                        height: 52,
                        child: FilledButton(
                          key: authEmailSubmitButtonKey,
                          onPressed: widget.controller.sendingMagicLink
                              ? null
                              : _submit,
                          child: widget.controller.sendingMagicLink
                              ? const SizedBox.square(
                                  dimension: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('로그인 링크 받기'),
                        ),
                      ),
                    ),
                    if (widget.controller.message != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          widget.controller.message!,
                          key: authMessageKey,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: widget.controller.magicLinkSent
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
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
      ),
    );
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    widget.controller.sendMagicLink(_emailController.text);
  }
}
