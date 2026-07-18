import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'package:visiosoil_app/core/services/auth/auth_session.dart';
import 'package:visiosoil_app/core/services/auth/key_value_secure_storage.dart';

/// Persists the [AuthSession] as JSON in secure storage under a single key.
class SecureCredentialStore {
  SecureCredentialStore(this._storage);

  final KeyValueSecureStorage _storage;

  static const _sessionKey = 'auth_session';

  Future<void> save(AuthSession session) =>
      _storage.write(_sessionKey, jsonEncode(session.toJson()));

  /// Reads the persisted session, or `null` when there is none.
  ///
  /// A blob that cannot be decoded — a partial write, or a leftover from an
  /// older [AuthSession] shape — is treated as no session and deleted, so the
  /// next read does not repeat the same failed decode. [FormatException] covers
  /// malformed JSON and an unparseable expiry; [TypeError] covers a non-object
  /// top-level value and a missing or mistyped field inside `fromJson`.
  Future<AuthSession?> read() async {
    final raw = await _storage.read(_sessionKey);
    if (raw == null) return null;
    try {
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException catch (e) {
      await _discardCorruptSession(e);
      return null;
    } on TypeError catch (e) {
      await _discardCorruptSession(e);
      return null;
    }
  }

  /// Describes a decode failure using only its type.
  ///
  /// The formatted exception must never be logged: `FormatException.toString()`
  /// echoes an excerpt of the string it failed to parse, and that string is the
  /// session blob, so a truncated write would put the OAuth access token into
  /// device logs. The type alone distinguishes malformed JSON from a bad field,
  /// which is all the log needs.
  @visibleForTesting
  static String describeDecodeFailure(Object error) =>
      'discarding undecodable session blob (${error.runtimeType})';

  Future<void> _discardCorruptSession(Object error) async {
    developer.log(
      describeDecodeFailure(error),
      name: 'SecureCredentialStore',
    );
    await _storage.delete(_sessionKey);
  }

  Future<void> clear() => _storage.delete(_sessionKey);
}
