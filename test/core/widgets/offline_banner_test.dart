// The offline card as PNG 18 draws it (SPEC 0214).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/offline_banner.dart';

void main() {
  testWidgets('offline_card_matches_the_mock', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: OfflineBanner(pendingCount: 1)),
      ),
    );
    final palette = AppPalette.light;

    final box = find.byKey(const ValueKey('offline-card'));
    expect(tester.getTopLeft(box).dx, 16);
    expect(tester.getTopRight(box).dx, 390 - 16);
    final art = find.byKey(const ValueKey('offline-art'));
    expect(tester.getSize(art), const Size(64, 50));
    final title = tester.widget<Text>(find.text('Sem conexão')).style!;
    expect(title.fontSize, 15);
    expect(title.fontWeight, FontWeight.w400);
    expect(title.color, palette.onSurface);
    final line = tester
        .widget<Text>(find.textContaining('aguarda envio'))
        .style!;
    expect(line.fontSize, 13);
    expect(line.color, palette.onSurfaceVariant);
  });

  // SPEC 0216: Modo Sol draws the whole illustration in ink, the slash too.
  testWidgets('offline_slash_is_error_in_light_and_ink_in_sun', (tester) async {
    for (final (theme, palette) in [
      (AppTheme.light, AppPalette.light),
      (AppTheme.sun, AppPalette.sun),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(body: OfflineBanner(pendingCount: 1)),
        ),
      );
      final art = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('offline-art')),
      );
      final slash = (art.painter! as dynamic).slash as Color;
      expect(slash, palette.isSun ? palette.onSurface : palette.error);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
