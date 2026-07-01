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

      final button = find.widgetWithText(FilledButton, 'Voltar ao início');
      expect(button, findsOneWidget);

      await tester.tap(button);
      expect(goHomeCalls, 1);
    },
  );
}
