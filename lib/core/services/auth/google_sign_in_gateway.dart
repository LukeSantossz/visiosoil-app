import 'package:google_sign_in/google_sign_in.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';

/// Result of an interactive or silent Google authentication.
class GatewaySignInResult {
  const GatewaySignInResult({
    required this.account,
    required this.accessToken,
    required this.expiresAt,
  });

  final AuthAccount account;
  final String accessToken;
  final DateTime expiresAt;
}

/// Seam over the `google_sign_in` plugin so [GoogleAuthService] orchestration is
/// unit-testable. The concrete implementation is exercised on a device.
abstract class GoogleSignInGateway {
  /// Interactive sign-in. Returns null if the user cancels.
  Future<GatewaySignInResult?> signIn();

  /// Silent re-authentication for an existing grant. Returns null if no session
  /// can be restored without user interaction.
  Future<GatewaySignInResult?> refresh();

  Future<void> signOut();
}

/// `google_sign_in`-backed [GoogleSignInGateway].
///
/// Requests the Drive scope needed by the sync backend (#55). The access token
/// lifetime is not reported by the plugin, so a conservative validity window is
/// applied; an expired token triggers another silent refresh.
class GoogleSignInGatewayImpl implements GoogleSignInGateway {
  GoogleSignInGatewayImpl({
    GoogleSignIn? googleSignIn,
    Duration tokenValidity = const Duration(minutes: 50),
    DateTime Function() clock = DateTime.now,
  })  : _googleSignIn = googleSignIn ??
            GoogleSignIn(scopes: const [_driveScope]),
        _tokenValidity = tokenValidity,
        _clock = clock;

  /// Narrowest Drive scope that lets #55 store its own app data.
  static const _driveScope = 'https://www.googleapis.com/auth/drive.file';

  final GoogleSignIn _googleSignIn;
  final Duration _tokenValidity;
  final DateTime Function() _clock;

  @override
  Future<GatewaySignInResult?> signIn() =>
      _toResult(_googleSignIn.signIn());

  @override
  Future<GatewaySignInResult?> refresh() =>
      _toResult(_googleSignIn.signInSilently());

  @override
  Future<void> signOut() => _googleSignIn.signOut();

  Future<GatewaySignInResult?> _toResult(
    Future<GoogleSignInAccount?> pending,
  ) async {
    final account = await pending;
    if (account == null) return null;
    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) return null;
    return GatewaySignInResult(
      account: AuthAccount(
        email: account.email,
        displayName: account.displayName,
      ),
      accessToken: token,
      expiresAt: _clock().toUtc().add(_tokenValidity),
    );
  }
}
