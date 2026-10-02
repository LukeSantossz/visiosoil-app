import 'package:visiosoil_app/core/services/auth/auth_account.dart';

/// Optional authentication seam. Only the sync layer depends on it; the core
/// capture/history/offline paths never read it, so the app works unauthenticated.
abstract class AuthService {
  /// Interactive sign-in. Returns the account, or null if the user cancels.
  Future<AuthAccount?> signIn();

  /// Signs out and clears stored credentials.
  Future<void> signOut();

  /// Deletes the account from this app: clears the stored session, then
  /// revokes the app's grant with the provider (SPEC 0113). Throws
  /// [AccountNotRevokedException] when the session is gone but the revoke
  /// failed; any other error leaves the account in place.
  Future<void> deleteAccount();

  /// Restores a previously stored session without prompting. Returns the
  /// account, or null if there is none.
  Future<AuthAccount?> restoreSession();

  /// The account from the last successful sign-in/restore, or null.
  AuthAccount? get currentAccount;
}

/// The account left this device, but the provider did not confirm revoking the
/// app's grant (SPEC 0113). The user has to revoke it with the provider.
class AccountNotRevokedException implements Exception {
  const AccountNotRevokedException(this.cause);

  /// What the revoke failed with.
  final Object cause;

  @override
  String toString() => 'AccountNotRevokedException: $cause';
}
