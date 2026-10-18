import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// The sides a cropped sheet runs off, which the live warning names
/// (SPEC 0169). Each frame is a pale A4-proportioned rectangle on a darker
/// surface, laid so that part of it falls outside the frame.
RgbFrame _scene({
  required int width,
  required int height,
  required double left,
  required double top,
  required double sheetWidth,
}) {
  final sheetHeight = sheetWidth * sheetHeightMm / sheetWidthMm;
  final rgb = Uint8List(width * height * 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final inside = x >= left &&
          x < left + sheetWidth &&
          y >= top &&
          y < top + sheetHeight;
      final grey = inside ? 235 : 90;
      final i = (y * width + x) * 3;
      rgb[i] = grey;
      rgb[i + 1] = grey;
      rgb[i + 2] = grey;
    }
  }
  return RgbFrame(width, height, rgb);
}

void main() {
  test('a_sheet_off_the_right_names_right', () {
    final result = findSheet(
      _scene(width: 576, height: 1024, left: 200, top: 150, sheetWidth: 450),
    );
    expect(result.refusal, SheetRefusal.cropped);
    expect(result.croppedSides, [FrameSide.right]);
  });

  test('a_sheet_off_top_and_bottom_names_both', () {
    final result = findSheet(
      _scene(width: 1024, height: 1024, left: 200, top: -60, sheetWidth: 800),
    );
    expect(result.refusal, SheetRefusal.cropped);
    expect(result.croppedSides.toSet(), {FrameSide.top, FrameSide.bottom});
  });

  test('a_found_sheet_has_no_sides', () {
    final result = findSheet(
      _scene(width: 576, height: 1024, left: 80, top: 160, sheetWidth: 416),
    );
    expect(result.refusal, isNull);
    expect(result.croppedSides, isEmpty);
  });
}
