// Acceptance criteria for the soil image quality analyzer (SPEC 0030).
//
// Each group name matches an acceptance criterion in
// `docs/specs/0030-soil-image-acceptance-criteria.md`. The golden conformance
// group is what proves this implementation and `ml/src/image_quality.py` agree;
// a divergence on either side fails the other side's suite.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/services/image_quality/image_quality_analyzer.dart';
import 'package:visiosoil_app/core/services/image_quality/image_quality_criteria.dart';
import 'package:visiosoil_app/core/services/image_quality/image_quality_report.dart';

const _analyzer = ImageQualityAnalyzer();
const _side = 640;
const _fixtureDir = 'test/fixtures/image_quality';

// --- fixture builders: the same formulas as the Python generator ------------

img.Image _fill(int side, int value) {
  final image = img.Image(width: side, height: side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _checkerboard(int side, int low, int high, {int cell = 4}) {
  final image = img.Image(width: side, height: side);
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final value = ((x ~/ cell) + (y ~/ cell)) % 2 == 0 ? high : low;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

Set<ImageQualityCriterion> _failed(ImageQualityReport report) =>
    report.failures.map((failure) => failure.criterion).toSet();

void main() {
  group('roi geometry', () {
    test('roi_is_largest_centred_square', () {
      expect(roiBounds(400, 300), (x: 50, y: 0, side: 300));
      expect(roiBounds(300, 400), (x: 0, y: 50, side: 300));
      expect(roiBounds(300, 300), (x: 0, y: 0, side: 300));
    });

    test('roi_side_is_reported', () {
      final square = _analyzer.analyze(_checkerboard(_side, 60, 200));
      expect(square.metrics!.roiSidePx, _side);

      final wide = img.copyResize(
        _checkerboard(_side, 60, 200),
        width: _side * 2,
        height: _side,
      );
      expect(_analyzer.analyze(wide).metrics!.roiSidePx, _side);
    });

    test('roi_side_below_minimum_is_blocking', () {
      final report = _analyzer.analyze(_checkerboard(256, 60, 200));
      expect(report.verdict, ImageQualityVerdict.blocking);
      expect(_failed(report), contains(ImageQualityCriterion.resolution));
    });
  });

  group('blur', () {
    test('blur_is_resolution_independent', () {
      final large =
          _analyzer.analyze(_checkerboard(2048, 60, 200, cell: 64)).metrics!;
      final small =
          _analyzer.analyze(_checkerboard(1024, 60, 200, cell: 32)).metrics!;

      final ratio = large.blurScore / small.blurScore;
      expect(ratio, greaterThan(0.95));
      expect(ratio, lessThan(1.05));
    });

    test('blur_separates_sharp_from_blurred', () {
      final sharp = _analyzer.analyze(_checkerboard(_side, 60, 200));
      final blurred = _analyzer.analyze(
        img.gaussianBlur(_checkerboard(_side, 60, 200), radius: 6),
      );

      expect(sharp.metrics!.blurScore,
          greaterThan(blurred.metrics!.blurScore));
      expect(_failed(sharp), isNot(contains(ImageQualityCriterion.blur)));
      expect(_failed(blurred), contains(ImageQualityCriterion.blur));
      expect(blurred.verdict, ImageQualityVerdict.blocking);
    });
  });

  group('exposure and clipping', () {
    test('exposure_bounds_are_two_sided', () {
      final dark = _analyzer.analyze(_checkerboard(_side, 5, 35));
      final bright = _analyzer.analyze(_checkerboard(_side, 225, 248));
      final mid = _analyzer.analyze(_checkerboard(_side, 60, 200));

      expect(dark.verdict, ImageQualityVerdict.blocking);
      expect(_failed(dark), contains(ImageQualityCriterion.exposure));
      expect(bright.verdict, ImageQualityVerdict.blocking);
      expect(_failed(bright), contains(ImageQualityCriterion.exposure));
      expect(_failed(mid), isNot(contains(ImageQualityCriterion.exposure)));
    });

    test('clipping_is_detected', () {
      final image = _checkerboard(_side, 96, 160);
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x += 5) {
          image.setPixelRgb(x, y, 255, 255, 255);
        }
      }
      final report = _analyzer.analyze(image);

      expect(report.metrics!.clippedFraction, closeTo(0.20, 1e-12));
      expect(report.verdict, ImageQualityVerdict.blocking);
      expect(_failed(report), contains(ImageQualityCriterion.clipping));
    });
  });

  group('the advisory criteria', () {
    test('low_contrast_is_advisory', () {
      final report = _analyzer.analyze(_checkerboard(_side, 113, 143));

      expect(report.metrics!.contrastScore,
          lessThan(const ImageQualityCriteria().minContrastScore));
      expect(_failed(report), contains(ImageQualityCriterion.contrast));
      expect(_failed(report), isNot(contains(ImageQualityCriterion.blur)));
      expect(report.verdict, ImageQualityVerdict.advisory);
    });

    test('colour_cast_is_advisory', () {
      final image = _checkerboard(_side, 60, 180);
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          final pixel = image.getPixel(x, y);
          image.setPixelRgb(
            x,
            y,
            (pixel.r + 60).clamp(0, 255),
            pixel.g,
            pixel.b,
          );
        }
      }
      final report = _analyzer.analyze(image);

      expect(report.metrics!.colorCastScore, closeTo(60 / 255, 1e-12));
      expect(_failed(report), contains(ImageQualityCriterion.colorCast));
      expect(report.verdict, ImageQualityVerdict.advisory);
    });

    test('specular_is_advisory', () {
      final image = _checkerboard(_side, 100, 160);
      final brightRows = (_side * 0.15).toInt();
      for (var y = 0; y < brightRows; y++) {
        for (var x = 0; x < _side; x++) {
          image.setPixelRgb(x, y, 251, 251, 251);
        }
      }
      final report = _analyzer.analyze(image);

      expect(report.metrics!.specularFraction, closeTo(0.15, 1e-12));
      expect(report.metrics!.clippedFraction, 0.0);
      expect(_failed(report), contains(ImageQualityCriterion.specular));
      expect(report.verdict, ImageQualityVerdict.advisory);
    });
  });

  group('verdict composition', () {
    test('blocking_outranks_advisory', () {
      final image = _checkerboard(_side, 60, 180);
      for (var y = 0; y < _side; y++) {
        for (var x = 0; x < _side; x++) {
          final pixel = image.getPixel(x, y);
          image.setPixelRgb(x, y, (pixel.r + 60).clamp(0, 255), pixel.g,
              pixel.b);
        }
      }
      final report = _analyzer.analyze(img.gaussianBlur(image, radius: 6));

      expect(_failed(report), contains(ImageQualityCriterion.blur));
      expect(_failed(report), contains(ImageQualityCriterion.colorCast));
      expect(report.verdict, ImageQualityVerdict.blocking);
    });

    test('all_failing_criteria_are_reported', () {
      final report = _analyzer.analyze(_fill(_side, 12));

      expect(
        _failed(report),
        containsAll(<ImageQualityCriterion>[
          ImageQualityCriterion.exposure,
          ImageQualityCriterion.contrast,
          ImageQualityCriterion.blur,
        ]),
      );
      for (final failure in report.failures) {
        expect(failure.measured.isNaN, isFalse);
        expect(failure.margin, greaterThan(0.0));
      }
    });

    test('ok_report_lists_no_failures', () {
      final report = _analyzer.analyze(_checkerboard(_side, 60, 200));
      expect(report.verdict, ImageQualityVerdict.ok);
      expect(report.failures, isEmpty);
    });

    test('analyzer_failure_is_unvalidated', () {
      final report = _analyzer.analyze(img.Image(width: 0, height: 0));

      expect(report.verdict, ImageQualityVerdict.unvalidated);
      expect(report.metrics, isNull);
      expect(report.failures, isEmpty);
      expect(report.unvalidatedReason, isNotNull);
    });

    test('criteria_are_injectable', () {
      final image = _checkerboard(_side, 60, 200);
      final defaultReport = _analyzer.analyze(image);
      expect(defaultReport.verdict, ImageQualityVerdict.ok);

      final strict = ImageQualityCriteria(
        minContrastScore: defaultReport.metrics!.contrastScore + 10.0,
      );
      final strictReport = _analyzer.analyze(image, criteria: strict);

      expect(strictReport.verdict, ImageQualityVerdict.advisory);
      expect(_failed(strictReport), contains(ImageQualityCriterion.contrast));
    });
  });

  test('orientation_is_baked_before_cropping', () {
    // A tall image with an orientation tag must measure as its rotated pixels
    // do. PNG fixtures carry no EXIF, so this path sits outside the golden and
    // is asserted independently in each language.
    final tall = img.copyResize(
      _checkerboard(_side, 60, 200),
      width: _side,
      height: _side * 2,
      interpolation: img.Interpolation.nearest,
    );
    final rotated = img.copyRotate(tall, angle: 90);

    tall.exif.imageIfd.orientation = 6; // rotate 90 degrees clockwise
    final baked = _analyzer.analyze(tall).metrics!;
    final reference = _analyzer.analyze(rotated).metrics!;

    expect(baked.roiSidePx, reference.roiSidePx);
    expect(baked.meanLuminance, closeTo(reference.meanLuminance, 1e-9));
    expect(baked.blurScore,
        closeTo(reference.blurScore, reference.blurScore.abs() * 1e-9));
  });

  group('cross-language conformance', () {
    late Map<String, dynamic> golden;

    setUpAll(() {
      final file = File('$_fixtureDir/golden.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: '${file.path} is missing. Regenerate it with '
            '`cd ml && python scripts/generate_image_quality_golden.py`.',
      );
      golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    });

    test('dart_matches_golden', () {
      for (final entry in golden['fixtures'] as List<dynamic>) {
        final fixture = entry as Map<String, dynamic>;
        final name = fixture['file'] as String;
        final decoded = img.decodePng(
          File('$_fixtureDir/$name').readAsBytesSync(),
        );
        expect(decoded, isNotNull, reason: 'could not decode $name');

        final report = _analyzer.analyze(decoded!);
        expect(report.verdict.name, fixture['verdict'], reason: name);

        final metrics = report.metrics!;
        final expected = fixture['metrics'] as Map<String, dynamic>;
        expect(metrics.roiSidePx, expected['roi_side_px'], reason: '$name roi');
        expect(metrics.downscaleApplied, expected['downscale_applied'],
            reason: '$name downscale');

        void matches(String key, double actual) {
          final want = (expected[key] as num).toDouble();
          expect(actual, closeTo(want, want.abs() * 1e-9 + 1e-12),
              reason: '$name.$key');
        }

        matches('blur_score', metrics.blurScore);
        matches('mean_luminance', metrics.meanLuminance);
        matches('clipped_fraction', metrics.clippedFraction);
        matches('contrast_score', metrics.contrastScore);
        matches('color_cast_score', metrics.colorCastScore);
        matches('specular_fraction', metrics.specularFraction);
      }
    });

    test('golden_covers_every_criterion', () {
      final sole = <String>{};
      for (final entry in golden['fixtures'] as List<dynamic>) {
        final failures = (entry as Map<String, dynamic>)['failures'] as List;
        if (failures.length == 1) {
          sole.add((failures.single as Map<String, dynamic>)['criterion']
              as String);
        }
      }

      final missing = ImageQualityCriterion.values
          .map((criterion) => criterion.name)
          .toSet()
          .difference(sole);
      expect(missing, isEmpty, reason: 'no fixture isolates: $missing');
    });
  });
}
