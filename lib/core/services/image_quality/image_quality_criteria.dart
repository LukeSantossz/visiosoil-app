/// Thresholds for the soil image acceptance criteria (SPEC 0030).
///
/// **Every default here is PROVISIONAL.** They are engineering starting points,
/// not calibrated values: no real soil images exist to calibrate against
/// (`docs/architecture/soil-classification.md` §4). They live in a value object
/// so a later phase can recalibrate without touching the analyzer, and so a
/// dataset audit and a capture gate can be pinned to the same criteria.
///
/// The Python half of this contract is `ml/src/image_quality.py`; the two are
/// held together by `test/fixtures/image_quality/golden.json`.
class ImageQualityCriteria {
  const ImageQualityCriteria({
    this.minBlurScore = 100.0,
    this.minMeanLuminance = 40.0,
    this.maxMeanLuminance = 215.0,
    this.maxClippedFraction = 0.05,
    this.minContrastScore = 20.0,
    this.maxColorCastScore = 0.15,
    this.maxSpecularFraction = 0.10,
    this.minRoiSidePx = 512,
  });

  /// Minimum variance of the Laplacian. Below this the photo is out of focus.
  final double minBlurScore;

  /// Bounds on mean luma. Outside them the photo is too dark or too bright.
  final double minMeanLuminance;
  final double maxMeanLuminance;

  /// Maximum fraction of pixels burnt out or crushed to black.
  final double maxClippedFraction;

  /// Minimum luma standard deviation. Below this the photo is flat.
  final double minContrastScore;

  /// Maximum channel-mean spread. Above this the photo carries a colour tint,
  /// which matters here because soil colour is part of the signal.
  final double maxColorCastScore;

  /// Maximum fraction of bright, unsaturated pixels — a flash or a hotspot.
  final double maxSpecularFraction;

  /// Minimum ROI side. Below this there are too few pixels to work with.
  final int minRoiSidePx;
}
