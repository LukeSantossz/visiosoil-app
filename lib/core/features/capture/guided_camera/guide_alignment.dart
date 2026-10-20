import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;

/// Where each guide stands against the sheet the live reader found
/// (SPEC 0169): the corner brackets by their corner's distance, the soil
/// target by the soil rows, and what the user should do about it.

/// A guide's state, drawn in its own colour.
enum GuideState { idle, placed, near, off }

/// One of the outline's four corner brackets.
enum BracketPosition { topLeft, topRight, bottomRight, bottomLeft }

/// What a misaligned sheet needs: a shift of the phone, the phone closer or
/// farther, or a turn.
enum MisalignmentFix { shift, closer, farther, turn }

/// Each bracket's state; [arrow] the way to move the phone, set only when
/// the sheet is mostly shifted; [fix] null when every bracket is placed;
/// [offScreen] the screen's sides a corner falls past, furthest first.
typedef SheetAlignment = ({
  Map<BracketPosition, GuideState> brackets,
  FrameSide? arrow,
  MisalignmentFix? fix,
  List<FrameSide> offScreen,
});

/// A corner within this fraction of the outline's width of its bracket is
/// placed, and within [nearFraction] near. First values, for the field
/// session to tune.
const double placedFraction = 0.06;
const double nearFraction = 0.15;

/// A mean corner displacement over this fraction of the outline's width is a
/// shift, which an arrow can fix.
const double shiftFraction = 0.06;

/// A sheet narrower than [smallerThan] of the outline asks for the phone
/// closer, and wider than [largerThan] farther.
const double smallerThan = 0.85;
const double largerThan = 1.15;

/// How far the read frame's aspect may differ from the preview's before the
/// corners are not trusted on the screen.
const double aspectTolerance = 0.02;

const Map<BracketPosition, GuideState> allIdle = {
  BracketPosition.topLeft: GuideState.idle,
  BracketPosition.topRight: GuideState.idle,
  BracketPosition.bottomRight: GuideState.idle,
  BracketPosition.bottomLeft: GuideState.idle,
};

/// The preview's rectangle on the overlay: drawn whole, `BoxFit.contain`,
/// centred on the screen (SPEC 0171), in the coordinates of an overlay laid
/// out inside [safePadding].
Rect previewRectOnOverlay({
  required Size previewSize,
  required Size screenSize,
  required EdgeInsets safePadding,
}) {
  final scale = math.min(
    screenSize.width / previewSize.width,
    screenSize.height / previewSize.height,
  );
  final shown = previewSize * scale;
  return Rect.fromLTWH(
    (screenSize.width - shown.width) / 2 - safePadding.left,
    (screenSize.height - shown.height) / 2 - safePadding.top,
    shown.width,
    shown.height,
  );
}

/// [corners], in the read frame's pixels, on the overlay: through the
/// preview's `BoxFit.contain` on the screen (SPEC 0171), less the safe area
/// the overlay is laid out in. Null unless there are four corners and the
/// read frame has the preview's aspect within [aspectTolerance]: a frame of
/// another aspect does not see what the screen shows.
List<Offset>? mapCornersToOverlay({
  required List<({double x, double y})> corners,
  required Size readSize,
  required Size previewSize,
  required Size screenSize,
  required EdgeInsets safePadding,
}) {
  if (corners.length != 4 || readSize.isEmpty || previewSize.isEmpty) {
    return null;
  }
  final readAspect = readSize.width / readSize.height;
  final previewAspect = previewSize.width / previewSize.height;
  if ((readAspect / previewAspect - 1).abs() > aspectTolerance) return null;
  final shown = previewRectOnOverlay(
    previewSize: previewSize,
    screenSize: screenSize,
    safePadding: safePadding,
  );
  return [
    for (final c in corners)
      shown.topLeft +
          Offset(
            c.x / readSize.width * shown.width,
            c.y / readSize.height * shown.height,
          ),
  ];
}

