import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;

/// The guides' states from the sheet's corners (SPEC 0169).
void main() {
  final layout = CaptureGuideLayout.compute(
    const Size(390, 797),
    topInset: 72,
    bottomInset: 140,
  );
  final outline = layout.outline;
  final w = outline.width;
  const screen = Rect.fromLTRB(0, -47, 390, 797);

  Map<BracketPosition, Offset> vertices() => {
    BracketPosition.topLeft: outline.topLeft,
    BracketPosition.topRight: outline.topRight,
    BracketPosition.bottomRight: outline.bottomRight,
    BracketPosition.bottomLeft: outline.bottomLeft,
  };

  Map<BracketPosition, Offset> transformed(Offset Function(Offset) f) =>
      vertices().map((position, point) => MapEntry(position, f(point)));

  Offset scaled(Offset p, double k) =>
      outline.center + (p - outline.center) * k;

  Offset rotated(Offset p, double degrees) {
    final a = degrees * math.pi / 180;
    final v = p - outline.center;
    return outline.center +
        Offset(
          v.dx * math.cos(a) - v.dy * math.sin(a),
          v.dx * math.sin(a) + v.dy * math.cos(a),
        );
  }

  test('corners_map_to_the_overlay', () {
    // The preview is drawn whole: `BoxFit.contain` (SPEC 0171).
    const scale = 390 / 720;
    final mapped = mapCornersToOverlay(
      corners: const [
        (x: 0, y: 0),
        (x: 576, y: 0),
        (x: 576, y: 1024),
        (x: 0, y: 1024),
      ],
      readSize: const Size(576, 1024),
      previewSize: const Size(720, 1280),
      screenSize: const Size(390, 844),
      safePadding: const EdgeInsets.only(top: 47),
    )!;
    const offsetY = (844 - 1280 * scale) / 2 - 47;
    expect(mapped[0].dx, closeTo(0, 0.5));
    expect(mapped[0].dy, closeTo(offsetY, 0.5));
    expect(mapped[2].dx, closeTo(390, 0.5));
    expect(mapped[2].dy, closeTo(offsetY + 1280 * scale, 0.5));

    expect(
      mapCornersToOverlay(
        corners: const [(x: 0, y: 0), (x: 1, y: 0), (x: 1, y: 1), (x: 0, y: 1)],
        readSize: const Size(768, 1024),
        previewSize: const Size(720, 1280),
        screenSize: const Size(390, 844),
        safePadding: EdgeInsets.zero,
      ),
      isNull,
    );
  });

  test('corners_are_assigned_by_position', () {
    final points = [
      outline.topLeft,
      outline.topRight,
      outline.bottomRight,
      outline.bottomLeft,
    ];
    for (var turn = 0; turn < 4; turn++) {
      final order = [for (var i = 0; i < 4; i++) points[(i + turn) % 4]];
      expect(assignCorners(order), vertices(), reason: 'rotation $turn');
    }
  });

  test('bracket_states_follow_the_distance', () {
    final corners = vertices();
    corners[BracketPosition.topLeft] =
        corners[BracketPosition.topLeft]! + Offset(0.05 * w, 0);
    corners[BracketPosition.topRight] =
        corners[BracketPosition.topRight]! + Offset(0.10 * w, 0);
    corners[BracketPosition.bottomRight] =
        corners[BracketPosition.bottomRight]! + Offset(0, 0.20 * w);
    final alignment = alignSheet(
      corners: corners,
      layout: layout,
      screen: screen,
    );
    expect(alignment.brackets, {
      BracketPosition.topLeft: GuideState.placed,
      BracketPosition.topRight: GuideState.near,
      BracketPosition.bottomRight: GuideState.off,
      BracketPosition.bottomLeft: GuideState.placed,
    });
  });

  test('a_placed_sheet_has_no_fix', () {
    final alignment = alignSheet(
      corners: vertices(),
      layout: layout,
      screen: screen,
    );
    expect(alignment.brackets.values, everyElement(GuideState.placed));
    expect(alignment.fix, isNull);
    expect(alignment.arrow, isNull);
    expect(alignment.offScreen, isEmpty);
  });

  test('arrows_point_the_way_to_move_the_phone', () {
    final shifted = alignSheet(
      corners: transformed((p) => p + Offset(0.1 * w, 0)),
      layout: layout,
      screen: screen,
    );
    expect(shifted.fix, MisalignmentFix.shift);
    expect(shifted.arrow, FrameSide.right);

    final small = alignSheet(
      corners: transformed((p) => scaled(p, 0.7)),
      layout: layout,
      screen: screen,
    );
    expect(small.fix, MisalignmentFix.closer);
    expect(small.arrow, isNull);
  });

  test('misalignment_names_its_fix', () {
    expect(
      alignSheet(
        corners: transformed((p) => scaled(p, 1.3)),
        layout: layout,
        screen: const Rect.fromLTRB(-500, -500, 900, 1300),
      ).fix,
      MisalignmentFix.farther,
    );
    expect(
      alignSheet(
        corners: transformed((p) => rotated(p, 8)),
        layout: layout,
        screen: screen,
      ).fix,
      MisalignmentFix.turn,
    );
    expect(
      alignSheet(
        corners: transformed((p) => p + Offset(0, -0.1 * w)),
        layout: layout,
        screen: screen,
      ).arrow,
      FrameSide.top,
    );
    // A sheet lying across the outline is turned, not too large: its corners
    // are assigned by position, so its long edge runs along the top.
    expect(
      alignSheet(
        corners: assignCorners(
          transformed((p) => rotated(p, 90)).values.toList(),
        ),
        layout: layout,
        screen: const Rect.fromLTRB(-500, -500, 900, 1300),
      ).fix,
      MisalignmentFix.turn,
    );
  });

  test('a_corner_is_assigned_once_at_45_degrees', () {
    final assigned = assignCorners(
      transformed((p) => rotated(p, 45)).values.toList(),
    );
    expect(assigned.values.toSet(), hasLength(4));
  });

  test('a_corner_past_the_screen_is_off_screen', () {
    final corners = vertices();
    corners[BracketPosition.topRight] = Offset(400, outline.top);
    final alignment = alignSheet(
      corners: corners,
      layout: layout,
      screen: screen,
    );
    expect(alignment.offScreen, [FrameSide.right]);
  });

  test('the_target_follows_the_soil_rows', () {
    expect(targetStateFor(null), GuideState.idle);
    expect(targetStateFor(const LiveSheetNotFound()), GuideState.idle);
    expect(targetStateFor(const LiveSheetCropped()), GuideState.idle);
    expect(
      targetStateFor(
        const LiveSheetFound(
          sheetLongSidePx: 900,
          discDiameterMm: null,
          holdsMinPatches: false,
        ),
      ),
      GuideState.idle,
    );
    expect(
      targetStateFor(
        const LiveSheetFound(
          sheetLongSidePx: 900,
          discDiameterMm: 50,
          holdsMinPatches: false,
        ),
      ),
      GuideState.near,
    );
    expect(
      targetStateFor(
        const LiveSheetFound(
          sheetLongSidePx: 900,
          discDiameterMm: 80,
          holdsMinPatches: true,
        ),
      ),
      GuideState.placed,
    );
  });

  test('the_preview_is_shown_whole', () {
    // The Developer's phone: 1220 x 2712 px at 3.25, a 3:4 preview.
    const screenSize = Size(1220 / 3.25, 2712 / 3.25);
    const padding = EdgeInsets.only(top: 40, bottom: 16);
    final preview = previewRectOnOverlay(
      previewSize: const Size(3072, 4096),
      screenSize: screenSize,
      safePadding: padding,
    );
    expect(preview.left, closeTo(0, 0.01));
    expect(preview.width, closeTo(screenSize.width, 0.01));
    expect(preview.height, closeTo(screenSize.width * 4 / 3, 0.01));
    expect(preview.top, greaterThanOrEqualTo(-padding.top));
    expect(
      preview.bottom,
      lessThanOrEqualTo(screenSize.height - padding.top),
    );
    expect(
      preview.center.dy,
      closeTo(screenSize.height / 2 - padding.top, 0.01),
    );
  });

  test('a_corner_inside_the_frame_is_on_screen', () {
    const previewSize = Size(768, 1024);
    const screenSize = Size(390, 844);
    const padding = EdgeInsets.only(top: 47);
    final mapped = mapCornersToOverlay(
      corners: const [
        (x: 5, y: 200),
        (x: 700, y: 200),
        (x: 700, y: 900),
        (x: 5, y: 900),
      ],
      readSize: previewSize,
      previewSize: previewSize,
      screenSize: screenSize,
      safePadding: padding,
    )!;
    final alignment = alignSheet(
      corners: assignCorners(mapped),
      layout: layout,
      screen: previewRectOnOverlay(
        previewSize: previewSize,
        screenSize: screenSize,
        safePadding: padding,
      ),
    );
    expect(alignment.offScreen, isEmpty);
  });
}
