import 'dart:math' as math;

import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';
import 'package:visiosoil_app/core/services/descriptors/patch_grid.dart';

/// The contract's numbers the live reading needs, as a record so it can be
/// sent to the reader's isolate once (SPEC 0166).
typedef LiveContract = ({
  double canonicalMmPerPx,
  int patchPx,
  double strideFraction,
  int minPatches,
});

LiveContract liveContractOf(DescriptorContract contract) => (
      canonicalMmPerPx: contract.canonicalMmPerPx,
      patchPx: contract.patchPx,
      strideFraction: contract.patchStrideFraction,
      minPatches: contract.minPatches,
    );

/// What one preview frame says about the sheet and the soil on it.
sealed class LiveReading {
  const LiveReading();
}

/// `findSheet` found no sheet.
final class LiveSheetNotFound extends LiveReading {
  const LiveSheetNotFound();
}

/// `findSheet` found a sheet that runs off the frame.
final class LiveSheetCropped extends LiveReading {
  const LiveSheetCropped({this.sides = const []});

  /// The frame's sides the sheet runs off, most first; empty when the reader
  /// could not tell (SPEC 0169).
  final List<FrameSide> sides;
}

/// A whole sheet, and what is on it.
final class LiveSheetFound extends LiveReading {
  const LiveSheetFound({
    required this.sheetLongSidePx,
    required this.discDiameterMm,
    required this.holdsMinPatches,
    this.corners = const [],
  });

  /// The sheet's long side in the read frame's pixels, for the scale.
  final double sheetLongSidePx;

  /// The soil disc's diameter, or null when `locateSoilDisc` measured none:
  /// no soil, too little contrast, or a patch thinner than its margin, which
  /// the still refuses alike, as `soilRegionTooSmall`.
  final double? discDiameterMm;

  /// Whether the disc holds the contract's `min_patches` patches.
  final bool holdsMinPatches;

  /// The sheet's four corners in the read frame's pixels, which the guides
  /// are coloured by (SPEC 0169); empty when not known.
  final List<({double x, double y})> corners;
}

/// Reads [frame] with the reader that judges the still: `findSheet`,
/// `locateSoilDisc` and `patchGeometry`, with the contract's numbers.
LiveReading readSheet(RgbFrame frame, LiveContract contract) {
  final found = findSheet(frame);
  final corners = found.corners;
  if (corners == null) {
    return switch (found.refusal!) {
      SheetRefusal.cropped => LiveSheetCropped(sides: found.croppedSides),
      SheetRefusal.notFound => const LiveSheetNotFound(),
    };
  }
  final longSide = sheetLongSidePx(corners);
  final disc = locateSoilDisc(frame, corners);
  if (disc == null) {
    return LiveSheetFound(
      sheetLongSidePx: longSide,
      discDiameterMm: null,
      holdsMinPatches: false,
      corners: corners.points,
    );
  }
  final placed = patchGeometry(
    regionDiameterPx: disc.diameterMm / contract.canonicalMmPerPx,
    patchPx: contract.patchPx,
    canonicalMmPerPx: contract.canonicalMmPerPx,
    minPatches: contract.minPatches,
    strideFraction: contract.strideFraction,
  );
  return LiveSheetFound(
    sheetLongSidePx: longSide,
    discDiameterMm: disc.diameterMm,
    holdsMinPatches: placed.geometry != null,
    corners: corners.points,
  );
}

/// The sheet's long side in pixels: the larger mean of two opposite edges,
/// so a keystoned sheet counts both of its long edges.
double sheetLongSidePx(SheetCorners corners) {
  final p = corners.points;
  double edge(int a, int b) =>
      math.sqrt(math.pow(p[a].x - p[b].x, 2) + math.pow(p[a].y - p[b].y, 2));
  final firstPair = (edge(0, 1) + edge(2, 3)) / 2;
  final secondPair = (edge(1, 2) + edge(3, 0)) / 2;
  return math.max(firstPair, secondPair);
}
