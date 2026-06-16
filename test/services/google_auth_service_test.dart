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

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

class _FakeGateway implements GoogleSignInGateway {
  GatewaySignInResult? signInResult;
  GatewaySignInResult? refreshResult;
  int signOutCalls = 0;

  @override
  Future<GatewaySignInResult?> signIn() async => signInResult;

  @override
  Future<GatewaySignInResult?> refresh() async => refreshResult;

  @override
  Future<void> signOut() async => signOutCalls++;
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
    late SecureCredentialStore store;
    late GoogleAuthService service;
    var now = DateTime.utc(2026, 6, 15, 12);

    setUp(() {
      now = DateTime.utc(2026, 6, 15, 12);
      gateway = _FakeGateway();
      store = SecureCredentialStore(_InMemorySecureStorage());
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
  });
}
