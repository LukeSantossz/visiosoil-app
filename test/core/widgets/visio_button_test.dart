import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';

Widget _host(Widget child) =>
    MaterialApp(theme: AppTheme.light, home: Scaffold(body: child));

void main() {
  testWidgets('primary variant renders a filled ElevatedButton',
      (tester) async {
    await tester.pumpWidget(_host(
      VisioButton(label: 'Salvar', onPressed: () {}),
    ));
    expect(find.byType(ElevatedButton), findsOneWidget);
  });

  testWidgets('secondary variant renders an OutlinedButton', (tester) async {
    await tester.pumpWidget(_host(
      VisioButton(
        label: 'Cancelar',
        onPressed: () {},
        variant: VisioButtonVariant.secondary,
      ),
    ));
    expect(find.byType(OutlinedButton), findsOneWidget);
  });

  testWidgets('destructive variant renders a TextButton with error foreground',
      (tester) async {
    await tester.pumpWidget(_host(
      VisioButton(
        label: 'Excluir',
        onPressed: () {},
        icon: Icons.delete_outline,
        variant: VisioButtonVariant.destructive,
      ),
    ));

    expect(find.byType(TextButton), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    final button = tester.widget<TextButton>(find.byType(TextButton));
    final foreground = button.style?.foregroundColor?.resolve(<WidgetState>{});
    expect(foreground, AppTheme.light.colorScheme.error);

    // Matches the design-system 24px horizontal / 48px-height button contract,
    // like the sibling elevated/outlined actions (the text-button theme sets no
    // geometry of its own).
    expect(
      button.style?.padding?.resolve(<WidgetState>{}),
      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    );
    expect(tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(48));
  });

  testWidgets('a busy button is disabled', (tester) async {
    await tester.pumpWidget(_host(
      VisioButton(label: 'Salvar', onPressed: () {}, isLoading: true),
    ));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });
}
