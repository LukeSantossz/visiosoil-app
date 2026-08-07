/// Soil image acceptance criteria — the Dart half (SPEC 0030).
///
/// One criteria set governs both what enters the dataset and what the app is
/// allowed to produce (ADR 0009). The Python half is `ml/src/image_quality.py`;
/// the two agree by construction of `test/fixtures/image_quality/golden.json`,
/// and a divergence fails both suites.
///
/// Everything here is pure arithmetic over pixels: no model, no I/O, no state.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_quality_criteria.dart';
import 'image_quality_report.dart';

/// ITU-R BT.601 luma, on 8-bit channel values as `double`, no rounding.
const double _lumaR = 0.299;
const double _lumaG = 0.587;
const double _lumaB = 0.114;

/// Fixed points of the metric definitions. These are not thresholds and are not
/// tunable: changing one changes what the metric means, so both languages and
/// every calibration would have to move together.
const double _darkClipLuma = 2.0;
const double _brightClipLuma = 253.0;
const double _specularLuma = 250.0;
const double _specularSaturation = 0.10;
const int _downscaleSidePx = 512;

/// The largest centred square of a `width` x `height` image.
({int x, int y, int side}) roiBounds(int width, int height) {
  final side = math.min(width, height);
  return (x: (width - side) ~/ 2, y: (height - side) ~/ 2, side: side);
}

class ImageQualityAnalyzer {
  const ImageQualityAnalyzer();

  /// Measure [source] and return a verdict.
  ///
  /// A failure of the analyzer itself yields [ImageQualityVerdict.unvalidated]
  /// with its cause attached, never a rejection and never a thrown exception:
  /// a crashed checker must not block a valid sample, and making it a verdict
  /// rather than an exception means the caller cannot forget the case.
  ImageQualityReport analyze(
    img.Image source, {
    ImageQualityCriteria criteria = const ImageQualityCriteria(),
  }) {
    final ImageQualityMetrics metrics;
    try {
      metrics = measure(source);
    } catch (error) {
      return ImageQualityReport.unvalidated('$error');
    }

    final failures = evaluate(metrics, criteria);
    final ImageQualityVerdict verdict;
    if (failures.any((f) => f.severity == ImageQualityVerdict.blocking)) {
      verdict = ImageQualityVerdict.blocking;
    } else if (failures.isNotEmpty) {
      verdict = ImageQualityVerdict.advisory;
    } else {
      verdict = ImageQualityVerdict.ok;
    }

    return ImageQualityReport(
      verdict: verdict,
      metrics: metrics,
      failures: failures,
    );
  }

  /// Compute the seven metrics over the ROI. Throws on an unusable image.
  ImageQualityMetrics measure(img.Image source) {
    final baked = _bakeOrientation(source);
    final bounds = roiBounds(baked.width, baked.height);
    if (bounds.side <= 0) {
      throw ArgumentError(
        'image has a zero-length side: ${baked.width}x${baked.height}',
      );
    }

    final side = bounds.side;
    final count = side * side;
    final luma = Float64List(count);

    var sumRed = 0.0;
    var sumGreen = 0.0;
    var sumBlue = 0.0;
    var clipped = 0;
    var specular = 0;

    final pixels = baked.getRange(bounds.x, bounds.y, side, side);
    var i = 0;
    while (pixels.moveNext()) {
      final pixel = pixels.current;
      final red = pixel.r.toDouble();
      final green = pixel.g.toDouble();
      final blue = pixel.b.toDouble();

      final value = _lumaR * red + _lumaG * green + _lumaB * blue;
      luma[i++] = value;

      sumRed += red;
      sumGreen += green;
      sumBlue += blue;

      if (value <= _darkClipLuma || value >= _brightClipLuma) {
        clipped++;
      }
      if (value >= _specularLuma) {
        final brightest = math.max(red, math.max(green, blue));
        final darkest = math.min(red, math.min(green, blue));
        final saturation =
            brightest > 0.0 ? (brightest - darkest) / brightest : 0.0;
        if (saturation <= _specularSaturation) {
          specular++;
        }
      }
    }

    final meanRed = sumRed / count;
    final meanGreen = sumGreen / count;
    final meanBlue = sumBlue / count;
    final cast = math.max(
      (meanRed - meanGreen).abs(),
      math.max((meanRed - meanBlue).abs(), (meanGreen - meanBlue).abs()),
    );

    var sumLuma = 0.0;
    for (final value in luma) {
      sumLuma += value;
    }
    final meanLuma = sumLuma / count;

    var sumSquares = 0.0;
    for (final value in luma) {
      final deviation = value - meanLuma;
      sumSquares += deviation * deviation;
    }

    final downscaleApplied = side > _downscaleSidePx;
    final blurPlane =
        downscaleApplied ? _boxDownscale(luma, side, _downscaleSidePx) : luma;
    final blurSide = downscaleApplied ? _downscaleSidePx : side;

    return ImageQualityMetrics(
      blurScore: _laplacianVariance(blurPlane, blurSide),
      meanLuminance: meanLuma,
      clippedFraction: clipped / count,
      contrastScore: math.sqrt(sumSquares / count),
      colorCastScore: cast / 255.0,
      specularFraction: specular / count,
      roiSidePx: side,
      downscaleApplied: downscaleApplied,
    );
  }

