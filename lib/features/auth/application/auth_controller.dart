import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/auth_repository.dart';

enum AuthGateState {
  initializing,
  signedOut,
  signedInProfileLoading,
  signedInNeedsProfile,
  signedInReady,
  error,
}

enum NicknameValidationError { tooShort, tooLong, invalidCharacters, reserved }

const _nicknameCharacters = r'^[가-힣A-Za-z0-9_]+$';
const _reservedNickname = r'(admin|moderator|support|운영자|관리자|버거맵)';

NicknameValidationError? validateNickname(String value) {
  final nickname = value.trim();
  if (nickname.length < 2) return NicknameValidationError.tooShort;
  if (nickname.length > 20) return NicknameValidationError.tooLong;
  if (!RegExp(_nicknameCharacters).hasMatch(nickname)) {
    return NicknameValidationError.invalidCharacters;
  }
  if (RegExp(_reservedNickname).hasMatch(nickname.toLowerCase())) {
    return NicknameValidationError.reserved;
  }
  return null;
}

bool isValidEmail(String value) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());

class AuthController extends ChangeNotifier {
  AuthController(this._repository);

  final AuthRepository _repository;
  AuthGateState _state = AuthGateState.initializing;
  AuthUserProfile? _profile;
  StreamSubscription<String?>? _subscription;
  Future<void>? _profileLoadFuture;
  String? _resolvingUserId;
  int _generation = 0;
  bool _initialized = false;
  bool _disposed = false;
  bool _sendingMagicLink = false;
  bool _submittingNickname = false;
  bool _signingOut = false;
  bool _magicLinkSent = false;
  String? _message;

  AuthGateState get state => _state;
  bool get hasSession => _repository.currentUserId != null;
  AuthUserProfile? get profile => _profile;
  bool get sendingMagicLink => _sendingMagicLink;
  bool get submittingNickname => _submittingNickname;
  bool get signingOut => _signingOut;
  bool get magicLinkSent => _magicLinkSent;
  String? get message => _message;

  void initialize() {
    if (_initialized || _disposed) return;
    _initialized = true;
    _subscription = _repository.userChanges.listen(
      _handleUserChanged,
      onError: _handleAuthStreamError,
    );
    unawaited(_resolveUser(_repository.currentUserId));
  }

  Future<void> retry() => _resolveUser(_repository.currentUserId);

  Future<void> sendMagicLink(String email) async {
    if (_sendingMagicLink || _disposed) return;
    final normalized = email.trim().toLowerCase();
    if (!isValidEmail(normalized)) {
      _message = '올바른 이메일 주소를 입력해 주세요.';
      _magicLinkSent = false;
      _notify();
      return;
    }

    _sendingMagicLink = true;
    _magicLinkSent = false;
    _message = null;
    _notify();
    try {
      await _repository.sendMagicLink(normalized);
      if (_disposed) return;
      _magicLinkSent = true;
      _message = '로그인 링크를 보냈습니다. 이메일에서 링크를 열어 주세요.';
    } on AuthFlowException catch (error) {
      if (_disposed) return;
      _message = _messageFor(error.kind, operation: 'login');
    } on Object {
      if (_disposed) return;
      _message = _messageFor(AuthFailureKind.unknown, operation: 'login');
    } finally {
      if (!_disposed) {
        _sendingMagicLink = false;
        _notify();
      }
    }
  }

  Future<void> submitNickname(String value) async {
    if (_submittingNickname ||
        _disposed ||
        _state != AuthGateState.signedInNeedsProfile) {
      return;
    }
    final nickname = value.trim();
    final validationError = validateNickname(nickname);
    if (validationError != null) {
      _message = nicknameValidationMessage(validationError);
      _notify();
      return;
    }

    final expectedUserId = _repository.currentUserId;
    if (expectedUserId == null) {
      _setSignedOut();
      return;
    }
    final operationGeneration = _generation;
    _submittingNickname = true;
    _message = null;
    _notify();
    try {
      final profile = await _repository.createCurrentProfile(nickname);
      if (_disposed ||
          operationGeneration != _generation ||
          _repository.currentUserId != expectedUserId) {
        return;
      }
      if (profile.id != expectedUserId) {
        throw const AuthFlowException(AuthFailureKind.profile);
      }
      _profile = profile;
      _state = AuthGateState.signedInReady;
    } on AuthFlowException catch (error) {
      if (_disposed || operationGeneration != _generation) return;
      if (_repository.currentUserId == null) {
        _setSignedOut();
        return;
      }
      _message = _messageFor(error.kind, operation: 'profileCreate');
    } on Object {
      if (_disposed || operationGeneration != _generation) return;
      _message = _messageFor(
        AuthFailureKind.unknown,
        operation: 'profileCreate',
      );
    } finally {
      if (!_disposed && operationGeneration == _generation) {
        _submittingNickname = false;
        _notify();
      }
    }
  }

