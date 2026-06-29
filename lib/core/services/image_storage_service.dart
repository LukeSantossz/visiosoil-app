import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists captured images into stable, app-managed storage.
///
/// The capture flow hands over the transient file produced by `image_picker`
/// (in an OS cache directory that can be purged at any time). The repository
/// uses this service to copy that file into durable app storage before
/// persisting the record, so a saved record never points at a path the OS can
/// evict. Centralizing image-file persistence here keeps the file lifecycle in
/// one place (the future delete path, #71, will live alongside).
abstract class ImageStorageService {
  /// Copies [source] into stable app storage under a name derived from
  /// [recordUuid] and returns the absolute path of the stored copy.
  ///
  /// Throws a [FileSystemException] when [source] cannot be read or the copy
  /// fails; callers must not persist a record when this throws.
  Future<String> saveCapturedImage(File source, {required String recordUuid});
}

/// Default [ImageStorageService] backed by the application documents directory.
class DefaultImageStorageService implements ImageStorageService {
  /// [baseDirectory] resolves the root under which images are stored; it
  /// defaults to [getApplicationDocumentsDirectory] and is injectable so tests
  /// can target a temporary directory without platform channels.
  DefaultImageStorageService({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _baseDirectory;

  static const String _subdirectory = 'soil_images';

  @override
  Future<String> saveCapturedImage(
    File source, {
    required String recordUuid,
  }) async {
    // Guard against path traversal: recordUuid becomes a filename component, so
    // it must not contain path separators that could escape the target dir.
    if (recordUuid.contains('/') || recordUuid.contains(r'\')) {
      throw ArgumentError.value(
        recordUuid,
        'recordUuid',
        'must not contain path separators',
      );
    }

    final base = await _baseDirectory();
    final targetDir = Directory(p.join(base.path, _subdirectory));
    await targetDir.create(recursive: true);

    final sourceExtension = p.extension(source.path);
    final extension = sourceExtension.isEmpty ? '.jpg' : sourceExtension;
    final targetPath = p.join(targetDir.path, '$recordUuid$extension');

    final stored = await source.copy(targetPath);
    return stored.path;
  }
}
