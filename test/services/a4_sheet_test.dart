import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

/// The A4-sheet reader against scenes an independent geometry placed
/// (SPEC 0091). `ml/scripts/generate_sheet_fixtures.py` lays the sheet with
/// Pillow's perspective transform and records where its corners went. Nothing
/// here shares that mathematics.
const _fixtures = 'test/fixtures/sheet';

final Map<String, dynamic> _golden =
    jsonDecode(File('$_fixtures/golden.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _case(String name) => (_golden['cases'] as List)
    .cast<Map<String, dynamic>>()
    .firstWhere((entry) => entry['name'] == name);

RgbFrame _frame(String name) => InferenceService.frameOf(
  img.decodeJpg(File('$_fixtures/${_case(name)['file']}').readAsBytesSync())!,
);

List<({double x, double y})> _placed(String name) => [
  for (final corner in _case(name)['corners'] as List)
    (x: (corner[0] as num).toDouble(), y: (corner[1] as num).toDouble()),
];

double _distance(({double x, double y}) a, ({double x, double y}) b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

RgbFrame _mirrored(RgbFrame frame) {
  final rgb = Uint8List(frame.rgb.length);
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      final from = (y * frame.width + x) * 3;
      final to = (y * frame.width + (frame.width - 1 - x)) * 3;
      rgb[to] = frame.rgb[from];
      rgb[to + 1] = frame.rgb[from + 1];
      rgb[to + 2] = frame.rgb[from + 2];
    }
  }
  return RgbFrame(frame.width, frame.height, rgb);
}

SheetCorners _found(String name) {
  final result = findSheet(_frame(name));
  expect(result.refusal, isNull, reason: '$name was refused');
  return result.corners!;
}

const _wholeSheets = [
  'frontal',
  'tilted_15',
  'tilted_30',
  'rotated_20',
  'landscape',
  'marks',
];

void main() {
  test('a_sheet_is_found_within_tolerance', () {
    for (final name in _wholeSheets) {
      final placed = _placed(name);
      final diagonal = _distance(placed[0], placed[2]);
      final corners = _found(name).points;
      expect(corners, hasLength(4));

      for (final corner in corners) {
        final nearest = placed
            .map((p) => _distance(p, corner))
            .reduce(math.min);
        expect(
          nearest,
          lessThanOrEqualTo(0.005 * diagonal),
          reason: '$name: a corner is ${nearest.toStringAsFixed(2)} px off',
        );
      }

      // The second edge is a long one, which is what maps to 297 mm.
      final long = _distance(corners[1], corners[2]);
      final short = _distance(corners[0], corners[1]);
      expect(long, greaterThan(short), reason: '$name: long side misread');

      final mmPerPx = (_case(name)['mm_per_px'] as num).toDouble();
      final rectified = rectifySheet(_frame(name), _found(name));
      expect(
        (rectified.mmPerPx - mmPerPx).abs() / mmPerPx,
        lessThanOrEqualTo(0.01),
        reason: '$name: ${rectified.mmPerPx} mm/px against $mmPerPx',
      );
    }
  });

  test('no_sheet_is_refused_as_not_found', () {
    expect(findSheet(_frame('no_sheet')).refusal, SheetRefusal.notFound);
  });

  test('a_pale_sheet_on_a_pale_surface_is_refused_as_not_found', () {
    expect(findSheet(_frame('pale_on_pale')).refusal, SheetRefusal.notFound);
  });

  test('a_cropped_sheet_is_refused_as_cropped', () {
    expect(findSheet(_frame('cropped')).refusal, SheetRefusal.cropped);
  });

  test('a_mirrored_photograph_reads_the_same_scale', () {
    for (final name in ['frontal', 'tilted_30', 'rotated_20']) {
      final frame = _frame(name);
      final mirror = _mirrored(frame);
      final direct = rectifySheet(frame, findSheet(frame).corners!).mmPerPx;
      final reflected = rectifySheet(
        mirror,
        findSheet(mirror).corners!,
      ).mmPerPx;
      expect(
        (direct - reflected).abs() / direct,
        lessThanOrEqualTo(0.005),
        reason: '$name: $direct against $reflected mm/px',
      );
    }
  });

  test('rectification_puts_marks_where_the_sheet_has_them', () {
    final rectified = rectifySheet(_frame('marks'), _found('marks'));
    final frame = rectified.frame;
    final mmPerPx = rectified.mmPerPx;
    final window = (6 / mmPerPx).round();

    // The marks are symmetric under the sheet's reflections and half-turn, so
    // which corner the reader calls the origin does not move them.
    for (final mark in _case('marks')['marks_mm'] as List) {
      final expectedX = (mark[0] as num) / mmPerPx;
      final expectedY = (mark[1] as num) / mmPerPx;
      var sumX = 0.0, sumY = 0.0, count = 0;
      for (var y = expectedY.round() - window; y <= expectedY + window; y++) {
        for (var x = expectedX.round() - window; x <= expectedX + window; x++) {
          if (x < 0 || y < 0 || x >= frame.width || y >= frame.height) continue;
          final i = (y * frame.width + x) * 3;
          final grey = greyOf(frame.rgb[i], frame.rgb[i + 1], frame.rgb[i + 2]);
          if (grey < 60) {
            sumX += x + 0.5;
            sumY += y + 0.5;
            count++;
          }
        }
      }
      expect(count, greaterThan(0), reason: 'mark $mark not found');
      final offMm =
          math.sqrt(
            math.pow(sumX / count - expectedX, 2) +
                math.pow(sumY / count - expectedY, 2),
          ) *
          mmPerPx;
      expect(
        offMm,
        lessThanOrEqualTo(1.0),
        reason: 'mark $mark is ${offMm.toStringAsFixed(2)} mm off',
      );
    }
  });

  test('rectification_keeps_the_native_scale', () {
    for (final name in _wholeSheets) {
      final photographed = 1 / (_case(name)['mm_per_px'] as num);
      final rectified = 1 / rectifySheet(_frame(name), _found(name)).mmPerPx;
      expect(
        (rectified - photographed).abs() / photographed,
        lessThanOrEqualTo(0.05),
        reason: '$name: $rectified px/mm against $photographed',
      );
    }
  });

  test('a_region_is_rectified_alone', () {
    final frame = _frame('tilted_15');
    final corners = findSheet(frame).corners!;
    final whole = rectifySheet(frame, corners);
    final region = rectifySheet(
      frame,
      corners,
      region: const SheetRegion(
        leftMm: 60,
        topMm: 100,
        widthMm: 90,
        heightMm: 95,
      ),
    );

    expect(region.mmPerPx, whole.mmPerPx);
    final part = region.frame;
    for (var y = 0; y < part.height; y++) {
      for (var x = 0; x < part.width; x++) {
        final i = (y * part.width + x) * 3;
        final j =
            ((region.top + y) * whole.frame.width + (region.left + x)) * 3;
        expect(
          [part.rgb[i], part.rgb[i + 1], part.rgb[i + 2]],
          [whole.frame.rgb[j], whole.frame.rgb[j + 1], whole.frame.rgb[j + 2]],
          reason: 'pixel ($x, $y) of the region differs from the whole',
        );
      }
    }
  });
}
