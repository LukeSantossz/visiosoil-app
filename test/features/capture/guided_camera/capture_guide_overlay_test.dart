import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';

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
