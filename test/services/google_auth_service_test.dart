// Tests for GoogleAuthService orchestration: sign-in/out, session restore, and
// access-token refresh — all against fakes for the plugin gateway and storage,
// so no platform channel is touched.
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
  GatewaySignInResult? signInResult;
  GatewaySignInResult? refreshResult;
  int signOutCalls = 0;

  /// When set, [signOut] throws it, standing in for a remote revoke failure
  /// (network down, token already invalid) that must not strand local state.
  Object? signOutError;

  @override
  Future<GatewaySignInResult?> signIn() async => signInResult;

  @override
  Future<GatewaySignInResult?> refresh() async => refreshResult;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    final error = signOutError;
    if (error != null) throw error;
  }
}

GatewaySignInResult _result({
  String email = 'agro@example.com',
  String token = 'token-1',
  DateTime? expiresAt,
}) =>
    GatewaySignInResult(
      account: AuthAccount(email: email, displayName: 'Agro'),
      accessToken: token,
      expiresAt: expiresAt ?? DateTime.utc(2026, 6, 15, 13),
    );

void main() {
  group('GoogleAuthService', () {
    late _FakeGateway gateway;
    late _InMemorySecureStorage storage;
    late SecureCredentialStore store;
    late GoogleAuthService service;
    var now = DateTime.utc(2026, 6, 15, 12);

    // The store's own key, repeated here because it is private.
    const sessionKey = 'auth_session';

    setUp(() {
      now = DateTime.utc(2026, 6, 15, 12);
      gateway = _FakeGateway();
      storage = _InMemorySecureStorage();
      store = SecureCredentialStore(storage);
      service = GoogleAuthService(gateway, store, clock: () => now);
    });

    test('sign_in_persists_session_and_sets_current_account', () async {
      gateway.signInResult = _result();

      final account = await service.signIn();

      expect(account?.email, 'agro@example.com');
      expect(service.currentAccount?.email, 'agro@example.com');
      expect((await store.read())?.accessToken, 'token-1');
    });

    test('sign_in_returns_null_when_gateway_cancelled', () async {
      gateway.signInResult = null;

      final account = await service.signIn();

      expect(account, isNull);
      expect(service.currentAccount, isNull);
      expect(await store.read(), isNull);
    });

    test('sign_out_clears_session_and_current_account', () async {
      gateway.signInResult = _result();
      await service.signIn();

      await service.signOut();

      expect(service.currentAccount, isNull);
      expect(await store.read(), isNull);
      expect(gateway.signOutCalls, 1);
    });

    test('sign_out_clears_local_credentials_even_when_remote_revoke_throws',
        () async {
      gateway.signInResult = _result();
      await service.signIn();
      gateway.signOutError = Exception('revoke failed');

      // The remote error still surfaces to the caller...
      await expectLater(service.signOut(), throwsA(isA<Exception>()));

      // ...but the persisted session and in-memory account are already gone,
      // so a lost device does not retain a usable OAuth token.
      expect(await store.read(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('sign_out_propagates_and_keeps_account_when_local_clear_fails',
        () async {
      gateway.signInResult = _result();
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
        AuthSession(
          email: 'agro@example.com',
          displayName: 'Agro',
          accessToken: 'token-1',
          expiresAt: DateTime.utc(2026, 6, 15, 13),
        ),
      );

      final account = await service.restoreSession();

      expect(account?.email, 'agro@example.com');
      expect(service.currentAccount?.email, 'agro@example.com');
    });

    test('restore_session_returns_null_when_empty', () async {
      expect(await service.restoreSession(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('access_token_returns_stored_when_not_expired', () async {
      gateway.signInResult = _result(token: 'token-1');
      await service.signIn();

      final token = await service.accessToken();

      expect(token, 'token-1');
      expect(gateway.refreshResult, isNull); // refresh not consulted
    });

    test('expired_token_triggers_silent_refresh_via_gateway', () async {
      gateway.signInResult = _result(
        token: 'token-1',
        expiresAt: DateTime.utc(2026, 6, 15, 12, 30),
      );
      await service.signIn();
      now = DateTime.utc(2026, 6, 15, 14); // past expiry
      gateway.refreshResult = _result(
        token: 'token-2',
        expiresAt: DateTime.utc(2026, 6, 15, 15),
      );

      final token = await service.accessToken();

      expect(token, 'token-2');
      expect((await store.read())?.accessToken, 'token-2');
    });

    test('access_token_clears_session_when_refresh_fails', () async {
      gateway.signInResult = _result(
        token: 'token-1',
        expiresAt: DateTime.utc(2026, 6, 15, 12, 30),
      );
      await service.signIn();
      now = DateTime.utc(2026, 6, 15, 14);
      gateway.refreshResult = null; // silent refresh yields nothing

      final token = await service.accessToken();

      expect(token, isNull);
      expect(await store.read(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('restore_session_returns_null_on_a_corrupt_blob', () async {
      await storage.write(sessionKey, 'not-json-at-all');

      expect(await service.restoreSession(), isNull);
      expect(service.currentAccount, isNull);
    });

    test('access_token_returns_null_on_a_corrupt_blob', () async {
      await storage.write(sessionKey, 'not-json-at-all');

      // Degrades to signed-out rather than throwing on every call, which is what
      // the sync layer needs from a token source.
      expect(await service.accessToken(), isNull);
    });
  });
}
