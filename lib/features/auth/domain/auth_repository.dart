class AuthUserProfile {
  const AuthUserProfile({required this.id, required this.nickname});

  final String id;
  final String nickname;
}

enum AuthFailureKind {
  network,
  invalidInput,
  authentication,
  canceled,
  profile,
  accountDeletionCleanup,
  unknown,
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.kind);

  final AuthFailureKind kind;
}

abstract interface class AuthRepository {
  String? get currentUserId;

  Stream<String?> get userChanges;

  Future<void> sendMagicLink(String email);

  Future<void> signInWithGoogle();

  Future<AuthUserProfile?> fetchCurrentProfile();

  Future<AuthUserProfile> createCurrentProfile(String nickname);

  Future<void> signOut();

  /// Deletes only the caller account and clears its local session on success.
  /// A failed/ambiguous server response must preserve the local session.
  Future<void> deleteAccount();
}
