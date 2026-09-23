import 'package:flutter/material.dart';

import '../application/auth_controller.dart';
import 'login_screen.dart';
import 'nickname_onboarding_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controller,
    required this.signedInBuilder,
  });

  final AuthController controller;
  final Widget Function(BuildContext context, Future<void> Function() signOut)
  signedInBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => switch (widget.controller.state) {
        AuthGateState.initializing ||
        AuthGateState.signedInProfileLoading => const _AuthLoadingScreen(),
        AuthGateState.signedOut => LoginScreen(controller: widget.controller),
        AuthGateState.signedInNeedsProfile => NicknameOnboardingScreen(
          controller: widget.controller,
        ),
        AuthGateState.signedInReady => widget.signedInBuilder(
          context,
          widget.controller.signOut,
        ),
        AuthGateState.error => _AuthErrorScreen(
          message:
              widget.controller.message ?? '로그인 상태를 확인하지 못했습니다. 다시 시도해 주세요.',
          onRetry: widget.controller.retry,
          onSignOut: widget.controller.signOut,
          signingOut: widget.controller.signingOut,
        ),
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Semantics(
          liveRegion: true,
          label: '로그인 상태 확인 중',
          child: const CircularProgressIndicator(),
        ),
      ),
    );
  }
}

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({
    required this.message,
    required this.onRetry,
    required this.onSignOut,
    required this.signingOut,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;
  final bool signingOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Semantics(liveRegion: true, child: Text(message)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: onRetry,
                      child: const Text('다시 시도'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: signingOut ? null : onSignOut,
                    child: const Text('로그아웃'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
