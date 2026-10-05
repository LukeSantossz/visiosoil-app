// Acceptance criteria for the Dart patch grid (SPEC 0081, ADR 0025).
//
// Each test name matches an acceptance criterion in
// `docs/specs/0081-cut-the-canonical-patch-grid-in-dart-from-a-measured-scale.md`.
// The golden is written by `ml/scripts/generate_patch_golden.py` from
// `src.patches` and the training cut, and `ml/tests/test_patch_golden.py` holds
// Python to it. Everything here is compared exactly: ADR 0025's rule is
// identical arithmetic, not approximately equal pixels.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

const _goldenPath = 'test/fixtures/patches/golden.json';

/// `src.patches.PatchRefusal`'s values, as the golden names them.
const _refusals = {
  'too_coarse_to_normalise': PatchRefusal.tooCoarse,
  'region_too_small_for_the_patch_floor': PatchRefusal.regionTooSmall,
  'region_not_wholly_photographed': PatchRefusal.outsideFrame,
};

double _real(Object? value) => (value as num).toDouble();

RgbFrame _frame(Map<String, dynamic> entry) => RgbFrame(
  entry['width'] as int,
  entry['height'] as int,
  base64Decode(entry['rgb'] as String),
);

List<Map<String, dynamic>> _cases(Map<String, dynamic> golden, String key) =>
    (golden[key] as List<dynamic>).cast<Map<String, dynamic>>();

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    final file = File(_goldenPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_goldenPath is missing. Regenerate it with '
          '`cd ml && python scripts/generate_patch_golden.py`.',
    );
    golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('dart_resample_matches_pillow', () {
    final cases = _cases(golden, 'resample');
    expect(cases, isNotEmpty);
    for (final entry in cases) {
      final resampled = resampleToCanonical(
        _frame(entry),
        measuredMmPerPx: _real(entry['measured_mm_per_px']),
        canonicalMmPerPx: _real(entry['canonical_mm_per_px']),
      );
      expect(resampled.refusal, isNull, reason: entry['name'] as String);
      final frame = resampled.frame!;
      expect(frame.width, entry['out_width'], reason: entry['name'] as String);
      expect(
        frame.height,
        entry['out_height'],
        reason: entry['name'] as String,
      );
      expect(
        frame.rgb,
        base64Decode(entry['resampled'] as String),
        reason: entry['name'] as String,
      );
    }
  });

  test('dart_luma_matches_python', () {
    final cases = _cases(golden, 'luma');
    expect(cases, isNotEmpty);
    for (final entry in cases) {
      final rgb = (entry['rgb'] as List<dynamic>).cast<int>();
      expect(greyOf(rgb[0], rgb[1], rgb[2]), entry['grey'], reason: '$rgb');
    }
  });

  test('dart_geometry_matches_python', () {
    final cases = _cases(golden, 'geometry');
    expect(cases, isNotEmpty);
    for (final entry in cases) {
      final name = entry['name'] as String;
      final outcome = patchGeometry(
        regionDiameterPx: _real(entry['region_diameter_px']),
        patchPx: entry['patch_px'] as int,
        canonicalMmPerPx: _real(entry['canonical_mm_per_px']),
        minPatches: entry['min_patches'] as int,
        strideFraction: _real(entry['stride_fraction']),
      );
      if (entry.containsKey('refusal')) {
        expect(outcome.refusal, _refusals[entry['refusal']], reason: name);
        expect(outcome.geometry, isNull, reason: name);
        continue;
      }
      final geometry = outcome.geometry!;
      expect(geometry.count, entry['count'], reason: name);
      expect(geometry.stridePx, _real(entry['stride_px']), reason: name);
      expect(geometry.insetPx, _real(entry['inset_px']), reason: name);
      expect(geometry.patchMm, _real(entry['patch_mm']), reason: name);
      expect(
        [
          for (final offset in geometry.offsets) [offset.$1, offset.$2],
        ],
        [
          for (final offset in entry['offsets'] as List<dynamic>)
            [for (final value in offset as List<dynamic>) _real(value)],
        ],
        reason: name,
      );
    }
  });

  test('dart_patches_match_python', () {
    final cases = _cases(golden, 'pipeline');
    expect(cases, isNotEmpty);
    for (final entry in cases) {
      final name = entry['name'] as String;
      final outcome = canonicalPatches(
        _frame(entry),
        measuredMmPerPx: _real(entry['measured_mm_per_px']),
        centreYPx: _real(entry['centre_y_px']),
        centreXPx: _real(entry['centre_x_px']),
        diameterPx: _real(entry['diameter_px']),
        canonicalMmPerPx: _real(entry['canonical_mm_per_px']),
        patchPx: entry['patch_px'] as int,
        strideFraction: _real(entry['stride_fraction']),
        minPatches: entry['min_patches'] as int,
      );
      if (entry.containsKey('refusal')) {
        expect(outcome.refusal, _refusals[entry['refusal']], reason: name);
        expect(outcome.patches, isNull, reason: name);
        continue;
      }
      expect(outcome.refusal, isNull, reason: name);
      expect(outcome.patches, [
        for (final patch in entry['patches'] as List<dynamic>)
          base64Decode(patch as String),
      ], reason: name);
    }
  });

  test('a_photograph_coarser_than_the_canonical_is_refused', () {
    final frame = RgbFrame(2, 1, Uint8List.fromList([1, 2, 3, 4, 5, 6]));

    final coarse = resampleToCanonical(
      frame,
      measuredMmPerPx: 0.14,
      canonicalMmPerPx: 0.125,
    );
    expect(coarse.refusal, PatchRefusal.tooCoarse);
    expect(coarse.frame, isNull);

    final same = resampleToCanonical(
      frame,
      measuredMmPerPx: 0.125,
      canonicalMmPerPx: 0.125,
    );
    expect(same.refusal, isNull);
    expect(same.frame!.rgb, frame.rgb);
    expect((same.frame!.width, same.frame!.height), (2, 1));
  });

  // SPEC 0141: a disc too small for the centred floor moves to the half-stride
  // grid, at the contract's patch side and canonical scale.
  const canonical = 0.12920342774728033;

  ({PatchGeometry? geometry, PatchRefusal? refusal}) disc(double mm) =>
      patchGeometry(
        regionDiameterPx: mm / canonical,
        patchPx: 160,
        canonicalMmPerPx: canonical,
        minPatches: 4,
        strideFraction: 0.5,
      );

  test('the_half_stride_grid_fills_a_small_disc', () {
    expect(disc(47.5).geometry!.offsets, [
      (-40.0, -40.0),
      (-40.0, 40.0),
      (40.0, -40.0),
      (40.0, 40.0),
    ]);
    expect(disc(51.0).geometry!.offsets, [
      (-80.0, 0.0),
      (0.0, -80.0),
      (0.0, 0.0),
      (0.0, 80.0),
      (80.0, 0.0),
    ]);
  });

  test('a_disc_below_the_half_stride_block_is_refused', () {
    final outcome = disc(43.5);
    expect(outcome.refusal, PatchRefusal.regionTooSmall);
    expect(outcome.geometry, isNull);
  });

  test('floor_division_is_pythons', () {
    // `1 // 0.1` is 9.0 in Python, while `1 / 0.1` rounds to exactly 10.0.
    expect(pythonFloorDivide(1.0, 0.1), 9.0);
    expect(pythonFloorDivide(7.0, 2.0), 3.0);
    expect(pythonFloorDivide(-7.0, 2.0), -4.0);
    expect(pythonFloorDivide(240.0, 80.0), 3.0);
  });

  test('one_luma_definition_in_lib', () {
    final declaring = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('0.299') ||
          text.contains('0.587') ||
          text.contains('0.114')) {
        declaring.add(entity.path);
      }
    }
    expect(declaring, hasLength(1), reason: '$declaring');
  });
}