/// Each corner to one bracket by its position on the screen: the corners in
/// clockwise order around their centre, starting from the one with the least
/// x + y. Each corner gets exactly one bracket, however the sheet is turned.
Map<BracketPosition, Offset> assignCorners(List<Offset> corners) {
  final centre = corners.reduce((a, b) => a + b) / corners.length.toDouble();
  // The screen's y runs down, so a growing angle turns clockwise.
  final around = [...corners]
    ..sort((a, b) => (a - centre).direction.compareTo((b - centre).direction));
  final first = around.indexOf(
    around.reduce((a, b) => a.dx + a.dy <= b.dx + b.dy ? a : b),
  );
  return {
    for (final (i, position) in BracketPosition.values.indexed)
      position: around[(first + i) % around.length],
  };
}

Offset _vertex(Rect outline, BracketPosition position) => switch (position) {
  BracketPosition.topLeft => outline.topLeft,
  BracketPosition.topRight => outline.topRight,
  BracketPosition.bottomRight => outline.bottomRight,
  BracketPosition.bottomLeft => outline.bottomLeft,
};

/// The guides' states for a sheet whose [corners] lie on the overlay, with
/// [screen] what the screen shows of the frame in the overlay's coordinates:
/// the preview's rectangle, since the preview is drawn whole (SPEC 0171).
SheetAlignment alignSheet({
  required Map<BracketPosition, Offset> corners,
  required CaptureGuideLayout layout,
  required Rect screen,
}) {
  final outline = layout.outline;
  final width = outline.width;
  final brackets = <BracketPosition, GuideState>{};
  var displacement = Offset.zero;
  for (final position in BracketPosition.values) {
    final offset = corners[position]! - _vertex(outline, position);
    displacement += offset / BracketPosition.values.length.toDouble();
    final distance = offset.distance / width;
    brackets[position] = distance <= placedFraction
        ? GuideState.placed
        : distance <= nearFraction
        ? GuideState.near
        : GuideState.off;
  }

  MisalignmentFix? fix;
  FrameSide? arrow;
  if (brackets.values.any((state) => state != GuideState.placed)) {
    double edge(BracketPosition a, BracketPosition b) =>
        (corners[a]! - corners[b]!).distance;
    final sheetWidth = (edge(BracketPosition.topRight, BracketPosition.topLeft) +
            edge(BracketPosition.bottomRight, BracketPosition.bottomLeft)) /
        2;
    final sheetHeight =
        (edge(BracketPosition.bottomLeft, BracketPosition.topLeft) +
                edge(BracketPosition.bottomRight, BracketPosition.topRight)) /
            2;
    if (displacement.distance > shiftFraction * width) {
      fix = MisalignmentFix.shift;
      arrow = displacement.dx.abs() >= displacement.dy.abs()
          ? (displacement.dx > 0 ? FrameSide.right : FrameSide.left)
          : (displacement.dy > 0 ? FrameSide.bottom : FrameSide.top);
    } else if (sheetWidth > sheetHeight) {
      // The sheet lies across the outline: no distance fixes that.
      fix = MisalignmentFix.turn;
    } else if (sheetWidth < smallerThan * width) {
      fix = MisalignmentFix.closer;
    } else if (sheetWidth > largerThan * width) {
      fix = MisalignmentFix.farther;
    } else {
      fix = MisalignmentFix.turn;
    }
  }

  final overshoot = <FrameSide, double>{};
  void note(FrameSide side, double by) {
    if (by > (overshoot[side] ?? 0)) overshoot[side] = by;
  }

  for (final c in corners.values) {
    note(FrameSide.left, screen.left - c.dx);
    note(FrameSide.top, screen.top - c.dy);
    note(FrameSide.right, c.dx - screen.right);
    note(FrameSide.bottom, c.dy - screen.bottom);
  }
  final offScreen = [
    for (final entry
        in overshoot.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
      entry.key,
  ];
  return (brackets: brackets, arrow: arrow, fix: fix, offScreen: offScreen);
}

/// The soil target's state, from the soil rows the banner already reads
/// (SPEC 0166): idle until a disc is measured, near while it holds too few
/// patches, placed once it holds enough.
GuideState targetStateFor(LiveReading? reading) => switch (reading) {
  LiveSheetFound(discDiameterMm: null) => GuideState.idle,
  LiveSheetFound(holdsMinPatches: false) => GuideState.near,
  LiveSheetFound() => GuideState.placed,
  _ => GuideState.idle,
};
