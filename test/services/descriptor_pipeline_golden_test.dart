// Cross-language descriptor-pipeline golden over a committed real JPEG
// (SPEC 0177). Python generates the fixture; this test verifies the Dart path.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

const _goldenPath = 'test/fixtures/descriptors/pipeline_golden.json';

Matcher _near(double want) => closeTo(want, want.abs() * 1e-9 + 1e-12);

double _real(Object? value) => (value as num).toDouble();

void main() {
  late Map<String, dynamic> golden;

  setUpAll(() {
    final file = File(_goldenPath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          '$_goldenPath is missing. Regenerate it with '
          '`cd ml && python scripts/generate_descriptor_pipeline_golden.py`.',
    );
    golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  });

  test('dart_pipeline_matches_python_for_a_real_photograph', () {
    final photograph = File(golden['photograph'] as String);
    final decoded = img.decodeJpg(photograph.readAsBytesSync())!;
    final frame = InferenceService.frameOf(img.bakeOrientation(decoded));
    final measurement = golden['measurement'] as Map<String, dynamic>;
    final geometry = golden['geometry'] as Map<String, dynamic>;
    final cut = canonicalPatches(
      frame,
      measuredMmPerPx: _real(measurement['mm_per_px']),
      centreYPx: _real(measurement['centre_y_px']),
      centreXPx: _real(measurement['centre_x_px']),
      diameterPx: _real(measurement['diameter_px']),
      canonicalMmPerPx: _real(geometry['canonical_mm_per_px']),
      patchPx: geometry['patch_px'] as int,
      strideFraction: _real(geometry['patch_stride_fraction']),
      minPatches: geometry['min_patches'] as int,
    );
    expect(cut.refusal, isNull);
    final patches = cut.patches!;
    final expected = (golden['patches'] as List<dynamic>).cast<List<dynamic>>();
    expect(patches, hasLength(expected.length));

    final totals = Float64List(26);
    for (var patchIndex = 0; patchIndex < patches.length; patchIndex++) {
      final actual = describePatch(
        patches[patchIndex],
        geometry['patch_px'] as int,
        geometry['patch_px'] as int,
      );
      final want = expected[patchIndex]
          .map((value) => (value as num).toDouble())
          .toList();
      expect(actual, hasLength(26));
      for (var feature = 0; feature < actual.length; feature++) {
        expect(
          actual[feature],
          _near(want[feature]),
          reason: 'patch $patchIndex feature $feature',
        );
        totals[feature] += actual[feature];
      }
    }

    final mean = (golden['mean_features'] as List<dynamic>)
        .map((value) => (value as num).toDouble())
        .toList();
    expect(mean, hasLength(26));
    for (var feature = 0; feature < mean.length; feature++) {
      expect(
        totals[feature] / patches.length,
        _near(mean[feature]),
        reason: 'mean feature $feature',
      );
    }
  });
}