  /// Every failing criterion, in metric-table order.
  ///
  /// Never short-circuits: the caller must be able to name everything that
  /// needs fixing in one retake.
  List<CriterionFailure> evaluate(
    ImageQualityMetrics metrics,
    ImageQualityCriteria criteria,
  ) {
    final failures = <CriterionFailure>[];

    if (metrics.blurScore < criteria.minBlurScore) {
      failures.add(_failure(
          ImageQualityCriterion.blur, metrics.blurScore, criteria.minBlurScore));
    }

    if (metrics.meanLuminance < criteria.minMeanLuminance) {
      failures.add(_failure(ImageQualityCriterion.exposure,
          metrics.meanLuminance, criteria.minMeanLuminance));
    } else if (metrics.meanLuminance > criteria.maxMeanLuminance) {
      failures.add(_failure(ImageQualityCriterion.exposure,
          metrics.meanLuminance, criteria.maxMeanLuminance));
    }

    if (metrics.clippedFraction > criteria.maxClippedFraction) {
      failures.add(_failure(ImageQualityCriterion.clipping,
          metrics.clippedFraction, criteria.maxClippedFraction));
    }

    if (metrics.contrastScore < criteria.minContrastScore) {
      failures.add(_failure(ImageQualityCriterion.contrast,
          metrics.contrastScore, criteria.minContrastScore));
    }

    if (metrics.colorCastScore > criteria.maxColorCastScore) {
      failures.add(_failure(ImageQualityCriterion.colorCast,
          metrics.colorCastScore, criteria.maxColorCastScore));
    }

    if (metrics.specularFraction > criteria.maxSpecularFraction) {
      failures.add(_failure(ImageQualityCriterion.specular,
          metrics.specularFraction, criteria.maxSpecularFraction));
    }

    if (metrics.roiSidePx < criteria.minRoiSidePx) {
      failures.add(_failure(ImageQualityCriterion.resolution,
          metrics.roiSidePx.toDouble(), criteria.minRoiSidePx.toDouble()));
    }

    return failures;
  }
}

img.Image _bakeOrientation(img.Image source) {
  final ifd = source.exif.imageIfd;
  if (!ifd.hasOrientation || ifd.orientation == 1) {
    return source;
  }
  return img.bakeOrientation(source);
}

CriterionFailure _failure(
  ImageQualityCriterion criterion,
  double measured,
  double threshold,
) {
  return CriterionFailure(
    criterion: criterion,
    severity: blockingCriteria.contains(criterion)
        ? ImageQualityVerdict.blocking
        : ImageQualityVerdict.advisory,
    measured: measured,
    threshold: threshold,
    margin: (measured - threshold).abs(),
  );
}

/// One output pixel's source span: where it starts and its coverage weights.
class _AreaSpan {
  const _AreaSpan(this.start, this.weights);

  final int start;
  final Float64List weights;
}

/// Area-weighted average downscale of a square plane to [target] a side.
///
/// Defined arithmetically rather than delegated to `copyResize`, because the
/// two languages' bilinear filters are different algorithms and would never
/// agree to the conformance tolerance. An area filter is also what makes the
/// blur score comparable across capture resolutions: a point-sampled bilinear
/// ignores most source pixels when shrinking, so a high-frequency pattern would
/// alias differently at each source size.
///
/// Horizontal pass first, then vertical, matching SPEC 0030.
Float64List _boxDownscale(Float64List plane, int side, int target) {
  final spans = _areaSpans(side, target);

  final horizontal = Float64List(side * target);
  for (var y = 0; y < side; y++) {
    final row = y * side;
    final out = y * target;
    for (var j = 0; j < target; j++) {
      final span = spans[j];
      var sum = 0.0;
      for (var k = 0; k < span.weights.length; k++) {
        sum += plane[row + span.start + k] * span.weights[k];
      }
      horizontal[out + j] = sum;
    }
  }

  final result = Float64List(target * target);
  for (var i = 0; i < target; i++) {
    final span = spans[i];
    final out = i * target;
    for (var j = 0; j < target; j++) {
      var sum = 0.0;
      for (var k = 0; k < span.weights.length; k++) {
        sum += horizontal[(span.start + k) * target + j] * span.weights[k];
      }
      result[out + j] = sum;
    }
  }

  return result;
}

List<_AreaSpan> _areaSpans(int source, int target) {
  final scale = source / target;
  return List<_AreaSpan>.generate(target, (j) {
    final start = j * scale;
    final end = (j + 1) * scale;
    final first = start.floor();
    final last = math.min(end.ceil(), source);
    final weights = Float64List(last - first);
    for (var i = first; i < last; i++) {
      final overlap = math.min(end, i + 1.0) - math.max(start, i.toDouble());
      weights[i - first] = overlap > 0.0 ? overlap / scale : 0.0;
    }
    return _AreaSpan(first, weights);
  });
}

/// Population variance of the 3x3 Laplacian over interior pixels only.
///
/// Kernel `[[0, 1, 0], [1, -4, 1], [0, 1, 0]]`. No padding and no border
/// extension, so an invented edge cannot contribute to the score.
double _laplacianVariance(Float64List plane, int side) {
  if (side < 3) {
    throw ArgumentError('plane too small for a 3x3 kernel: $side');
  }

  final interior = side - 2;
  final responses = Float64List(interior * interior);
  var sum = 0.0;

  for (var y = 1; y < side - 1; y++) {
    final row = y * side;
    final above = row - side;
    final below = row + side;
    for (var x = 1; x < side - 1; x++) {
      final response = plane[above + x] +
          plane[below + x] +
          plane[row + x - 1] +
          plane[row + x + 1] -
          4.0 * plane[row + x];
      responses[(y - 1) * interior + (x - 1)] = response;
      sum += response;
    }
  }

  final mean = sum / responses.length;
  var sumSquares = 0.0;
  for (final response in responses) {
    final deviation = response - mean;
    sumSquares += deviation * deviation;
  }
  return sumSquares / responses.length;
}
