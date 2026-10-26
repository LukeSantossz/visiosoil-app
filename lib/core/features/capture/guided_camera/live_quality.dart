import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';
import 'package:visiosoil_app/core/services/image_quality/image_quality_criteria.dart';

/// Preview-only light and focus estimates. Neither is a calibrated lux reading.
class LiveQuality {
  const LiveQuality({
    required this.lightOk,
    required this.focusOk,
    this.tooBright = false,
  });
  final bool lightOk;
  final bool focusOk;
  final bool tooBright;

  static LiveQuality? measure(RgbFrame frame) {
    // Tiny or missing frames cannot establish image quality.
    if (frame.width < 16 || frame.height < 16) return null;
    const criteria = ImageQualityCriteria();
    final side = frame.width < frame.height ? frame.width : frame.height;
    final left = (frame.width - side) ~/ 2;
    final top = (frame.height - side) ~/ 2;
    double grey(int x, int y) =>
        frame.rgb[(y * frame.width + x) * 3].toDouble();
    var sum = 0.0;
    var lapSum = 0.0;
    var lapSquares = 0.0;
    var count = 0;
    for (var y = top + 1; y < top + side - 1; y++) {
      for (var x = left + 1; x < left + side - 1; x++) {
        final value = grey(x, y);
        final lap =
            grey(x - 1, y) +
            grey(x + 1, y) +
            grey(x, y - 1) +
            grey(x, y + 1) -
            4 * value;
        sum += value;
        lapSum += lap;
        lapSquares += lap * lap;
        count++;
      }
    }
    final mean = sum / count;
    final variance = lapSquares / count - (lapSum / count) * (lapSum / count);
    return LiveQuality(
      lightOk:
          mean >= criteria.minMeanLuminance &&
          mean <= criteria.maxMeanLuminance,
      tooBright: mean > criteria.maxMeanLuminance,
      focusOk: variance >= criteria.minBlurScore,
    );
  }
}
