import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
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

  // The design system's press feedback: a button shrinks to 0.98 while it is
  // pressed (SPEC 0134).
  AnimatedScale pressScale(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.descendant(
        of: find.byType(VisioButton),
        matching: find.byType(AnimatedScale),
      ));

  testWidgets('button_press_scales', (tester) async {
    await tester.pumpWidget(_host(VisioButton(label: 'Salvar', onPressed: () {})));
    expect(pressScale(tester).scale, 1);

    final gesture = await tester.startGesture(tester.getCenter(find.text('Salvar')));
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 0.98);
    expect(pressScale(tester).duration, AppMotion.instant);

    await gesture.up();
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 1);
  });

  testWidgets('disabled_button_does_not_scale', (tester) async {
    await tester.pumpWidget(_host(
      const VisioButton(label: 'Salvar', onPressed: null),
    ));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Salvar')));
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 1);
    await gesture.up();
  });

  // A button disabled while pressed clears its pressed state as it builds;
  // the scale follows after the frame instead of failing it.
  testWidgets('a_button_disabled_mid_press_settles', (tester) async {
    await tester.pumpWidget(_host(VisioButton(label: 'Salvar', onPressed: () {})));
    final gesture = await tester.startGesture(tester.getCenter(find.text('Salvar')));
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 0.98);

    await tester.pumpWidget(_host(
      const VisioButton(label: 'Salvar', onPressed: null),
    ));
    await tester.pump(AppMotion.instant);
    expect(tester.takeException(), isNull);
    expect(pressScale(tester).scale, 1);
    await gesture.up();
  });

  testWidgets('press_scale_respects_reduced_motion', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(_host(VisioButton(label: 'Salvar', onPressed: () {})));

    final gesture = await tester.startGesture(tester.getCenter(find.text('Salvar')));
    await tester.pump();
    expect(pressScale(tester).scale, 0.98);
    expect(pressScale(tester).duration, Duration.zero);
    await gesture.up();
  });
}
