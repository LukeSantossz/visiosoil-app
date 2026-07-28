// Local-only generator for the launcher-icon source PNGs (spec 0025). It draws
// the mark through the shared paintVisioSoilMark routine and rasterizes with
// Flutter's own engine, so no external tool (ImageMagick) is needed. It is
// skipped in CI; run it explicitly to (re)produce the committed sources:
//
//   GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart
//
// Then regenerate the platform icons with: dart run flutter_launcher_icons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';

Future<void> _writeTile({
  required String path,
  required Color? background, // null => transparent (adaptive foreground)
  required double markFraction, // mark edge as a fraction of the tile
}) async {
  const dimension = 1024;
  final bounds = Rect.fromLTWH(0, 0, dimension.toDouble(), dimension.toDouble());
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, bounds);
  if (background != null) {
    canvas.drawRect(bounds, Paint()..color = background);
  }
  final markSize = dimension * markFraction;
  final offset = (dimension - markSize) / 2;
  canvas.translate(offset, offset);
  paintVisioSoilMark(canvas, Size(markSize, markSize), Colors.white);

  final picture = recorder.endRecording();
  final image = await picture.toImage(dimension, dimension);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(png!.buffer.asUint8List());
}

void main() {
  test('generate launcher-icon sources from the brand mark', () async {
    // Full icon: white mark at 60% of the design-system green tile.
    await _writeTile(
      path: 'assets/branding/app_icon.png',
      background: const Color(0xFF4A7C59),
      markFraction: 0.60,
    );
    // Android adaptive foreground: transparent, mark pulled in to the safe zone.
    await _writeTile(
      path: 'assets/branding/app_icon_foreground.png',
      background: null,
      markFraction: 0.50,
    );
  },
      skip: Platform.environment['GENERATE_ICONS'] != '1'
          ? 'set GENERATE_ICONS=1 to (re)generate the committed icon sources'
          : false);
}
