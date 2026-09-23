import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_repository.dart';

const supabaseProfileSelectColumns = 'id,nickname';
const burgerMapAuthRedirectUrl = 'com.burgermapkorea.app://login-callback/';

Map<String, Object> buildProfileInsertPayload({
  required String userId,
  required String nickname,
}) => <String, Object>{'id': userId, 'nickname': nickname};

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

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
