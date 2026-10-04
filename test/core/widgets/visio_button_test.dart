import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';

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
  });

  testWidgets('a busy button is disabled', (tester) async {
    await tester.pumpWidget(_host(
      VisioButton(label: 'Salvar', onPressed: () {}, isLoading: true),
    ));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  // The shared indicator keeps the button's spinner at its own size, so a
  // loading button does not stretch (SPEC 0123).
  testWidgets('spinners_keep_their_size: a loading button', (tester) async {
    await tester.pumpWidget(_host(Center(
      child: VisioButton(label: 'Salvar', onPressed: () {}, isLoading: true),
    )));

    expect(tester.getSize(find.byType(LoadingIndicator)), const Size(20, 20));
  });
}
