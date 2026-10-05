// One icon-only button whose label is required, refused when empty, and
// proven to reach the screen reader (SPEC 0131).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/widgets/visio_icon_button.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('label_reaches_semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(VisioIconButton(
      label: 'Fechar',
      icon: Icons.close,
      onPressed: () {},
    )));

    // The IconButton owns the node: since SPEC 0134 the component's root is
    // the press scale's transform, which has none of its own.
    expect(
      tester.getSemantics(find.byType(IconButton)),
      // Flutter exposes a tooltip as the node's tooltip, which TalkBack and
      // VoiceOver announce as the button's name.
      matchesSemantics(
        tooltip: 'Fechar',
        isButton: true,
        hasTapAction: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  test('empty_label_is_refused', () {
    expect(
      () => VisioIconButton(label: '  ', icon: Icons.close, onPressed: () {}),
      throwsAssertionError,
    );
  });

  testWidgets('over_photo_draws_the_scrim', (tester) async {
    await tester.pumpWidget(_host(VisioIconButton(
      label: 'Voltar',
      icon: Icons.arrow_back,
      overPhoto: true,
      onPressed: () {},
    )));

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.style?.backgroundColor?.resolve({}), Colors.black45);
    expect(button.color, Colors.white);
  });

  // An icon button shrinks to 0.92 while it is pressed (SPEC 0134).
  AnimatedScale pressScale(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.descendant(
        of: find.byType(VisioIconButton),
        matching: find.byType(AnimatedScale),
      ));

  testWidgets('icon_button_press_scales', (tester) async {
    await tester.pumpWidget(_host(VisioIconButton(
      label: 'Fechar',
      icon: Icons.close,
      onPressed: () {},
    )));
    expect(pressScale(tester).scale, 1);

    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.close)));
    // The tooltip's long press competes for the touch, so the press, and its
    // ink, begin after kPressTimeout.
    await tester.pump(kPressTimeout);
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 0.92);

    await gesture.up();
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 1);
  });

  testWidgets('disabled_icon_button_does_not_scale', (tester) async {
    await tester.pumpWidget(_host(VisioIconButton(
      label: 'Fechar',
      icon: Icons.close,
      onPressed: null,
    )));

    final gesture =
        await tester.startGesture(tester.getCenter(find.byIcon(Icons.close)));
    await tester.pump(kPressTimeout);
    await tester.pump(AppMotion.instant);
    expect(pressScale(tester).scale, 1);
    await gesture.up();
  });
}
