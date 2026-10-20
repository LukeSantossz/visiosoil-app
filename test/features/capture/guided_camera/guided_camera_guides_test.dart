import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guided_camera_screen.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_frame.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;

import '../../../support/guided_camera_harness.dart';

/// The guides react to where the sheet lies, and warn when it leaves the
/// screen (SPEC 0169). The phone is 390 × 844 with no safe-area padding, and
/// the preview stream has the preview's own aspect, so corners are mapped.
/// The preview is drawn whole, `BoxFit.contain` (SPEC 0171).
const _screen = Size(390, 844);
const _readWidth = 576, _readHeight = 1024;
const _scale = 390 / 720;
const _shownHeight = 1280 * _scale;
const _originY = (844 - _shownHeight) / 2;

final _layout = CaptureGuideLayout.compute(
  _screen,
  topInset: GuidedCameraScreen.bannerHeight,
  bottomInset: GuidedCameraScreen.footerHeight,
  preview: const Rect.fromLTWH(0, _originY, 390, _shownHeight),
);
final _outline = _layout.outline;

final _warning = find.byKey(const ValueKey('guided-camera-warning'));
final _ring = find.byKey(const ValueKey('guided-camera-ring'));
Finder _glow(FrameSide side) =>
    find.byKey(ValueKey('guided-camera-glow-${side.name}'));

void _phone(WidgetTester tester) {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// An overlay point as a corner in the read frame's pixels.
({double x, double y}) _toFrame(Offset p) => (
  x: p.dx / 390 * _readWidth,
  y: (p.dy - _originY) / _shownHeight * _readHeight,
);

LiveSheetFound _sheetAt(List<Offset> corners, {bool enoughSoil = true}) =>
    LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: 70,
      holdsMinPatches: enoughSoil,
      corners: [for (final c in corners) _toFrame(c)],
    );

List<Offset> get _vertices => [
  _outline.topLeft,
  _outline.topRight,
  _outline.bottomRight,
  _outline.bottomLeft,
];

final CameraFrame _sizedFrame = (
  format: LivePixelFormat.yuv420,
  width: _readWidth,
  height: _readHeight,
  bytes: Uint8List(_readWidth * _readHeight),
  bytesPerRow: _readWidth,
);

/// One reading of a preview-sized frame, answered with [reading].
Future<void> _read(
  WidgetTester tester,
  GuidedCameraHarness h,
  LiveReading reading,
) async {
  h.cameras.cameras.last.emitFrame(_sizedFrame);
  await tester.pump();
  h.readers.last.reply(reading);
  await tester.pump();
  await tester.pump();
}

/// Two agreeing readings, which the debounce lets through.
Future<void> _readTwice(
  WidgetTester tester,
  GuidedCameraHarness h,
  LiveReading reading,
) async {
  await _read(tester, h, reading);
  await _read(tester, h, reading);
}

CaptureGuideOverlay _overlay(WidgetTester tester) =>
    tester.widget<CaptureGuideOverlay>(find.byType(CaptureGuideOverlay));

Future<GuidedCameraHarness> _open(WidgetTester tester) async {
  _phone(tester);
  final h = await openGuidedCamera(tester);
  await tiltTo(tester, h, 0);
  return h;
}

