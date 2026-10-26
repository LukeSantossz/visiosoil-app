import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_camera.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import '../../../support/guided_camera_harness.dart';

void main() {
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'sun': AppTheme.sun,
  }.entries) {
    testWidgets(
      '${entry.key}_controls_have_labels_targets_and_close_returns_cancelled',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await openGuidedCamera(tester, theme: entry.value);
        for (final label in ['Trocar câmera', 'Como fotografar', 'Fechar']) {
          final button = find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label,
          );
          expect(button, findsOneWidget);
          expect(
            tester.getSemantics(button),
            matchesSemantics(
              tooltip: label,
              isButton: true,
              hasTapAction: true,
              isEnabled: true,
              hasEnabledState: true,
              isFocusable: true,
              hasFocusAction: true,
            ),
          );
          final size = tester.getSize(button);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        expect(find.byIcon(LucideIcons.x), findsOneWidget);
        expect(find.byTooltip('Galeria'), findsNothing);
        expect(find.byTooltip('Flash'), findsNothing);
        await tester.tap(find.byTooltip('Fechar'));
        await tester.pumpAndSettle();
        expect(h.popped.single, isA<GuidedCaptureCancelled>());
        semantics.dispose();
      },
    );
  }

  testWidgets('single_camera_disables_flip', (tester) async {
    final h = GuidedCameraHarness();
    h.cameras.canSwitchCamera = false;
    await openGuidedCamera(tester, harness: h);
    final button = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Trocar câmera',
      ),
    );
    expect(button.onPressed, isNull);
    await backOut(tester);
  });

  testWidgets('info_opens_guide_and_reopens_camera_on_return', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final h = await openGuidedCamera(tester);
    await tester.tap(find.byTooltip('Como fotografar'));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureGuideScreen), findsOneWidget);
    expect(h.cameras.cameras.single.disposed, isTrue);
    await backOut(tester);
    expect(h.cameras.cameras, hasLength(2));
    expect(h.cameras.cameras.last.streaming, isTrue);
    expect(h.popped, isEmpty);
    await backOut(tester);
  });

  testWidgets('flip_restarts_live_reading', (tester) async {
    final h = await openGuidedCamera(tester);
    await tester.tap(find.byTooltip('Trocar câmera'));
    await tester.pumpAndSettle();
    expect(h.cameras.log, contains('switchCamera:0'));
    expect(h.cameras.cameras.single.streaming, isTrue);
    await backOut(tester);
  });
}
