import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/auth/auth_session.dart';
import 'package:visiosoil_app/core/services/auth/google_sign_in_gateway.dart';
import 'package:visiosoil_app/core/services/auth/secure_credential_store.dart';

/// [AuthService] backed by Google sign-in and secure local storage.
///
/// Holds the signed-in [AuthAccount] in memory and the [AuthSession] in the
/// [SecureCredentialStore]. Token refresh is delegated to the gateway's silent
/// re-authentication; a failed refresh clears the session.
class GoogleAuthService implements AuthService {
  GoogleAuthService(
    this._gateway,
    this._store, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final GoogleSignInGateway _gateway;
  final SecureCredentialStore _store;
  final DateTime Function() _clock;

  AuthAccount? _currentAccount;

  @override
  AuthAccount? get currentAccount => _currentAccount;

  @override
  Future<AuthAccount?> signIn() async {
    final result = await _gateway.signIn();
    if (result == null) return null;
    await _persist(result);
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

  @override
  Future<String?> accessToken() async {
    final session = await _store.read();
    if (session == null) return null;
    if (!session.isExpiredAt(_clock())) return session.accessToken;

    final refreshed = await _gateway.refresh();
    if (refreshed == null) {
      await _store.clear();
      _currentAccount = null;
      return null;
    }
    await _persist(refreshed);
    return refreshed.accessToken;
  }

  Future<void> _persist(GatewaySignInResult result) async {
    await _store.save(
      AuthSession(
        email: result.account.email,
        displayName: result.account.displayName,
        accessToken: result.accessToken,
        expiresAt: result.expiresAt,
      ),
    );
    _currentAccount = result.account;
  }

  AuthAccount _accountOf(AuthSession session) =>
      AuthAccount(email: session.email, displayName: session.displayName);
}
