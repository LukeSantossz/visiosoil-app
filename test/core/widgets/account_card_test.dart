import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark, AppTheme.sun]) {
    for (final linked in [false, true]) {
      testWidgets(
        'account header exposes identity and supports large text $linked ${theme.hashCode}',
        (tester) async {
          final semantics = tester.ensureSemantics();
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: MediaQuery(
                  data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                  child: AccountCard(
                    name: linked ? 'Test User' : null,
                    email: linked ? 'test@example.com' : null,
                    child: const Text('Account action'),
                  ),
                ),
              ),
            ),
          );
          expect(
            find.text(linked ? 'Test User' : 'Sem conta vinculada'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel(
              linked
                  ? 'Test User, test@example.com'
                  : 'Sem conta vinculada, Dados só neste aparelho',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
