// The processing screen against PNG 13, 31 and 38 (SPEC 0211).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/widgets/processing_lattice.dart';
import 'package:visiosoil_app/core/features/capture/widgets/processing_view.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

Widget _host(ThemeData theme, {String? textureClass}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: ProcessingView(
      highlightClass: textureClass,
      phaseLabel: 'Classificando...',
    ),
  ),
);

void main() {
  testWidgets('processing_matches_the_mock', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(AppTheme.light, textureClass: 'Argilosa'));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    final title = tester.widget<Text>(find.text('Analisando a amostra'));
    expect(title.style?.fontSize, 20);
    expect(title.style?.fontWeight, FontWeight.w600);
    final chip = tester.widget<Text>(find.text('Argilosa'));
    expect(chip.style?.fontSize, 12);
    expect(chip.style?.fontWeight, FontWeight.w600);
    final sentence = tester.widget<Text>(
      find.textContaining('Comparando com o modelo'),
    );
    expect(sentence.style?.fontSize, 14);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Classificando...'), findsNothing);
    expect(find.bySemanticsLabel('Classificando...'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('lattice_draws_outside_sun_mode', (tester) async {
    for (final (theme, drawn) in [
      (AppTheme.light, true),
      (AppTheme.sun, false),
    ]) {
      await tester.pumpWidget(
        MaterialApp(theme: theme, home: const ProcessingLattice()),
      );
      // Let the theme finish animating from the previous one.
      await tester.pumpAndSettle();
      final paints = find.descendant(
        of: find.byType(ProcessingLattice),
        matching: find.byType(CustomPaint),
      );
      expect(paints, drawn ? findsOneWidget : findsNothing);
    }
  });
}
