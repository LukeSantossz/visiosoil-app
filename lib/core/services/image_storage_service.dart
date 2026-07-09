import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists captured images into stable, app-managed storage.
///
/// The capture flow hands over the transient file produced by `image_picker`
/// (in an OS cache directory that can be purged at any time). The repository
/// uses this service to copy that file into durable app storage before
/// persisting the record, so a saved record never points at a path the OS can
/// evict. Centralizing image-file persistence here keeps the file lifecycle —
/// both the copy on capture and the delete on record removal — in one place.
abstract class ImageStorageService {
  /// Copies [source] into stable app storage under a name derived from
  /// [recordUuid] and returns the absolute path of the stored copy.
  ///
  /// Throws a [FileSystemException] when [source] cannot be read or the copy
  /// fails; callers must not persist a record when this throws.
  Future<String> saveCapturedImage(File source, {required String recordUuid});

  /// Deletes the stored image at [imagePath].
  ///
  /// An already-absent file is an idempotent no-op; any other I/O failure
  /// throws a [FileSystemException] for the caller to handle.
  Future<void> deleteImage(String imagePath);
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

    // Exclusive write: never overwrite an existing image, so a UUID collision
    // cannot clobber another record's stored photo.
    if (await File(targetPath).exists()) {
      throw FileSystemException(
        'refusing to overwrite an existing stored image',
        targetPath,
      );
    }

    // JPEG captures carry EXIF (including GPS) that duplicates, uncontrolled,
    // the location the app records explicitly. Strip it losslessly at this
    // durable-storage boundary, keeping only the orientation tag: injectJpgExif
    // swaps the EXIF APP1 segment while leaving the entropy-coded scan intact, so
    // the stored pixels are byte-identical to the source. Orientation is kept
    // because Image.file honors it for display. A non-JPEG source (never produced
    // by camera-only capture) yields no EXIF and is copied through unchanged.
    final bytes = await source.readAsBytes();
    var outputBytes = bytes;
    // Only attempt an EXIF strip on data that starts with a JPEG SOI marker;
    // anything else (including short or malformed inputs) is copied as-is, so
    // the raw-copy contract holds for every non-JPEG source.
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      final sourceExif = img.decodeJpgExif(bytes);
      if (sourceExif != null) {
        final kept = img.ExifData();
        final orientation = sourceExif.imageIfd.orientation;
        if (orientation != null) {
          kept.imageIfd.orientation = orientation;
        }
        outputBytes = img.injectJpgExif(bytes, kept) ?? bytes;
      }
    }
    await File(targetPath).writeAsBytes(outputBytes, flush: true);
    return targetPath;
  }

  @override
  Future<void> deleteImage(String imagePath) async {
    try {
      await File(imagePath).delete();
    } on PathNotFoundException {
      // Already absent: deletion is idempotent, so a missing file is success.
    }
  }
}
