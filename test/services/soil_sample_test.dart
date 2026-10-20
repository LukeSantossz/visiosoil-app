import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/soil_sample.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// The soil sample cut from a photograph for display (SPEC 0172), on the
/// committed sheet photographs of 2026-10-05.
const _fixtures = 'test/fixtures/sheet_photos';
const _measured = '$_fixtures/photo_160609.jpg';
const _cropped = '$_fixtures/photo_160812.jpg';

double _meanLuma(img.Image image, int left, int top, int width, int height) {
  var sum = 0.0;
  for (var y = top; y < top + height; y++) {
    for (var x = left; x < left + width; x++) {
      sum += image.getPixel(x, y).luminance;
    }
  }
  return sum / (width * height);
}

void main() {
  test('the_sample_is_centred_on_the_soil', () {
    final bytes = soilSampleJpeg(_measured)!;
    final sample = img.decodeJpg(bytes)!;

    expect(sample.width, sample.height);
    expect(sample.width, lessThanOrEqualTo(soilSampleMaxSidePx));
    final s = sample.width;
    final centre = _meanLuma(sample, s * 3 ~/ 8, s * 3 ~/ 8, s ~/ 4, s ~/ 4);
    final border = _meanLuma(sample, 0, 0, s, s ~/ 20);
    expect(centre, lessThan(border - 40));
  });

  test('the_sample_reaches_past_the_disc', () {
    final frame = InferenceService.frameOf(
      img.bakeOrientation(img.decodeJpg(File(_measured).readAsBytesSync())!),
    );
    final corners = findSheet(frame).corners!;
    final disc = locateSoilDisc(frame, corners)!;
    final region = soilSampleRegion(disc);

    expect(region.widthMm, region.heightMm);
    final wanted = disc.diameterMm + 2 * soilSampleMarginMm;
    final bounded =
        region.leftMm <= 0 ||
        region.topMm <= 0 ||
        region.leftMm + region.widthMm >= sheetWidthMm ||
        region.topMm + region.heightMm >= sheetHeightMm;
    if (bounded) {
      expect(region.widthMm, lessThanOrEqualTo(wanted + 1e-9));
    } else {
      expect(region.widthMm, closeTo(wanted, 1e-9));
    }
    expect(region.leftMm + region.widthMm / 2, closeTo(disc.xMm, 1e-9));
    expect(region.topMm + region.heightMm / 2, closeTo(disc.yMm, 1e-9));
  });

  test('a_disc_by_the_edge_keeps_the_square_inside_the_sheet', () {
    final region = soilSampleRegion((xMm: 30, yMm: 150, diameterMm: 60));

    expect(region.leftMm, closeTo(0, 1e-9));
    expect(region.widthMm, closeTo(60, 1e-9));
    expect(region.heightMm, closeTo(60, 1e-9));
    expect(region.topMm, closeTo(120, 1e-9));
  });

  test('no_sheet_no_sample', () {
    expect(soilSampleJpeg(_cropped), isNull);
    expect(soilSampleJpeg('$_fixtures/absent.jpg'), isNull);

    final unreadable = File(
      '${Directory.systemTemp.createTempSync('soil_sample_').path}/x.jpg',
    )..writeAsBytesSync(Uint8List.fromList([1, 2, 3]));
    addTearDown(() => unreadable.parent.deleteSync(recursive: true));
    expect(soilSampleJpeg(unreadable.path), isNull);

    final blank = File('${unreadable.parent.path}/blank.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 400, height: 300)));
    expect(soilSampleJpeg(blank.path), isNull);
  });

  test('a_rounded_rectangle_is_cut_square', () {
    final square = squareSample(img.Image(width: 1023, height: 1024));

    expect(square.width, 1023);
    expect(square.height, 1023);
  });
}
