// The quality chips' numbers: the ambient light sensor's lux beside the
// light verdict, and the sheet's estimated distance (SPEC 0238), handed over
// with the shot they were shown for (SPEC 0240).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

import '../../../support/guided_camera_harness.dart';
import 'guided_camera_v11_test.dart' show readQuality;

QualityChip chipOf(WidgetTester tester, String label) => tester
    .widgetList<QualityChip>(find.byType(QualityChip))
    .singleWhere((chip) => chip.label == label);

/// A sheet spanning 22 of the 32 px a test frame is read at: with a 5.6 mm
/// lens over a 7.3 mm active side, about 337 mm away.
const sheet = LiveSheetFound(
  sheetLongSidePx: 22,
  discDiameterMm: 90,
  holdsMinPatches: true,
);

void main() {
  testWidgets('light_chip_adds_the_sensor_lux', (tester) async {
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    h.light.controller.add(1480);
    await tester.pump();
    final light = chipOf(tester, 'Luz');
    expect(light.value, 'Boa · 1.480 lx');
    expect(light.status, QualityStatus.ready);
    await backOut(tester);
  });

  testWidgets('light_chip_keeps_its_verdict_without_a_sensor', (tester) async {
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    expect(chipOf(tester, 'Luz').value, 'Boa');
    await backOut(tester);
  });

  testWidgets('light_chip_refreshes_at_most_twice_a_second', (tester) async {
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    h.light.controller.add(1480);
    await tester.pump();
    h.light.controller.add(57);
    await tester.pump(const Duration(milliseconds: 400));
    expect(chipOf(tester, 'Luz').value, 'Boa · 1.480 lx');
    await tester.pump(const Duration(milliseconds: 100));
    expect(chipOf(tester, 'Luz').value, 'Boa · 57 lx');
    await backOut(tester);
  });

  testWidgets('distance_chip_shows_the_estimate_for_a_found_sheet', (
    tester,
  ) async {
    final h = GuidedCameraHarness();
    h.optics.optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);
    await openGuidedCamera(tester, harness: h);
    await readQuality(tester, h, good: true, reading: sheet);
    final distance = chipOf(tester, 'Distância');
    expect(distance.value, '≈ 34 cm');
    expect(distance.status, QualityStatus.ready);
    await backOut(tester);
  });

  testWidgets('distance_chip_keeps_a_failed_status_beside_the_estimate', (
    tester,
  ) async {
    final h = GuidedCameraHarness();
    h.optics.optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);
    // A still this small is too coarse for any sheet: the row is too far.
    h.stillSizes.size = const Size(32, 32);
    await openGuidedCamera(tester, harness: h);
    await readQuality(tester, h, good: true, reading: sheet);
    final distance = chipOf(tester, 'Distância');
    expect(distance.value, '≈ 34 cm');
    expect(distance.status, QualityStatus.failed);
    await backOut(tester);
  });

  testWidgets('distance_chip_keeps_its_words_without_optics', (tester) async {
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true, reading: sheet);
    final distance = chipOf(tester, 'Distância');
    expect(distance.value, 'Enquadrada');
    expect(distance.status, QualityStatus.ready);
    await backOut(tester);
  });

  testWidgets('distance_chip_keeps_its_words_without_a_whole_sheet', (
    tester,
  ) async {
    final h = GuidedCameraHarness();
    h.optics.optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);
    await openGuidedCamera(tester, harness: h);
    await readQuality(tester, h, good: true, cropped: true);
    expect(chipOf(tester, 'Distância').value, 'Ajuste a moldura');
    await backOut(tester);
  });

  testWidgets('shot_hands_over_the_shown_numbers', (tester) async {
    final h = GuidedCameraHarness();
    h.optics.optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);
    await openGuidedCamera(tester, harness: h);
    await readQuality(tester, h, good: true, reading: sheet);
    h.light.controller.add(1480);
    await tester.pump();
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    final conditions = (h.popped.single! as GuidedCaptureCaptured).conditions;
    expect(conditions.lux, 1480);
    expect(conditions.distanceMm, closeTo(337, 1));
    expect(conditions.sharp, isTrue);
  });

  testWidgets('shot_hands_over_null_without_numbers', (tester) async {
    final h = await openGuidedCamera(tester);
    await tester.tap(shutter);
    await tester.pumpAndSettle();
    final conditions = (h.popped.single! as GuidedCaptureCaptured).conditions;
    expect(conditions.lux, isNull);
    expect(conditions.distanceMm, isNull);
    expect(conditions.sharp, isNull);
  });

  testWidgets('optics_are_read_for_each_camera', (tester) async {
    final h = await openGuidedCamera(tester);
    expect(h.optics.asked, ['0']);
    await tester.tap(find.byTooltip('Trocar câmera'));
    await tester.pumpAndSettle();
    expect(h.optics.asked, ['0', '1']);
    await backOut(tester);
  });

  testWidgets('light_is_heard_only_while_the_camera_is_live', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = await openGuidedCamera(tester);
    expect(h.light.listening, isTrue);
    await tester.tap(find.byTooltip('Como fotografar'));
    await tester.pumpAndSettle();
    expect(h.light.listening, isFalse);
    await backOut(tester);
    expect(h.light.listening, isTrue);
    expect(h.light.listens, 2);
    await backOut(tester);
    expect(h.light.listening, isFalse);
  });

  // A live region is announced each time its label changes, so the chips
  // speak their verdict and keep the number on screen (SPEC 0263).
  String spokenOf(WidgetTester tester, String label) =>
      tester.getSemantics(find.byWidget(chipOf(tester, label))).label;

  testWidgets('light_chip_announces_the_verdict_without_the_lux', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    h.light.controller.add(1480);
    await tester.pump();
    expect(chipOf(tester, 'Luz').value, 'Boa · 1.480 lx');
    expect(spokenOf(tester, 'Luz'), 'Luz, Boa');
    await backOut(tester);
    semantics.dispose();
  });

  testWidgets('light_chip_label_holds_while_the_lux_changes', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    h.light.controller.add(1480);
    await tester.pump();
    final before = spokenOf(tester, 'Luz');
    h.light.controller.add(57);
    await tester.pump(const Duration(milliseconds: 500));
    expect(chipOf(tester, 'Luz').value, 'Boa · 57 lx');
    expect(spokenOf(tester, 'Luz'), before);
    await backOut(tester);
    semantics.dispose();
  });

  testWidgets('distance_chip_announces_the_verdict_without_the_estimate', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final h = GuidedCameraHarness();
    h.optics.optics = (focalLengthMm: 5.6, activeLongSideMm: 7.3);
    await openGuidedCamera(tester, harness: h);
    await readQuality(tester, h, good: true, reading: sheet);
    expect(chipOf(tester, 'Distância').value, '≈ 34 cm');
    expect(spokenOf(tester, 'Distância'), 'Distância, Enquadrada');
    await backOut(tester);
    semantics.dispose();
  });

  testWidgets('focus_chip_announces_its_value', (tester) async {
    final semantics = tester.ensureSemantics();
    final h = await openGuidedCamera(tester);
    await readQuality(tester, h, good: true);
    expect(spokenOf(tester, 'Foco'), 'Foco, Nítido');
    await backOut(tester);
    semantics.dispose();
  });

  // The value keeps to one line, so the panel does not grow when a long
  // number appears (SPEC 0263).
  testWidgets('chip_height_does_not_follow_its_value', (tester) async {
    Future<double> heightWith(String value) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
            child: Center(
              child: SizedBox(
                width: 90,
                child: QualityChip(
                  label: 'Luz',
                  value: value,
                  status: QualityStatus.failed,
                ),
              ),
            ),
          ),
        ),
      );
      return tester.getSize(find.byType(QualityChip)).height;
    }

    final short = await heightWith('Boa');
    expect(await heightWith('Excessiva · 12.350 lx'), short);
  });
}
