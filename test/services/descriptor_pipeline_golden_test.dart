// Cross-language descriptor-pipeline golden over a committed real JPEG
// (SPEC 0177). Python generates the fixture; this test verifies the Dart path.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/descriptors/patch_descriptors.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';

const _goldenPath = 'test/fixtures/descriptors/pipeline_golden.json';

const _relativeTolerance = 1e-9;
const _absoluteTolerance = 1e-12;

// Pillow (libjpeg-turbo) and package:image decode the committed real JPEG's
// coefficients differently, so every stage downstream of decode diverges
// outside SPEC 0030's tolerance. The decode-isolated test below starts from
// Python's own decoded frame instead, so it is unaffected by this gap.
const _decoderDivergenceReason =
    'Known JPEG decoder divergence (Pillow/libjpeg-turbo vs package:image); '
    'see the decode-isolated test for the comparison this blocks, and '
    'SPEC 0177 Risks for the finding.';

double _real(Object? value) => (value as num).toDouble();

({List<double> mean, List<double> std}) _rgbStatistics(RgbFrame frame) {
  final sums = List<double>.filled(3, 0.0);
  for (var pixel = 0; pixel < frame.width * frame.height; pixel++) {
    for (var channel = 0; channel < 3; channel++) {
      sums[channel] += frame.rgb[pixel * 3 + channel];
    }
  }
  final count = frame.width * frame.height;
  final mean = [for (final sum in sums) sum / count];
  final squared = List<double>.filled(3, 0.0);
  for (var pixel = 0; pixel < count; pixel++) {
    for (var channel = 0; channel < 3; channel++) {
      final difference = frame.rgb[pixel * 3 + channel] - mean[channel];
      squared[channel] += difference * difference;
    }
  }
  return (mean: mean, std: [for (final sum in squared) math.sqrt(sum / count)]);
}

