/// The result of measuring a soil photograph against the acceptance criteria
/// (SPEC 0030).
library;

/// The seven criteria, in the order a report lists them.
///
/// The names are part of the cross-language contract: they are the strings in
/// `test/fixtures/image_quality/golden.json` and in `ml/src/image_quality.py`.
enum ImageQualityCriterion {
  blur,
  exposure,
  clipping,
  contrast,
  colorCast,
  specular,
  resolution,
}

/// `blur`, `exposure`, `clipping` and `resolution` may block. The other three
/// are advisory until they are calibrated against real images; blocking on an
/// uncalibrated criterion is how a gate starts refusing legitimate work.
const Set<ImageQualityCriterion> blockingCriteria = {
  ImageQualityCriterion.blur,
  ImageQualityCriterion.exposure,
  ImageQualityCriterion.clipping,
  ImageQualityCriterion.resolution,
};

enum ImageQualityVerdict {
  /// Inside every bound. Proceed silently.
  ok,

  /// Analyse, but attach the flags to the result and to the saved record.
  advisory,

  /// Name the defect and offer a retake. The override path is mandatory and
  /// belongs to the capture flow, not to this library (ADR 0009).
  blocking,

  /// The analyzer itself could not run. Never a rejection: a crashed checker
  /// must not block a valid sample.
  unvalidated,
}

/// One criterion that failed, with how far it missed.
///
/// The margin is what recalibration needs: a rejected capture records not just
/// that it failed but by how much.
class CriterionFailure {
  const CriterionFailure({
    required this.criterion,
    required this.severity,
    required this.measured,
    required this.threshold,
    required this.margin,
  });

  final ImageQualityCriterion criterion;

  /// Either [ImageQualityVerdict.blocking] or [ImageQualityVerdict.advisory].
  final ImageQualityVerdict severity;

  final double measured;
  final double threshold;
  final double margin;

  @override
  String toString() =>
      '${criterion.name}: $measured vs $threshold (off by $margin)';
}

/// Every metric, always reported numerically alongside the verdict.
class ImageQualityMetrics {
  const ImageQualityMetrics({
    required this.blurScore,
    required this.meanLuminance,
    required this.clippedFraction,
    required this.contrastScore,
    required this.colorCastScore,
    required this.specularFraction,
    required this.roiSidePx,
    required this.downscaleApplied,
  });

  /// Variance of the 3x3 Laplacian of the 512 px downscaled ROI luma plane.
  final double blurScore;

  /// Mean luma over the ROI, in `[0, 255]`.
  final double meanLuminance;

  /// Fraction of ROI pixels with luma `<= 2.0` or `>= 253.0`.
  final double clippedFraction;

  /// Population standard deviation of luma over the ROI.
  final double contrastScore;

  /// Maximum pairwise channel-mean difference, divided by 255.
  final double colorCastScore;

  /// Fraction of ROI pixels with luma `>= 250.0` and saturation `<= 0.10`.
  final double specularFraction;

  /// Side of the ROI square in source pixels, before any downscale.
  final int roiSidePx;

  /// Whether the blur plane was downscaled. False when the ROI was already at
  /// or below 512 px, in which case the blur score is not comparable with one
  /// measured on a larger source.
  final bool downscaleApplied;
}

class ImageQualityReport {
  const ImageQualityReport({
    required this.verdict,
    required this.metrics,
    required this.failures,
    this.unvalidatedReason,
  });

  /// The report for an analysis that could not run.
  ///
  /// [reason] is required so a failure is reported rather than swallowed.
  const ImageQualityReport.unvalidated(String reason)
      : verdict = ImageQualityVerdict.unvalidated,
        metrics = null,
        failures = const <CriterionFailure>[],
        unvalidatedReason = reason;

  final ImageQualityVerdict verdict;

  /// Null only when the verdict is [ImageQualityVerdict.unvalidated].
  final ImageQualityMetrics? metrics;

  /// Every failing criterion, never short-circuited on the first, so the caller
  /// can name everything that needs fixing in one retake.
  final List<CriterionFailure> failures;

  /// Why the analysis could not run. Set only for
  /// [ImageQualityVerdict.unvalidated].
  final String? unvalidatedReason;
}
