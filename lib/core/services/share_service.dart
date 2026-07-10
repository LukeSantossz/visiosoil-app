import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';
import 'package:visiosoil_app/core/services/share_content_builder.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Shares a [SoilRecord] through the native share sheet.
///
/// Composes a PNG card from the record's photo and metadata, writes it to a
/// temporary file, and hands it to `share_plus` with a text caption. Falls back
/// to sharing the caption alone when the photo file is missing or its bytes
/// cannot be decoded.
class ShareService {
  const ShareService();

  Future<void> shareRecord(
    SoilRecord record, {
    bool includeLocation = false,
  }) async {
    final caption =
        ShareContentBuilder.caption(record, includeLocation: includeLocation);
    final photoFile = File(record.imagePath);

    if (!await photoFile.exists()) {
      await SharePlus.instance.share(ShareParams(text: caption));
      return;
    }

    final photoBytes = await photoFile.readAsBytes();

    final Uint8List cardBytes;
    try {
      cardBytes = await ShareContentBuilder.composeCard(
        record,
        photoBytes,
        includeLocation: includeLocation,
      );
    } on Exception catch (e) {
      // Present but undecodable photo (corrupt, truncated, or empty): degrade
      // to the text-only caption, mirroring the missing-file path above.
      // `on Exception` scopes this to decode failures; a genuine engine Error
      // is not a recoverable share problem and deliberately propagates.
      developer.log(
        'Failed to compose share card; sharing caption only: $e',
        name: 'ShareService',
      );
      await SharePlus.instance.share(ShareParams(text: caption));
      return;
    }

    final tempDir = await Directory.systemTemp.createTemp('visiosoil_share');
    try {
      final cardFile = File(
        '${tempDir.path}/visiosoil_${record.id ?? 'record'}.png',
      );
      await cardFile.writeAsBytes(cardBytes);

      await SharePlus.instance.share(
        ShareParams(files: [XFile(cardFile.path)], text: caption),
      );
    } finally {
      // Delete the card and its directory after the share sheet has read them,
      // whether the share succeeded, failed, or was cancelled. A filesystem
      // cleanup failure is logged rather than masking the share outcome; any
      // other error surfaces as an unexpected fault.
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException catch (e) {
        developer.log(
          'Failed to delete temporary share directory: $e',
          name: 'ShareService',
        );
      }
    }
  }
}
