import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';

void main() {
  testWidgets('long email stays on one line at 411dp in Sun mode', (
    tester,
  ) async {
    const email = 'agronomist.with.a.very.long.email.address@example.com';
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.sun,
        home: Scaffold(
          body: AccountCard(
            name: 'Agro',
            email: email,
            child: TextButton(onPressed: () {}, child: const Text('Sair')),
          ),
        ),
      ),
    );
    final emailFinder = find.text(email);
    final text = tester.widget<Text>(emailFinder);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.softWrap, isFalse);
    expect(
      find.ancestor(of: emailFinder, matching: find.byType(Expanded)),
      findsOneWidget,
    );
    expect(find.text('Sair').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
