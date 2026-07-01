// Tests for [RouteErrorView]: the localized full-screen fallback the router
// shows for unknown routes. The view takes an `onGoHome` callback so it can be
// verified without a live router.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/route_error_view.dart';

void main() {
  testWidgets(
    'route_error_view_shows_localized_message_and_calls_on_go_home_on_button_tap',
    (tester) async {
      var goHomeCalls = 0;

      await tester.pumpWidget(
        MaterialApp(home: RouteErrorView(onGoHome: () => goHomeCalls++)),
      );

      expect(find.text('Tela não encontrada'), findsOneWidget);
      expect(find.text('Voltar ao início'), findsOneWidget);

      // Tap the label rather than matching the button's exact runtime type:
      // FilledButton.icon yields a subtype that find.byType(FilledButton) does
      // not match on some Flutter versions (the CI toolchain vs. local).
      await tester.tap(find.text('Voltar ao início'));
      expect(goHomeCalls, 1);
    },
  );
}
