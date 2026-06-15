import 'dart:io';

import 'package:share_plus/share_plus.dart';
import 'package:visiosoil_app/core/services/share_content_builder.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Shares a [SoilRecord] through the native share sheet.
///
/// Composes a PNG card from the record's photo and metadata, writes it to a
/// temporary file, and hands it to `share_plus` with a text caption. Falls back
/// to sharing the caption alone when the photo file is missing.
class ShareService {
  const ShareService();

  Future<void> shareRecord(SoilRecord record) async {
    final caption = ShareContentBuilder.caption(record);
    final photoFile = File(record.imagePath);

    if (!await photoFile.exists()) {
      await SharePlus.instance.share(ShareParams(text: caption));
      return;
    }

    final photoBytes = await photoFile.readAsBytes();
    final cardBytes = await ShareContentBuilder.composeCard(record, photoBytes);

    final tempDir = await Directory.systemTemp.createTemp('visiosoil_share');
    final cardFile = File(
      '${tempDir.path}/visiosoil_${record.id ?? 'record'}.png',
    );
    await cardFile.writeAsBytes(cardBytes);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(cardFile.path)], text: caption),
    );
  }
}
