import 'dart:io';

import 'package:visiosoil_app/core/services/image_storage_service.dart';

/// Test double for [ImageStorageService] that records calls and returns a fixed
/// stable path, without touching the filesystem.
class FakeImageStorageService implements ImageStorageService {
  FakeImageStorageService({
    this.storedPath = '/stable/stored.jpg',
    this.uniqueStoredPaths = false,
  });

  /// Path returned by [saveCapturedImage] on success when [uniqueStoredPaths]
  /// is false.
  final String storedPath;

  /// When true, [saveCapturedImage] returns a per-record path derived from the
  /// UUID, so distinct records get distinct stored paths.
  final bool uniqueStoredPaths;

  /// When true, [saveCapturedImage] throws to simulate a copy failure.
  bool throwOnSave = false;

  /// When true, every [deleteImage] call throws to simulate an I/O failure.
  bool throwOnDelete = false;

  /// [deleteImage] throws only for these specific paths (selective failure).
  final Set<String> throwDeleteForPaths = <String>{};

  /// Source paths passed to [saveCapturedImage], in call order.
  final List<String> savedSources = <String>[];

  /// Paths passed to [deleteImage], in call order.
  final List<String> deletedPaths = <String>[];

  @override
  Future<String> saveCapturedImage(
    File source, {
    required String recordUuid,
  }) async {
    savedSources.add(source.path);
    if (throwOnSave) {
      throw const FileSystemException('forced failure');
    }
    return uniqueStoredPaths ? '/stable/$recordUuid.jpg' : storedPath;
  }

  @override
  Future<void> deleteImage(String imagePath) async {
    deletedPaths.add(imagePath);
    if (throwOnDelete || throwDeleteForPaths.contains(imagePath)) {
      throw const FileSystemException('forced delete failure');
    }
  }
}
