import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_repository.dart';

const googleSignInScopes = <String>['email', 'profile'];

class GoogleAuthTokens {
  const GoogleAuthTokens({required this.idToken, required this.accessToken});

  final String idToken;
  final String accessToken;
}

typedef GoogleTokenLoader =
    Future<GoogleAuthTokens> Function(String serverClientId);

/// Uses the Android account picker; no browser OAuth redirect is involved.
class NativeGoogleTokenProvider {
  NativeGoogleTokenProvider() : _signIn = GoogleSignIn.instance;

  final GoogleSignIn _signIn;
  Future<void>? _initialization;

  Future<GoogleAuthTokens> authenticate(String serverClientId) async {
    if (serverClientId.trim().isEmpty) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }

    final initialization = _initialization ??= _signIn.initialize(
      serverClientId: serverClientId,
    );
    try {
      await initialization;
    } on Object {
      if (identical(_initialization, initialization)) _initialization = null;
      rethrow;
    }

    if (!_signIn.supportsAuthenticate()) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }
    final account = await _signIn.authenticate(scopeHint: googleSignInScopes);
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }

    final authorization =
        await account.authorizationClient.authorizationForScopes(
          googleSignInScopes,
        ) ??
        await account.authorizationClient.authorizeScopes(googleSignInScopes);
    if (authorization.accessToken.isEmpty) {
      throw const AuthFlowException(AuthFailureKind.authentication);
    }
    return GoogleAuthTokens(
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }
}
