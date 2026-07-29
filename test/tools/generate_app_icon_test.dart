// Local-only generator for the launcher-icon source PNGs (spec 0025). It draws
// the mark through the shared paintVisioSoilMark routine and rasterizes with
// Flutter's own engine, so no external tool (ImageMagick) is needed. It is
// skipped in CI; run it explicitly to (re)produce the committed sources:
//
//   PowerShell:  $env:GENERATE_ICONS=1; flutter test test/tools/generate_app_icon_test.dart
//   bash:        GENERATE_ICONS=1 flutter test test/tools/generate_app_icon_test.dart
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
    // Android adaptive foreground: transparent and near-full-bleed. The safe
    // zone comes from flutter_launcher_icons' own 16% inset in the generated
    // mipmap-anydpi-v26 XML, so the source must NOT be pre-shrunk (that would
    // double the padding and leave the mark undersized on API 26+).
    await _writeTile(
      path: 'assets/branding/app_icon_foreground.png',
      background: null,
      markFraction: 0.90,
    );
  },
      skip: Platform.environment['GENERATE_ICONS'] != '1'
          ? 'set GENERATE_ICONS=1 to (re)generate the committed icon sources'
          : false);
}
