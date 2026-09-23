import 'dart:async';

import 'package:flutter/material.dart';

import '../application/auth_controller.dart';
import 'login_screen.dart';
import 'nickname_onboarding_screen.dart';

typedef PublicExplorationBuilder =
    Widget Function(
      BuildContext context,
      VoidCallback onSignIn,
      Future<void> Function()? onSignOut,
      VoidCallback? onSetNickname,
      VoidCallback? onRetryAuth,
    );

/// Authentication adds optional account actions to a persistent public map.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.controllerLoader,
    required this.publicBuilder,
  });

  final Future<AuthController> Function() controllerLoader;
  final PublicExplorationBuilder publicBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  AuthController? _controller;
  Future<AuthController?>? _controllerLoad;
  Route<void>? _loginRoute;
  Route<void>? _nicknameRoute;
  bool _openingLogin = false;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureController());
  }

  Future<AuthController?> _ensureController() {
    final controller = _controller;
    if (controller != null) return Future.value(controller);
    final pending = _controllerLoad;
    if (pending != null) return pending;

    final attempt = _loadController();
    _controllerLoad = attempt;
    unawaited(
      attempt.whenComplete(() {
        if (identical(_controllerLoad, attempt)) _controllerLoad = null;
      }),
    );
    return attempt;
  }

  Future<AuthController?> _loadController() async {
    try {
      final controller = await widget.controllerLoader();
      if (!mounted) {
        controller.dispose();
        return null;
      }
      _controller = controller;
      controller.addListener(_onAuthChanged);
      controller.initialize();
      setState(() {});
      return controller;
    } on Object {
      // A failed Auth bootstrap must not block public store discovery.
      return null;
    }
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(() {});
    final controller = _controller;
    if (controller?.hasSession == true) _closeRoute(_loginRoute);
    if (controller?.hasSession != true ||
        controller?.state == AuthGateState.signedInReady) {
      _closeRoute(_nicknameRoute);
    }
  }

  void _closeRoute(Route<void>? route) {
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && route.isCurrent) route.navigator?.pop();
    });
  }

  Future<void> _openLogin() async {
    if (_openingLogin || _loginRoute != null) return;
    _openingLogin = true;
    try {
      final controller = await _ensureController();
      if (!mounted) return;
      if (controller == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인 기능을 준비하지 못했습니다. 다시 시도해 주세요.')),
        );
        return;
      }
      if (controller.hasSession) return;
      final route = MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: controller,
          builder: (_, _) => LoginScreen(controller: controller),
        ),
      );
      _loginRoute = route;
      await Navigator.of(context).push(route);
      if (identical(_loginRoute, route)) _loginRoute = null;
    } finally {
      _openingLogin = false;
    }
  }

  Future<void> _openNickname() async {
    final controller = _controller;
    if (controller == null ||
        controller.state != AuthGateState.signedInNeedsProfile ||
        _nicknameRoute != null) {
      return;
    }
    final route = MaterialPageRoute<void>(
      builder: (_) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => NicknameOnboardingScreen(controller: controller),
      ),
    );
    _nicknameRoute = route;
    await Navigator.of(context).push(route);
    if (identical(_nicknameRoute, route)) _nicknameRoute = null;
  }

  Future<void> _signOut() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.signOut();
    if (!mounted || !controller.hasSession || controller.message == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(controller.message!)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return widget.publicBuilder(
      context,
      () => unawaited(_openLogin()),
      controller?.hasSession == true ? _signOut : null,
      controller?.state == AuthGateState.signedInNeedsProfile
          ? () => unawaited(_openNickname())
          : null,
      controller?.hasSession == true && controller?.state == AuthGateState.error
          ? () => unawaited(controller!.retry())
          : null,
    );
  }

  @override
  void dispose() {
    _controller?.removeListener(_onAuthChanged);
    _controller?.dispose();
    super.dispose();
  }
}
