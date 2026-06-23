import 'dart:convert';

import 'package:visiosoil_app/core/services/auth/auth_session.dart';
import 'package:visiosoil_app/core/services/auth/key_value_secure_storage.dart';

/// Persists the [AuthSession] as JSON in secure storage under a single key.
class SecureCredentialStore {
  SecureCredentialStore(this._storage);

  final KeyValueSecureStorage _storage;

  static const _sessionKey = 'auth_session';

  Future<void> save(AuthSession session) =>
      _storage.write(_sessionKey, jsonEncode(session.toJson()));

  Future<AuthSession?> read() async {
    final raw = await _storage.read(_sessionKey);
    if (raw == null) return null;
    return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> clear() => _storage.delete(_sessionKey);
}
