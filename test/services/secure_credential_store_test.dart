// Tests for AuthSession serialization and SecureCredentialStore persistence.
//
// The store delegates secret storage to a [KeyValueSecureStorage]; tests use an
// in-memory fake so the real store logic (JSON encode/decode, key, clear) runs
// without the flutter_secure_storage platform channel.
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/auth/auth_session.dart';
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

void main() {
  group('AuthSession', () {
    test('auth_session_json_roundtrip', () {
      final session = AuthSession(
        email: 'agro@example.com',
        displayName: 'Agro Nomo',
        accessToken: 'token-abc',
        expiresAt: DateTime.utc(2026, 6, 15, 12),
      );

      final restored = AuthSession.fromJson(session.toJson());

      expect(restored.email, session.email);
      expect(restored.displayName, session.displayName);
      expect(restored.accessToken, session.accessToken);
      expect(restored.expiresAt, session.expiresAt);
    });

    test('auth_session_reports_expiry_against_clock', () {
      final session = AuthSession(
        email: 'a@b.com',
        displayName: null,
        accessToken: 't',
        expiresAt: DateTime.utc(2026, 6, 15, 12),
      );

      expect(session.isExpiredAt(DateTime.utc(2026, 6, 15, 13)), isTrue);
      expect(session.isExpiredAt(DateTime.utc(2026, 6, 15, 11)), isFalse);
      // Exactly at expiry counts as expired (conservative boundary).
      expect(session.isExpiredAt(DateTime.utc(2026, 6, 15, 12)), isTrue);
    });
  });

  group('SecureCredentialStore', () {
    late _InMemorySecureStorage storage;
    late SecureCredentialStore store;

    // The store's own key, repeated here because it is private. Tests seed this
    // key directly to reproduce a blob the store did not write itself: a partial
    // write, or a leftover from an older AuthSession shape.
    const sessionKey = 'auth_session';

    setUp(() {
      storage = _InMemorySecureStorage();
      store = SecureCredentialStore(storage);
    });

    test('secure_credential_store_persists_and_clears_session', () async {
      final session = AuthSession(
        email: 'agro@example.com',
        displayName: 'Agro Nomo',
        accessToken: 'token-abc',
        expiresAt: DateTime.utc(2026, 6, 15, 12),
      );

      await store.save(session);
      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.email, 'agro@example.com');
      expect(read.accessToken, 'token-abc');

      await store.clear();
      expect(await store.read(), isNull);
    });

    test('secure_credential_store_returns_null_when_empty', () async {
      expect(await store.read(), isNull);
    });

    test('secure_credential_store_returns_null_when_blob_is_malformed_json',
        () async {
      await storage.write(sessionKey, '{"email": "a@b.com", ');

      expect(await store.read(), isNull);
    });

    test('secure_credential_store_returns_null_when_blob_is_not_a_json_object',
        () async {
      // Valid JSON, but a top-level array: the cast to Map throws, not jsonDecode.
      await storage.write(sessionKey, '[1, 2, 3]');

      expect(await store.read(), isNull);
    });

    test(
        'secure_credential_store_returns_null_when_a_required_field_is_missing_or_mistyped',
        () async {
      // email absent and accessToken numeric: both fail the cast inside fromJson.
      await storage.write(
        sessionKey,
        '{"displayName": "A", "accessToken": 42, '
            '"expiresAt": "2026-06-15T12:00:00.000Z"}',
      );

      expect(await store.read(), isNull);
    });

    test('secure_credential_store_returns_null_when_expires_at_is_unparseable',
        () async {
      await storage.write(
        sessionKey,
        '{"email": "a@b.com", "displayName": null, "accessToken": "t", '
            '"expiresAt": "not-a-date"}',
      );

      expect(await store.read(), isNull);
    });

    test('secure_credential_store_deletes_the_bad_blob_so_the_next_read_is_empty',
        () async {
      await storage.write(sessionKey, 'garbage');

      await store.read();

      // The blob is gone from storage, not merely reported as absent, so the
      // next read does not repeat the failed decode.
      expect(await storage.read(sessionKey), isNull);
    });
  });
}
