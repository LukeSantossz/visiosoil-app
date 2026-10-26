// With Configurações' "Guia de enquadramento" off, the guided camera only
// shoots (SPEC 0208).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';
import 'package:visiosoil_app/providers/capture_preferences_provider.dart';

import '../../../support/guided_camera_harness.dart';

void main() {
  testWidgets('guide_off_hides_the_guide', (tester) async {
    final h = await openGuidedCamera(
      tester,
      overrides: [initialFrameGuideProvider.overrideWithValue(false)],
    );

    expect(find.byType(QualityChip), findsNothing);
    expect(find.byType(CaptureGuideOverlay), findsNothing);
    expect(find.byKey(const ValueKey('guided-camera-banner')), findsNothing);
    expect(find.textContaining('Captura liberada'), findsNothing);

    // Nothing reads the preview, so nothing can hold the shutter.
    expect(h.readers, isEmpty);
    expect(
      h.cameras.log.where((call) => call.startsWith('startFrames')),
      isEmpty,
    );
    await tester.tap(shutter);
    await tester.pumpAndSettle();

    expect(h.cameras.cameras.single.takePictureCalls, 1);
    expect(h.popped.single, isA<GuidedCaptureCaptured>());
  });

  testWidgets('guide_on_keeps_the_guide', (tester) async {
    await openGuidedCamera(tester);

    expect(find.byType(QualityChip), findsNWidgets(3));
    expect(find.byType(CaptureGuideOverlay), findsOneWidget);
    expect(find.textContaining('Captura liberada'), findsOneWidget);
  });
}
