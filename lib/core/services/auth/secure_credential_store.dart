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
  /// malformed JSON; [TypeError] covers a non-object top-level value and a
  /// missing or mistyped field inside `fromJson`.
  ///
  /// A blob that decodes but carries fields the current shape lacks is saved
  /// back in the current shape. That is a session from before SPEC 0106, whose
  /// OAuth access token and expiry this removes while the user stays signed in.
  Future<AuthSession?> read() async {
    final raw = await _storage.read(_sessionKey);
    if (raw == null) return null;
    final Map<String, dynamic> stored;
    final AuthSession session;
    try {
      stored = jsonDecode(raw) as Map<String, dynamic>;
      session = AuthSession.fromJson(stored);
    } on FormatException catch (e) {
      await _discardCorruptSession(e);
      return null;
    } on TypeError catch (e) {
      await _discardCorruptSession(e);
      return null;
    }
    if (!setEquals(stored.keys.toSet(), session.toJson().keys.toSet())) {
      await save(session);
    }
    return session;
  }

  /// Describes a decode failure using only its type.
  ///
  /// The formatted exception must never be logged: `FormatException.toString()`
  /// echoes an excerpt of the string it failed to parse, and that string is the
  /// session blob. A blob saved before SPEC 0106 holds an OAuth access token, so
  /// a truncated one would put the token into device logs. The type alone
  /// distinguishes malformed JSON from a bad field, which is all the log needs.
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