  Future<void> signOut() async {
    if (_signingOut || _disposed) return;
    _signingOut = true;
    _message = null;
    _notify();
    try {
      await _repository.signOut();
      if (_disposed) return;
      _setSignedOut();
    } on AuthFlowException catch (error) {
      if (_disposed) return;
      _message = _messageFor(error.kind, operation: 'logout');
    } on Object {
      if (_disposed) return;
      _message = _messageFor(AuthFailureKind.unknown, operation: 'logout');
    } finally {
      if (!_disposed) {
        _signingOut = false;
        _notify();
      }
    }
  }

  void _handleUserChanged(String? userId) {
    unawaited(_resolveUser(userId));
  }

  void _handleAuthStreamError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    ++_generation;
    _state = AuthGateState.error;
    _profile = null;
    _message = '로그인 상태를 확인하지 못했습니다. 다시 시도해 주세요.';
    _notify();
  }

  Future<void> _resolveUser(String? userId) {
    if (_disposed) return Future<void>.value();
    if (userId == null) {
      _setSignedOut();
      return Future<void>.value();
    }
    if (_state == AuthGateState.signedInReady && _profile?.id == userId) {
      return Future<void>.value();
    }
    if (_profileLoadFuture != null && _resolvingUserId == userId) {
      return _profileLoadFuture!;
    }

    final operationGeneration = ++_generation;
    _resolvingUserId = userId;
    _state = AuthGateState.signedInProfileLoading;
    _profile = null;
    _message = null;
    _magicLinkSent = false;
    _notify();

    late final Future<void> operation;
    operation = _loadProfile(userId, operationGeneration).whenComplete(() {
      if (identical(_profileLoadFuture, operation)) {
        _profileLoadFuture = null;
        _resolvingUserId = null;
      }
    });
    _profileLoadFuture = operation;
    return operation;
  }

  Future<void> _loadProfile(String userId, int operationGeneration) async {
    try {
      final profile = await _repository.fetchCurrentProfile();
      if (_disposed ||
          operationGeneration != _generation ||
          _repository.currentUserId != userId) {
        return;
      }
      _profile = profile;
      _state = profile == null
          ? AuthGateState.signedInNeedsProfile
          : AuthGateState.signedInReady;
    } on AuthFlowException catch (error) {
      if (_disposed || operationGeneration != _generation) return;
      if (_repository.currentUserId == null) {
        _setSignedOut();
        return;
      }
      _state = AuthGateState.error;
      _message = _messageFor(error.kind, operation: 'profileRead');
    } on Object {
      if (_disposed || operationGeneration != _generation) return;
      _state = AuthGateState.error;
      _message = _messageFor(AuthFailureKind.unknown, operation: 'profileRead');
    }
    _notify();
  }

  void _setSignedOut() {
    ++_generation;
    _profileLoadFuture = null;
    _resolvingUserId = null;
    _state = AuthGateState.signedOut;
    _profile = null;
    _message = null;
    _magicLinkSent = false;
    _submittingNickname = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

String nicknameValidationMessage(NicknameValidationError error) =>
    switch (error) {
      NicknameValidationError.tooShort => '닉네임은 2자 이상이어야 합니다.',
      NicknameValidationError.tooLong => '닉네임은 20자 이하여야 합니다.',
      NicknameValidationError.invalidCharacters =>
        '한글, 영문, 숫자, 밑줄(_)만 사용할 수 있습니다.',
      NicknameValidationError.reserved => '운영자를 나타내는 표현은 사용할 수 없습니다.',
    };

String _messageFor(AuthFailureKind kind, {required String operation}) {
  if (kind == AuthFailureKind.network) {
    return '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
  }
  if (operation == 'profileRead') {
    return '프로필을 확인하지 못했습니다. 다시 시도해 주세요.';
  }
  if (operation == 'profileCreate') {
    return '닉네임을 저장하지 못했습니다. 입력을 확인하고 다시 시도해 주세요.';
  }
  if (operation == 'logout') {
    return '로그아웃하지 못했습니다. 다시 시도해 주세요.';
  }
  return '로그인 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
}
