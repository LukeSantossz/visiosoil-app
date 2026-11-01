// The quality chips' numbers: the ambient light sensor's lux beside the
// light verdict, and the sheet's estimated distance (SPEC 0238).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';

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
}
