class AuthUserProfile {
  const AuthUserProfile({required this.id, required this.nickname});

  final String id;
  final String nickname;
}

enum AuthFailureKind { network, invalidInput, authentication, profile, unknown }

class AuthFlowException implements Exception {
  const AuthFlowException(this.kind);

  final AuthFailureKind kind;
}

abstract interface class AuthRepository {
  String? get currentUserId;

  Stream<String?> get userChanges;

  Future<void> sendMagicLink(String email);

  Future<AuthUserProfile?> fetchCurrentProfile();

  Future<AuthUserProfile> createCurrentProfile(String nickname);

  Future<void> signOut();
}
