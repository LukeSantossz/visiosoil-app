import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/auth/google_auth_service.dart';
import 'package:visiosoil_app/core/services/auth/google_sign_in_gateway.dart';
import 'package:visiosoil_app/core/services/auth/key_value_secure_storage.dart';
import 'package:visiosoil_app/core/services/auth/secure_credential_store.dart';

/// Sign-in state surfaced to the UI and the (future) sync layer.
class AuthState {
  const AuthState.signedOut() : account = null;
  const AuthState.signedIn(AuthAccount this.account);

  final AuthAccount? account;

  bool get isSignedIn => account != null;
}

/// The [AuthService] singleton. Overridden in tests with a fake.
final authServiceProvider = Provider<AuthService>((ref) {
  return GoogleAuthService(
    GoogleSignInGatewayImpl(),
    SecureCredentialStore(FlutterKeyValueSecureStorage()),
  );
});

/// Observable auth state. Restores any stored session on build; never blocks
/// core app use (a missing/failed session simply resolves to signed-out).
final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    // The store already absorbs an undecodable blob; this guards the rest of the
    // restore path (secure-storage platform failures) so the signed-out fallback
    // this provider documents holds instead of surfacing as AsyncError.
    try {
      final account = await ref.watch(authServiceProvider).restoreSession();
      return _stateFor(account);
    } on Exception catch (e) {
      developer.log('session restore failed: $e', name: 'AuthNotifier');
      return const AuthState.signedOut();
    }
  }

  Future<void> signIn() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final account = await ref.read(authServiceProvider).signIn();
      return _stateFor(account);
    });
  }

  Future<void> signOut() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(authServiceProvider).signOut();
      return const AuthState.signedOut();
    });
  }

  AuthState _stateFor(AuthAccount? account) => account == null
      ? const AuthState.signedOut()
      : AuthState.signedIn(account);
}
