// One icon-only button whose label is required, refused when empty, and
// proven to reach the screen reader (SPEC 0131).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

    expect(
      tester.getSemantics(find.byType(VisioIconButton)),
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
}