void main() {
  testWidgets('the_brackets_turn_green_when_placed', (tester) async {
    final h = await _open(tester);
    expect(_overlay(tester).brackets, allIdle);
    await _readTwice(tester, h, _sheetAt(_vertices));
    expect(_overlay(tester).brackets.values, everyElement(GuideState.placed));
    expect(_overlay(tester).target, GuideState.placed);
  });

  testWidgets('a_shifted_sheet_shows_arrows', (tester) async {
    final h = await _open(tester);
    // Short of the screen edge, so the sheet is shifted, not off the screen.
    final shift = Offset(0.08 * _outline.width, 0);
    await _readTwice(
      tester,
      h,
      _sheetAt([for (final v in _vertices) v + shift]),
    );
    expect(_overlay(tester).arrow, FrameSide.right);
    expect(_overlay(tester).brackets.values, everyElement(GuideState.near));
    expect(bannerText(tester), 'Leve o celular para a direita.');
  });

  // R2 round 1: an arrow only ever says what the banner says.
  testWidgets('no_arrow_while_the_banner_asks_for_something_else',
      (tester) async {
    _phone(tester);
    // A still this small makes every reading too coarse.
    final h = GuidedCameraHarness()..stillSizes.size = const Size(300, 400);
    await openGuidedCamera(tester, harness: h);
    await tiltTo(tester, h, 0);
    final shift = Offset(0.08 * _outline.width, 0);
    await _readTwice(
      tester,
      h,
      _sheetAt([for (final v in _vertices) v + shift]),
    );
    expect(bannerText(tester), 'Aproxime o celular da folha.');
    expect(_overlay(tester).arrow, isNull);
    expect(_overlay(tester).brackets.values, everyElement(GuideState.near));
  });

  testWidgets('the_trigger_needs_every_guide_green', (tester) async {
    final h = await _open(tester);
    final oneOff = _vertices;
    oneOff[1] = oneOff[1] + Offset(0, 0.1 * _outline.width);
    await _readTwice(tester, h, _sheetAt(oneOff));
    expect(_ring, findsNothing);

    await _readTwice(tester, h, _sheetAt(_vertices));
    expect(_ring, findsOneWidget);
  });

  testWidgets('a_cropped_sheet_warns_by_its_side', (tester) async {
    final h = await _open(tester);
    await _readTwice(
      tester,
      h,
      const LiveSheetCropped(sides: [FrameSide.right]),
    );
    expect(_glow(FrameSide.right), findsOneWidget);
    expect(_glow(FrameSide.left), findsNothing);
    expect(_warning, findsOneWidget);
    expect(find.text('A folha saiu da tela'), findsOneWidget);
    expect(find.text('Leve o celular para a direita'), findsOneWidget);
    expect(bannerText(tester), 'A folha saiu pela direita.');
    expect(_overlay(tester).brackets.values, everyElement(GuideState.off));
    expect(_overlay(tester).arrow, isNull);

    await _readTwice(
      tester,
      h,
      const LiveSheetCropped(sides: [FrameSide.left, FrameSide.right]),
    );
    expect(_glow(FrameSide.left), findsOneWidget);
    expect(_glow(FrameSide.right), findsOneWidget);
    expect(find.text('Afaste o celular da folha'), findsOneWidget);

    await _readTwice(tester, h, const LiveSheetCropped());
    expect(bannerText(tester), 'A folha está cortada. Afaste o celular.');
    expect(_glow(FrameSide.left), findsNothing);
    expect(_glow(FrameSide.right), findsNothing);
  });

  testWidgets('a_corner_past_the_screen_counts_as_leaving_it', (tester) async {
    final h = await _open(tester);
    final past = _vertices;
    past[1] = Offset(_screen.width + 10, past[1].dy);
    await _readTwice(tester, h, _sheetAt(past));
    expect(_glow(FrameSide.right), findsOneWidget);
    expect(_warning, findsOneWidget);
    expect(bannerText(tester), 'A folha saiu pela direita.');
  });

  testWidgets('the_warning_clears_when_the_sheet_returns', (tester) async {
    final h = await _open(tester);
    await _readTwice(tester, h, const LiveSheetCropped(sides: [FrameSide.top]));
    expect(_warning, findsOneWidget);
    await _readTwice(tester, h, _sheetAt(_vertices));
    expect(_warning, findsNothing);
    expect(_glow(FrameSide.top), findsNothing);
    expect(find.text('8–10 cm de solo'), findsOneWidget);
  });

  testWidgets('one_cropped_frame_does_not_warn', (tester) async {
    final h = await _open(tester);
    await _readTwice(tester, h, _sheetAt(_vertices));
    await _read(tester, h, const LiveSheetCropped(sides: [FrameSide.left]));
    expect(_warning, findsNothing);
    expect(_overlay(tester).brackets.values, everyElement(GuideState.placed));
  });

  testWidgets('a_stop_clears_the_guides', (tester) async {
    final h = await _open(tester);
    await _readTwice(tester, h, _sheetAt(_vertices));
    h.readers.last.fail();
    await tester.pumpAndSettle();
    expect(_overlay(tester).brackets, allIdle);
    expect(_overlay(tester).target, GuideState.idle);
    expect(_warning, findsNothing);
  });
}
