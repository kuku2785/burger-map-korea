import 'dart:async';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';
import 'native_google_token_provider.dart';

const supabaseProfileSelectColumns = 'id,nickname';
const burgerMapAuthRedirectUrl = 'com.burgermapkorea.app://login-callback/';

Map<String, Object> buildProfileInsertPayload({
  required String userId,
  required String nickname,
}) => <String, Object>{'id': userId, 'nickname': nickname};

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(
    this._client, {
    required this.googleServerClientId,
    GoogleTokenLoader? googleTokenLoader,
  }) : _googleTokenLoader =
           googleTokenLoader ?? NativeGoogleTokenProvider().authenticate;

  final SupabaseClient _client;
  final String googleServerClientId;
  final GoogleTokenLoader _googleTokenLoader;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Stream<String?> get userChanges =>
      _client.auth.onAuthStateChange.map((data) => data.session?.user.id);

  @override
  Future<void> sendMagicLink(String email) async {
    try {
      await _client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: burgerMapAuthRedirectUrl,
        shouldCreateUser: true,
      );
    } on AuthRetryableFetchException {
      throw const AuthFlowException(AuthFailureKind.network);
    } on AuthException {
      throw const AuthFlowException(AuthFailureKind.authentication);
    } on Object {
      throw const AuthFlowException(AuthFailureKind.unknown);
    }
  }

  @override
  Future<void> signInWithGoogle() async {
    try {
      final tokens = await _googleTokenLoader(googleServerClientId);
      if (tokens.idToken.isEmpty || tokens.accessToken.isEmpty) {
        throw const AuthFlowException(AuthFailureKind.authentication);
      }
      final result = await _client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: tokens.idToken,
        accessToken: tokens.accessToken,
      );
      if (result.session == null || _client.auth.currentSession == null) {
        throw const AuthFlowException(AuthFailureKind.authentication);
      }
    } on GoogleSignInException catch (error) {
      throw AuthFlowException(
        error.code == GoogleSignInExceptionCode.canceled
            ? AuthFailureKind.canceled
            : AuthFailureKind.authentication,
      );
    } on AuthRetryableFetchException {
      throw const AuthFlowException(AuthFailureKind.network);
    } on AuthException {
      throw const AuthFlowException(AuthFailureKind.authentication);
    } on AuthFlowException {
      rethrow;
    } on Object {
      throw const AuthFlowException(AuthFailureKind.unknown);
    }
  }

  @override
  Future<AuthUserProfile?> fetchCurrentProfile() async {
    final userId = currentUserId;
    if (userId == null) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }

    try {
      final row = await _client
          .from('profiles')
          .select(supabaseProfileSelectColumns)
          .eq('id', userId)
          .maybeSingle();
      if (row == null) return null;
      return _mapProfile(row, expectedUserId: userId);
    } on PostgrestException {
      throw const AuthFlowException(AuthFailureKind.profile);
    } on AuthFlowException {
      rethrow;
    } on Object {
      throw const AuthFlowException(AuthFailureKind.network);
    }
  }

  @override
  Future<AuthUserProfile> createCurrentProfile(String nickname) async {
    final userId = currentUserId;
    if (userId == null) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }

    try {
      await _client
          .from('profiles')
          .insert(
            buildProfileInsertPayload(userId: userId, nickname: nickname),
          );
    } on PostgrestException catch (error) {
      if (error.code != '23505') {
        throw const AuthFlowException(AuthFailureKind.profile);
      }
      // A concurrent successful INSERT is recoverable. Always re-read through
      // the user's normal RLS path instead of weakening the database contract.
    } on Object {
      throw const AuthFlowException(AuthFailureKind.network);
    }

    final profile = await fetchCurrentProfile();
    if (profile == null) {
      throw const AuthFlowException(AuthFailureKind.profile);
    }
    return profile;
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } on AuthRetryableFetchException {
      throw const AuthFlowException(AuthFailureKind.network);
    } on AuthException {
      throw const AuthFlowException(AuthFailureKind.authentication);
    } on Object {
      throw const AuthFlowException(AuthFailureKind.unknown);
    }
  }
}

AuthUserProfile _mapProfile(
  Map<String, dynamic> row, {
  required String expectedUserId,
}) {
  final id = row['id'];
  final nickname = row['nickname'];
  if (id != expectedUserId || nickname is! String || nickname.isEmpty) {
    throw const AuthFlowException(AuthFailureKind.profile);
  }
  return AuthUserProfile(id: expectedUserId, nickname: nickname);
}
