import 'package:visiosoil_app/core/services/auth/auth_account.dart';

/// Optional authentication seam. Only the sync layer depends on it; the core
/// capture/history/offline paths never read it, so the app works unauthenticated.
abstract class AuthService {
  /// Interactive sign-in. Returns the account, or null if the user cancels.
  Future<AuthAccount?> signIn();

  /// Signs out and clears stored credentials.
  Future<void> signOut();

  /// Restores a previously stored session without prompting. Returns the
  /// account, or null if there is none.
  Future<AuthAccount?> restoreSession();

  /// Returns a valid access token for the remote backend, refreshing silently
  /// if the stored one expired. Null if there is no usable session.
  Future<String?> accessToken();

  /// The account from the last successful sign-in/restore, or null.
  AuthAccount? get currentAccount;
}
