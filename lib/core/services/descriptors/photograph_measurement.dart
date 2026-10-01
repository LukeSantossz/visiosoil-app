/// Where the soil is and how big a pixel is, measured on one photograph
/// (SPEC 0083, ADR 0017).
///
/// The dataset side reads these from the dish rim and records them in its
/// manifest: millimetres per pixel, and the soil region's centre and diameter.
/// The application side measures them from the A4 sheet. The frame is part of
/// the measurement because the sheet reader rectifies the photograph, and the
/// grid must cut from the frame these numbers describe.
library;

import '../classification_report.dart';
import 'patch_grid.dart';

class PhotographMeasurement {
  const PhotographMeasurement({
    required this.frame,
    required this.mmPerPx,
    required this.centreYPx,
    required this.centreXPx,
    required this.diameterPx,
  });

  /// The frame the other four numbers are measured in.
  final RgbFrame frame;
  final double mmPerPx;
  final double centreYPx;
  final double centreXPx;
  final double diameterPx;
}

/// Measures one decoded, oriented photograph: the measurement, or the cause it
/// could not be taken for. Never a guessed scale (ADR 0017).
///
/// An implementation is sent to the inference isolate, so it must be a
/// top-level or static function.
typedef PhotographMeasurer =
    ({PhotographMeasurement? measurement, ClassificationFailureCause? cause})
    Function(RgbFrame frame);
