import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';

/// Seam over the `google_sign_in` plugin so [GoogleAuthService] orchestration is
/// unit-testable. The concrete implementation is exercised on a device.
abstract class GoogleSignInGateway {
  /// Interactive sign-in. Returns null if the user cancels.
  Future<AuthAccount?> signIn();

  Future<void> signOut();

  /// Revokes the app's grant and signs out (SPEC 0113).
  Future<void> disconnect();
}

/// `google_sign_in`-backed [GoogleSignInGateway].
///
/// Signs in with Google's default scopes only — identity, email and profile —
/// and keeps no token (SPEC 0106). A feature that needs more, such as the Drive
/// backend (#55), requests its scope when it first needs it.
class GoogleSignInGatewayImpl implements GoogleSignInGateway {
  GoogleSignInGatewayImpl({GoogleSignIn? googleSignIn})
      : _googleSignIn = googleSignIn ?? GoogleSignIn();

  final GoogleSignIn _googleSignIn;

  /// The scopes requested at sign-in beyond Google's default ones.
  @visibleForTesting
  List<String> get scopes => _googleSignIn.scopes;

  @override
  Future<AuthAccount?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return null;
    return AuthAccount(email: account.email, displayName: account.displayName);
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();

  /// Revokes the grant through Play services' `revokeAccess`, which acts on
  /// the last signed-in account even after an app restart.
  @override
  Future<void> disconnect() => _googleSignIn.disconnect();
}
