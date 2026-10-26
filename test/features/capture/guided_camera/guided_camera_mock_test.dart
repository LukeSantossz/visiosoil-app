// The guided camera against PNG 10, 11, 12 and 28 (SPEC 0211).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_alert.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guided_camera_screen.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/quality_chip.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import '../../../support/guided_camera_harness.dart';

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// A dark, flat frame, answered with a found sheet: light and focus fail.
Future<void> _readPoorly(WidgetTester tester, GuidedCameraHarness h) async {
  for (var i = 0; i < 2; i++) {
    h.cameras.cameras.single.emitFrame((
      format: tinyFrame.format,
      width: 32,
      height: 32,
      bytes: Uint8List.fromList(List.filled(1024, 10)),
      bytesPerRow: 32,
    ));
    await tester.pump();
    h.readers.last.reply(
      const LiveSheetFound(
        sheetLongSidePx: 900,
        discDiameterMm: 90,
        holdsMinPatches: true,
      ),
    );
    await tester.pump();
    await tester.pump();
  }
}

Color? _fill(WidgetTester tester, Finder finder) {
  final box = tester.widget<Container>(finder);
  return (box.decoration as BoxDecoration?)?.color;
}

void main() {
  testWidgets('camera_top_bar_matches_the_mock', (tester) async {
    _phone(tester);
    await openGuidedCamera(tester);
    // No band: the bar is drawn straight over the preview and its scrim.
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ColoredBox && widget.color == Colors.black54,
      ),
      findsNothing,
    );
    final close = find.byKey(const ValueKey('guided-camera-close'));
    expect(
      find.descendant(of: close, matching: find.byIcon(LucideIcons.x)),
      findsOneWidget,
    );
    expect(find.byTooltip('Fechar'), findsOneWidget);
    // As VisioAppBar lays out every other screen: the leading centred at
    // 28 dp, the title from 60 dp, the action centred 28 dp from the edge.
    expect(tester.getCenter(close), const Offset(28, 32));
    final title = find.text('Nova análise');
    expect(tester.getTopLeft(title).dx, 60);
    expect(tester.getCenter(find.byIcon(LucideIcons.info)).dx, 390 - 28);
    final style = tester.widget<Text>(title).style!;
    expect(style.fontSize, AppTypography.titleLarge.fontSize);
    expect(style.color, Colors.white);
  });

  testWidgets('guidance_pill_sits_above_the_outline', (tester) async {
    // Wide enough for the test font's square glyphs to keep one line.
    tester.view.physicalSize = const Size(1800, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await openGuidedCamera(tester);
    final pill = find.byKey(const ValueKey('guided-camera-banner'));
    expect(tester.getSize(pill).height, 28);
    final text = tester.widget<Text>(
      find.descendant(of: pill, matching: find.byType(Text)),
    );
    expect(text.style?.fontSize, 14);
    expect(text.style?.color, Colors.white);
    final overlay = find.byType(CaptureGuideOverlay);
    final layout = CaptureGuideLayout.compute(
      tester.getSize(overlay),
      topInset: GuidedCameraScreen.topInset,
      bottomInset: GuidedCameraScreen.bottomInset,
      preview: tester.widget<CaptureGuideOverlay>(overlay).preview,
    );
    final outlineTop = tester.getTopLeft(overlay).dy + layout.outline.top;
    expect(tester.getBottomLeft(pill).dy, closeTo(outlineTop - 12, 0.5));
  });

  testWidgets('quality_chips_match_the_mock', (tester) async {
    _phone(tester);
    final h = await openGuidedCamera(tester);
    await _readPoorly(tester, h);
    final chip = find.byType(QualityChip).first;
    expect(tester.getSize(chip).height, 51);
    final box = find
        .descendant(of: chip, matching: find.byType(Container))
        .first;
    expect(_fill(tester, box), const Color(0xFF1C1C1C));
    final label = tester.widget<Text>(
      find.descendant(of: chip, matching: find.text('Luz')),
    );
    expect(label.style?.fontSize, 13);
    expect(label.style?.fontWeight, FontWeight.w600);
    final value = tester.widget<Text>(
      find.descendant(of: chip, matching: find.text('Baixa')),
    );
    expect(value.style?.fontSize, 12);
    expect(value.style?.color, const Color(0xFFBDBDBD));
    expect(
      find.descendant(of: chip, matching: find.byIcon(LucideIcons.circleAlert)),
      findsOneWidget,
    );
  });

  testWidgets('held_shutter_matches_the_mock', (tester) async {
    _phone(tester);
    final h = await openGuidedCamera(tester);
    await _readPoorly(tester, h);
    final ring = find.byKey(const ValueKey('guided-camera-shutter-ring'));
    final disc = find.byKey(const ValueKey('guided-camera-shutter-disc'));
    expect(tester.getSize(ring), const Size(72, 72));
    expect(tester.getSize(disc), const Size(56, 56));
    final ringBox = tester.widget<Container>(ring).decoration! as BoxDecoration;
    expect(ringBox.border!.top.color, const Color(0xFF666666));
    expect(ringBox.border!.top.width, 4);
    expect(_fill(tester, disc), const Color(0xFF555555));
  });

  testWidgets('switch_sits_64_dp_from_the_right', (tester) async {
    _phone(tester);
    await openGuidedCamera(tester);
    final disc = find.byKey(const ValueKey('guided-camera-switch'));
    expect(tester.getSize(disc), const Size(48, 48));
    expect(tester.getCenter(disc).dx, 390 - 64);
    expect(
      tester.getCenter(disc).dy,
      tester
          .getCenter(find.byKey(const ValueKey('guided-camera-shutter-ring')))
          .dy,
    );
    expect(_fill(tester, disc), const Color(0xFF262626));
    expect(
      find.descendant(of: disc, matching: find.byIcon(LucideIcons.refreshCw)),
      findsOneWidget,
    );
  });

  testWidgets('capture_alert_matches_the_mock', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: CaptureAlert(
            causes: ['Pouca luz', 'fora de foco', 'longe demais'],
            corrections: [
              'Procure sombra clara',
              'aproxime até a amostra preencher a moldura',
              'segure firme',
            ],
          ),
        ),
      ),
    );
    final card = find.byKey(const ValueKey('capture-alert'));
    expect(_fill(tester, card), const Color(0xFFFFF4E2));
    final title = tester.widget<Text>(
      find.text('Ainda não dá para fotografar'),
    );
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(
      find.text(
        'Pouca luz, fora de foco, longe demais. Procure sombra clara, '
        'aproxime até a amostra preencher a moldura e segure firme.',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(LucideIcons.circleAlert), findsOneWidget);
  });

  testWidgets('refusal_card_floats_above_the_chips', (tester) async {
    _phone(tester);
    final h = await openGuidedCamera(tester);
    await _readPoorly(tester, h);
    await tester.tap(shutter);
    await tester.pump();
    final card = find.byKey(const ValueKey('capture-alert'));
    expect(card, findsOneWidget);
    final chips = tester.getTopLeft(find.byType(QualityChip).first);
    expect(tester.getBottomLeft(card).dy, closeTo(chips.dy - 7, 0.5));
    expect(tester.getTopLeft(card).dx, 16);
    expect(tester.getTopRight(card).dx, 390 - 16);
    // A refused chip keeps PNG 10's 51 dp.
    expect(tester.getSize(find.byType(QualityChip).first).height, 51);
    await tester.pump(CaptureAlert.visibleDuration);
  });
}
