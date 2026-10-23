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
    final decodedStatistics = _rgbStatistics(frame);
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
    void compare(List<double> actual, List<double> want, String source) {
      for (var feature = 0; feature < actual.length; feature++) {
        final difference = (actual[feature] - want[feature]).abs();
        if (difference > largestDifference[feature]) {
          largestDifference[feature] = difference;
          largestStandardisedDifference[feature] =
              difference / _real(scales[feature]);
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
    final mismatches = [
      ...(() {
        final expectedStatistics =
            golden['decoded_rgb_statistics'] as Map<String, dynamic>;
        final expectedMean = (expectedStatistics['mean'] as List<dynamic>)
            .map((value) => _real(value))
            .toList();
        final expectedStd = (expectedStatistics['std'] as List<dynamic>)
            .map((value) => _real(value))
            .toList();
        return [
          for (var channel = 0; channel < 3; channel++)
            if ((decodedStatistics.mean[channel] - expectedMean[channel])
                        .abs() >
                    expectedMean[channel].abs() * _relativeTolerance +
                        _absoluteTolerance ||
                (decodedStatistics.std[channel] - expectedStd[channel]).abs() >
                    expectedStd[channel].abs() * _relativeTolerance +
                        _absoluteTolerance)
              'decoded RGB channel $channel: '
                  'mean Δ=${(decodedStatistics.mean[channel] - expectedMean[channel]).abs().toStringAsPrecision(8)}, '
                  'std Δ=${(decodedStatistics.std[channel] - expectedStd[channel]).abs().toStringAsPrecision(8)}',
        ];
      })(),
      for (var feature = 0; feature < descriptorFeatureNames.length; feature++)
        if (largestDifference[feature] >
            mean[feature].abs() * _relativeTolerance + _absoluteTolerance)
          '${descriptorFeatureNames[feature]}: '
              'Δ=${largestDifference[feature].toStringAsPrecision(8)} '
              '(${largestStandardisedDifference[feature].toStringAsPrecision(8)} '
              'standard deviations) at ${sourceOfLargestDifference[feature]}',
    ];
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}
