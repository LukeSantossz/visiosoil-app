import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal secret key-value storage seam.
///
/// Abstracted so [SecureCredentialStore] logic is unit-testable with an
/// in-memory fake; the real implementation delegates to the platform secure
/// enclave (Android Keystore / iOS Keychain) via `flutter_secure_storage`.
abstract class KeyValueSecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// `flutter_secure_storage`-backed [KeyValueSecureStorage]. Thin plugin wrapper;
/// exercised on a device, not in `flutter test`.
class FlutterKeyValueSecureStorage implements KeyValueSecureStorage {
  FlutterKeyValueSecureStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
