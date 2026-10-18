import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

const _fixtures = 'test/fixtures/sheet_photos';

/// [frame] as the preview path hands it to the reader: each pixel's grey,
/// replicated into three channels.
RgbFrame _greyOf(RgbFrame frame) {
  final rgb = Uint8List(frame.rgb.length);
  for (var i = 0; i < rgb.length; i += 3) {
    final grey = greyOf(frame.rgb[i], frame.rgb[i + 1], frame.rgb[i + 2]);
    rgb[i] = grey;
    rgb[i + 1] = grey;
    rgb[i + 2] = grey;
  }
  return RgbFrame(frame.width, frame.height, rgb);
}

void main() {
  final contract = parseDescriptorContract(
    File('assets/models/spec.json').readAsStringSync(),
  ).contract!;
  final live = liveContractOf(contract);

  test('the_live_reading_matches_the_colour_reading', () {
    final photos = (jsonDecode(File('$_fixtures/expected.json').readAsStringSync())
        as Map<String, dynamic>)['photos'] as List<dynamic>;
    expect(photos, hasLength(6));
    for (final photo in photos.cast<Map<String, dynamic>>()) {
      final name = photo['name'] as String;
      final colour = InferenceService.frameOf(
        img.decodeJpg(File('$_fixtures/${photo['file']}').readAsBytesSync())!,
      );
      final reading = readSheet(_greyOf(colour), live);

      final found = findSheet(colour);
      if (found.corners == null) {
        expect(
          reading,
          found.refusal == SheetRefusal.cropped
              ? isA<LiveSheetCropped>()
              : isA<LiveSheetNotFound>(),
          reason: name,
        );
        continue;
      }
      expect(reading, isA<LiveSheetFound>(), reason: name);
      final liveFound = reading as LiveSheetFound;
      final disc = locateSoilDisc(colour, found.corners!);
      if (disc == null) {
        expect(liveFound.discDiameterMm, isNull, reason: name);
        expect(liveFound.holdsMinPatches, isFalse, reason: name);
        continue;
      }
      expect(liveFound.discDiameterMm, closeTo(disc.diameterMm, 1), reason: name);
      final geometry = patchGeometry(
        regionDiameterPx: disc.diameterMm / contract.canonicalMmPerPx,
        patchPx: contract.patchPx,
        canonicalMmPerPx: contract.canonicalMmPerPx,
        minPatches: contract.minPatches,
        strideFraction: contract.patchStrideFraction,
      );
      expect(liveFound.holdsMinPatches, geometry.geometry != null, reason: name);
      expect(liveFound.sheetLongSidePx, greaterThan(0), reason: name);
    }
  });

  test('the_long_side_is_the_mean_of_the_long_edges', () {
    const corners = SheetCorners([
      (x: 0, y: 0),
      (x: 100, y: 0),
      (x: 100, y: 141),
      (x: 0, y: 141),
    ]);
    expect(sheetLongSidePx(corners), closeTo(141, 1e-9));
    // A keystoned sheet: the two long edges differ, and their mean counts.
    const keystoned = SheetCorners([
      (x: 10, y: 0),
      (x: 90, y: 0),
      (x: 100, y: 140),
      (x: 0, y: 140),
    ]);
    final left = math.sqrt(10 * 10 + 140 * 140);
    final right = math.sqrt(10 * 10 + 140 * 140);
    expect(sheetLongSidePx(keystoned), closeTo((left + right) / 2, 1e-9));
  });
}
