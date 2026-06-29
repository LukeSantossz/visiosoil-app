import 'dart:io';

import 'package:visiosoil_app/core/services/image_storage_service.dart';

/// Test double for [ImageStorageService] that records calls and returns a fixed
/// stable path, without touching the filesystem.
class FakeImageStorageService implements ImageStorageService {
  FakeImageStorageService({this.storedPath = '/stable/stored.jpg'});

  /// Path returned by [saveCapturedImage] on success.
  final String storedPath;

  /// When true, [saveCapturedImage] throws to simulate a copy failure.
  bool throwOnSave = false;

  /// Source paths passed to [saveCapturedImage], in call order.
  final List<String> savedSources = <String>[];

  @override
  Future<String> saveCapturedImage(
    File source, {
    required String recordUuid,
  }) async {
    savedSources.add(source.path);
    if (throwOnSave) {
      throw const FileSystemException('forced failure');
    }
    return storedPath;
  }
}
