// Tests for GoogleAuthService orchestration: sign-in/out and session restore —
// all against fakes for the plugin gateway and storage, so no platform channel
// is touched.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_session.dart';
import 'package:visiosoil_app/core/services/auth/google_auth_service.dart';
import 'package:visiosoil_app/core/services/auth/google_sign_in_gateway.dart';
import 'package:visiosoil_app/core/services/auth/key_value_secure_storage.dart';
import 'package:visiosoil_app/core/services/auth/secure_credential_store.dart';

class _InMemorySecureStorage implements KeyValueSecureStorage {
  final Map<String, String> _data = {};

  /// When set, [delete] throws it, standing in for a secure-storage delete that
  /// fails at the platform boundary (Keystore/Keychain error).
  Object? deleteError;

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async {
    final error = deleteError;
    if (error != null) throw error;
    _data.remove(key);
  }
}

class _FakeGateway implements GoogleSignInGateway {
  AuthAccount? signInResult;
  int signOutCalls = 0;

  /// When set, [signOut] throws it, standing in for a remote revoke failure
  /// (network down, token already invalid) that must not strand local state.
  Object? signOutError;

  @override
  Future<AuthAccount?> signIn() async => signInResult;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
  }
}

AuthAccount _account() =>
    const AuthAccount(email: 'agro@example.com', displayName: 'Agro');

void main() {
  group('GoogleAuthService', () {
    late _FakeGateway gateway;
    late _InMemorySecureStorage storage;
    late SecureCredentialStore store;
    late GoogleAuthService service;

    // The store's own key, repeated here because it is private.
    const sessionKey = 'auth_session';

    setUp(() {
      gateway = _FakeGateway();
      storage = _InMemorySecureStorage();
      store = SecureCredentialStore(storage);
      service = GoogleAuthService(gateway, store);
    });

    test('sign_in_persists_the_account_and_no_token', () async {
      gateway.signInResult = _account();

      final account = await service.signIn();

      expect(account?.email, 'agro@example.com');
      expect(service.currentAccount?.email, 'agro@example.com');
      // SPEC 0106: sign-in asks for identity only, so there is no token to keep.
      final stored =
          jsonDecode((await storage.read(sessionKey))!) as Map<String, dynamic>;
      expect(stored, {'email': 'agro@example.com', 'displayName': 'Agro'});
    });

    test('sign_in_returns_null_when_gateway_cancelled', () async {
      gateway.signInResult = null;

      final account = await service.signIn();

      expect(account, isNull);
      expect(service.currentAccount, isNull);
      expect(await store.read(), isNull);
    });

    test('sign_out_clears_session_and_current_account', () async {
      gateway.signInResult = _account();
      await service.signIn();

      await service.signOut();

      expect(service.currentAccount, isNull);
      expect(await store.read(), isNull);
      expect(gateway.signOutCalls, 1);
    });

    test('sign_out_clears_local_credentials_even_when_remote_revoke_throws',
        () async {
      gateway.signInResult = _account();
      await service.signIn();
      gateway.signOutError = Exception('revoke failed');

      // The remote error still surfaces to the caller...
      await expectLater(service.signOut(), throwsA(isA<Exception>()));

      // ...but the persisted session and in-memory account are already gone,
      // so a lost device does not stay signed in.
      expect(await store.read(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('sign_out_propagates_and_keeps_account_when_local_clear_fails',
        () async {
      gateway.signInResult = _account();
      await service.signIn();
      storage.deleteError = Exception('secure storage delete failed');

      // A local-clear failure is a real sign-out failure, so it propagates...
      await expectLater(service.signOut(), throwsA(isA<Exception>()));

      // ...the remote revoke is never attempted (clear runs first), and the
      // account stays present because the credentials could not be removed —
      // the UI must not then report signed-out.
      expect(gateway.signOutCalls, 0);
      expect(service.currentAccount, isNotNull);
    });

    test('restore_session_returns_account_when_stored', () async {
      await store.save(
        const AuthSession(email: 'agro@example.com', displayName: 'Agro'),
      );

      final account = await service.restoreSession();

      expect(account?.email, 'agro@example.com');
      expect(service.currentAccount?.email, 'agro@example.com');
    });

    test('restore_session_returns_null_when_empty', () async {
      expect(await service.restoreSession(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('restore_session_returns_null_on_a_corrupt_blob', () async {
      await storage.write(sessionKey, 'not-json-at-all');

      expect(await service.restoreSession(), isNull);
      expect(service.currentAccount, isNull);
    });
  });
}
