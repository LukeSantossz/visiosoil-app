import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/auth/auth_session.dart';
import 'package:visiosoil_app/core/services/auth/google_sign_in_gateway.dart';
import 'package:visiosoil_app/core/services/auth/secure_credential_store.dart';

/// [AuthService] backed by Google sign-in and secure local storage.
///
/// Holds the signed-in [AuthAccount] in memory and the [AuthSession] in the
/// [SecureCredentialStore].
class GoogleAuthService implements AuthService {
  GoogleAuthService(this._gateway, this._store);

  final GoogleSignInGateway _gateway;
  final SecureCredentialStore _store;

  AuthAccount? _currentAccount;

  @override
  AuthAccount? get currentAccount => _currentAccount;

  @override
  Future<AuthAccount?> signIn() async {
    final account = await _gateway.signIn();
    if (account == null) return null;
    await _store.save(
      AuthSession(email: account.email, displayName: account.displayName),
    );
    _currentAccount = account;
    return _currentAccount;
  }

  @override
  Future<void> signOut() async {
    // Clear local credentials first so a throwing remote revoke can never leave
    // a usable session on the device; the remote error still propagates so the
    // caller can report it.
    await _store.clear();
    _currentAccount = null;
    await _gateway.signOut();
  }

  @override
  Future<AuthAccount?> restoreSession() async {
    final session = await _store.read();
    if (session == null) return null;
    _currentAccount = _accountOf(session);
    return _currentAccount;
  }

  AuthAccount _accountOf(AuthSession session) =>
      AuthAccount(email: session.email, displayName: session.displayName);
}