/// Runs the shared canonical-resample, patch-cut and descriptor stages over
/// [frame] and compares every patch and the photograph mean to [golden]
/// within SPEC 0030's tolerance, collecting every violation rather than
/// stopping at the first.
void _expectPipelineMatchesGolden(RgbFrame frame, Map<String, dynamic> golden) {
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
  final largestDifference = Float64List(26);
  final largestStandardisedDifference = Float64List(26);
  final sourceOfLargestDifference = List<String>.filled(26, '');
  final scales =
      ((jsonDecode(File('assets/models/spec.json').readAsStringSync())
                  as Map<String, dynamic>)['standardiser']
              as Map<String, dynamic>)['scale']
          as List<dynamic>;
  final violations = <String>[];

  // Checks each feature against its own patch's expected value, per SPEC
  // 0030's `atol + rtol * |expected|` rule, and collects every violation
  // rather than stopping at the first. A NaN or infinite value on either
  // side is reported explicitly: the tolerance comparison below is false for
  // every ordering of a NaN operand, so without this guard a non-finite
  // actual value would silently pass rather than fail.
  void compare(List<double> actual, List<double> want, String source) {
    for (var feature = 0; feature < actual.length; feature++) {
      final actualValue = actual[feature];
      final wantValue = want[feature];
      if (!actualValue.isFinite || !wantValue.isFinite) {
        violations.add(
          '$source ${descriptorFeatureNames[feature]}: non-finite value '
          '(want $wantValue, got $actualValue)',
        );
        continue;
      }
      final difference = (actualValue - wantValue).abs();
      final threshold = _absoluteTolerance + _relativeTolerance * wantValue.abs();
      if (difference > threshold) {
        violations.add(
          '$source ${descriptorFeatureNames[feature]}: '
          'Δ=${difference.toStringAsPrecision(8)} '
          '(want $wantValue, got $actualValue)',
        );
      }
      if (difference > largestDifference[feature]) {
        largestDifference[feature] = difference;
        final scale = _real(scales[feature]);
        largestStandardisedDifference[feature] =
            scale == 0 ? 0.0 : difference / scale;
        sourceOfLargestDifference[feature] = source;
      }
    }
  }

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
    compare(actual, want, 'patch $patchIndex');
    for (var feature = 0; feature < actual.length; feature++) {
      totals[feature] += actual[feature];
    }
  }

  final mean = (golden['mean_features'] as List<dynamic>)
      .map((value) => (value as num).toDouble())
      .toList();
  expect(mean, hasLength(26));
  final actualMean = [
    for (var feature = 0; feature < mean.length; feature++)
      totals[feature] / patches.length,
  ];
  compare(actualMean, mean, 'photograph mean');

  final offendingFeatures = [
    for (var feature = 0; feature < descriptorFeatureNames.length; feature++)
      if (largestDifference[feature] > 0) feature,
  ]..sort(
    (a, b) => largestDifference[b].compareTo(largestDifference[a]),
  );
  final worstOffenders = [
    for (final feature in offendingFeatures)
      '${descriptorFeatureNames[feature]}: '
          'Δ=${largestDifference[feature].toStringAsPrecision(8)} '
          '(${largestStandardisedDifference[feature].toStringAsPrecision(8)} '
          'standard deviations) at ${sourceOfLargestDifference[feature]}',
  ];
  // Printed unconditionally, pass or fail, so a measured difference is
  // visible rather than only inferable from a passing test.
  // ignore: avoid_print
  print(
    worstOffenders.isEmpty
        ? 'measured differences: none (bit-exact match against the golden)'
        : 'measured differences, largest first: ${worstOffenders.take(5).join('; ')}',
  );
  expect(
    violations,
    isEmpty,
    reason: [
      '${violations.length} tolerance violation(s):',
      ...violations,
      'Worst offenders by largest difference:',
      ...worstOffenders.take(5),
    ].join('\n'),
  );
}

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

  test(
    'decoder stage: dart_decoded_frame_matches_python_for_a_real_photograph',
    () {
      final photograph = File(golden['photograph'] as String);
      final decoded = img.decodeJpg(photograph.readAsBytesSync())!;
      final frame = InferenceService.frameOf(img.bakeOrientation(decoded));
      final decodedStatistics = _rgbStatistics(frame);

      final decodedSize = golden['decoded_size'] as List<dynamic>?;
      if (decodedSize != null) {
        expect(frame.width, equals(decodedSize[0]));
        expect(frame.height, equals(decodedSize[1]));
      }

      final canonicalSize = golden['canonical_size'] as List<dynamic>?;
      if (canonicalSize != null) {
        final measurement = golden['measurement'] as Map<String, dynamic>;
        final geometry = golden['geometry'] as Map<String, dynamic>;
        final canonical = resampleToCanonical(
          frame,
          measuredMmPerPx: _real(measurement['mm_per_px']),
          canonicalMmPerPx: _real(geometry['canonical_mm_per_px']),
        ).frame!;
        expect(canonical.width, equals(canonicalSize[0]));
        expect(canonical.height, equals(canonicalSize[1]));
      }

      final expectedStatistics =
          golden['decoded_rgb_statistics'] as Map<String, dynamic>;
      final expectedMean = (expectedStatistics['mean'] as List<dynamic>)
          .map((value) => _real(value))
          .toList();
      final expectedStd = (expectedStatistics['std'] as List<dynamic>)
          .map((value) => _real(value))
          .toList();
      final mismatches = [
        for (var channel = 0; channel < 3; channel++)
          if ((decodedStatistics.mean[channel] - expectedMean[channel])
                      .abs() >
                  _absoluteTolerance +
                      _relativeTolerance * expectedMean[channel].abs() ||
              (decodedStatistics.std[channel] - expectedStd[channel]).abs() >
                  _absoluteTolerance +
                      _relativeTolerance * expectedStd[channel].abs())
            'decoded RGB channel $channel: '
                'mean Δ=${(decodedStatistics.mean[channel] - expectedMean[channel]).abs().toStringAsPrecision(8)}, '
                'std Δ=${(decodedStatistics.std[channel] - expectedStd[channel]).abs().toStringAsPrecision(8)}',
      ];
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    },
    skip: _decoderDivergenceReason,
  );

  test(
    'end-to-end stage (JPEG decode included): '
    'dart_pipeline_matches_python_for_a_real_photograph',
    () {
      final photograph = File(golden['photograph'] as String);
      final decoded = img.decodeJpg(photograph.readAsBytesSync())!;
      final frame = InferenceService.frameOf(img.bakeOrientation(decoded));
      _expectPipelineMatchesGolden(frame, golden);
    },
    skip: _decoderDivergenceReason,
  );

  test(
    'descriptor stage (decode-isolated): '
    'dart_pipeline_matches_python_for_a_real_photograph',
    () {
      final fixture = golden['decoded_frame_fixture'] as Map<String, dynamic>;
      final pngFile = File(fixture['path'] as String);
      expect(
        pngFile.existsSync(),
        isTrue,
        reason:
            '${fixture['path']} is missing. Regenerate it with '
            '`cd ml && python scripts/generate_descriptor_pipeline_golden.py`.',
      );
      // This PNG is Python's own Pillow-decoded, EXIF-oriented RGB frame
      // (stage `${fixture['stage']}`), written losslessly, so decoding it
      // here reproduces the exact pixels Python described rather than
      // whatever package:image's JPEG decoder independently derives from the
      // JPEG coefficients.
      final decoded = img.decodePng(pngFile.readAsBytesSync())!;
      final frame = InferenceService.frameOf(decoded);

      final decodedSize = golden['decoded_size'] as List<dynamic>;
      expect(frame.width, equals(decodedSize[0]));
      expect(frame.height, equals(decodedSize[1]));

      _expectPipelineMatchesGolden(frame, golden);
    },
  );
}
