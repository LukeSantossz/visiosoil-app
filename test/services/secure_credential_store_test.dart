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
    late SecureCredentialStore store;

    setUp(() {
      store = SecureCredentialStore(_InMemorySecureStorage());
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
  });
}
