import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/services/descriptors/descriptor_contract.dart';

void main() {
  test('the_guide_has_the_sheets_proportions', () {
    for (final screen in const [Size(390, 844), Size(360, 640)]) {
      const top = 72.0;
      const bottom = 140.0;
      final layout = CaptureGuideLayout.compute(
        screen,
        topInset: top,
        bottomInset: bottom,
      );
      final outline = layout.outline;
      expect(
        outline.height / outline.width,
        closeTo(297 / 210, 297 / 210 * 0.005),
        reason: '$screen',
      );
      final available = screen.height - top - bottom;
      final expectedWidth =
          math.min(0.85 * screen.width, 0.85 * available * 210 / 297);
      expect(outline.width, closeTo(expectedWidth, 0.01), reason: '$screen');
      final expectedDiameter = outline.width * 90 / 210;
      expect(
        layout.targetDiameter,
        closeTo(expectedDiameter, expectedDiameter * 0.005),
        reason: '$screen',
      );
      expect(
        (layout.targetCentre - outline.center).distance,
        lessThanOrEqualTo(1),
        reason: '$screen',
      );
      expect(outline.center.dx, closeTo(screen.width / 2, 1));
      expect(outline.center.dy, closeTo(top + available / 2, 1));
    }
  });

  test('the_outline_lies_in_the_preview', () {
    const size = Size(375, 778);
    const top = 72.0;
    const bottom = 140.0;
    for (final preview in const [
      Rect.fromLTWH(0, 127, 375, 500),
      Rect.fromLTWH(0, 40, 375, 700),
    ]) {
      final layout = CaptureGuideLayout.compute(
        size,
        topInset: top,
        bottomInset: bottom,
        preview: preview,
      );
      final region = preview.intersect(
        const Rect.fromLTRB(0, top, 375, 778 - bottom),
      );
      final outline = layout.outline;
      expect(region.contains(outline.topLeft), isTrue, reason: '$preview');
      expect(
        region.inflate(0.01).contains(outline.bottomRight),
        isTrue,
        reason: '$preview',
      );
      expect(
        outline.width,
        closeTo(
          math.min(0.85 * region.width, 0.85 * region.height * 210 / 297),
          0.01,
        ),
        reason: '$preview',
      );
      expect(outline.center.dx, closeTo(region.center.dx, 0.01));
      expect(outline.center.dy, closeTo(region.center.dy, 0.01));
    }
  });

  test('a_sheet_filling_the_outline_reaches_the_scale', () {
    // The Developer's phone: 1220 x 2712 px at 3.25, its 3072 x 4096 still,
    // and the overlay in the safe area between the banner and the footer.
    const screen = Size(1220 / 3.25, 2712 / 3.25);
    const padding = EdgeInsets.only(top: 40, bottom: 16);
    const still = Size(3072, 4096);
    final preview = previewRectOnOverlay(
      previewSize: still,
      screenSize: screen,
      safePadding: padding,
    );
    final outline = CaptureGuideLayout.compute(
      padding.deflateSize(screen),
      topInset: 72,
      bottomInset: 140,
      preview: preview,
    ).outline;
    final canonical = parseDescriptorContract(
      File('assets/models/spec.json').readAsStringSync(),
    ).contract!.canonicalMmPerPx;

    final mmPerPx = math.max(
      210 / (outline.width / preview.width * still.width),
      297 / (outline.height / preview.height * still.height),
    );
    expect(mmPerPx, lessThanOrEqualTo(canonical / 1.1));
  });

  testWidgets('the_overlay_labels_the_target', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaptureGuideOverlay(
        topInset: 72,
        bottomInset: 140,
        tilt: 3,
        direction: Offset(0.6, 0.8),
      ),
    ));
    expect(find.text('8–10 cm de solo'), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-camera-level')), findsOneWidget);
  });

  testWidgets('the_level_is_hidden_without_a_tilt', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CaptureGuideOverlay(
        topInset: 72,
        bottomInset: 140,
        tilt: null,
        direction: Offset.zero,
      ),
    ));
    expect(find.text('8–10 cm de solo'), findsOneWidget);
    expect(find.byKey(const ValueKey('guided-camera-level')), findsNothing);
  });
}
