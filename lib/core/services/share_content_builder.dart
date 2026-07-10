import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Builds the shareable content for a [SoilRecord]: a plain-text caption and a
/// composed PNG card (the photo with a metadata footer).
///
/// Pure and free of file I/O and platform calls so it can be unit-tested.
/// [ShareService] handles loading the photo, writing the temp file, and the
/// native share sheet.
abstract final class ShareContentBuilder {
  /// Card width in pixels; the photo is scaled to it and the footer spans it.
  static const double _cardWidth = 1080;

  /// Padding around the footer text, in pixels.
  static const double _footerPadding = 32;

  /// Plain-text caption with one metadata field per line; fields that are
  /// missing or unavailable are omitted.
  ///
  /// Location (address and coordinates) is disclosed only when
  /// [includeLocation] is true, so a default share does not leak a client's
  /// precise field location; the caller opts in per share.
  static String caption(SoilRecord record, {bool includeLocation = false}) {
    final lines = <String>['VisioSoil — análise de solo'];
    if (record.hasClassification) {
      final confidence = record.confidenceScore != null
          ? ' (${record.formattedConfidence})'
          : '';
      lines.add('Classe: ${record.displayTextureClass}$confidence');
    }
    if (includeLocation) {
      if (record.hasValidAddress) {
        lines.add('Local: ${record.address}');
      }
      if (record.hasCoordinates) {
        lines.add('Coordenadas: ${record.formattedCoordinates}');
      }
    }
    lines.add('Data: ${record.formattedTimestamp}');
    return lines.join('\n');
  }

  /// Composes [photoBytes] with a metadata footer into a PNG card and returns
  /// the encoded bytes. The photo is scaled to [_cardWidth] and the caption is
  /// drawn in a footer band below it.
  static Future<Uint8List> composeCard(
    SoilRecord record,
    Uint8List photoBytes, {
    bool includeLocation = false,
  }) async {
    final codec = await ui.instantiateImageCodec(photoBytes);
    final frame = await codec.getNextFrame();
    final photo = frame.image;

    final scale = _cardWidth / photo.width;
    final photoHeight = photo.height * scale;

    final footer = TextPainter(
      text: TextSpan(
        text: caption(record, includeLocation: includeLocation),
        style: const TextStyle(
          color: Color(0xFF1A1C19),
          fontSize: 34,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: _cardWidth - _footerPadding * 2);

    final cardHeight = photoHeight + footer.height + _footerPadding * 2;

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, _cardWidth, cardHeight),
    );

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, _cardWidth, cardHeight),
      ui.Paint()..color = const Color(0xFFFCFDF8),
    );
    canvas.drawImageRect(
      photo,
      ui.Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, _cardWidth, photoHeight),
      ui.Paint(),
    );
    footer.paint(canvas, Offset(_footerPadding, photoHeight + _footerPadding));

    final picture = recorder.endRecording();
    final image = await picture.toImage(_cardWidth.round(), cardHeight.ceil());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);

    photo.dispose();
    image.dispose();
    picture.dispose();

    return data!.buffer.asUint8List();
  }
}
