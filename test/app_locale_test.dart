// The strings Flutter's own widgets supply read in pt-BR, whatever language
// the device is set to (SPEC 0119).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';

/// Pumps the app on a single page and returns that page's context.
Future<BuildContext> _pumpApp(WidgetTester tester) async {
  late BuildContext page;
  await tester.pumpWidget(ProviderScope(
    overrides: [initialThemeModeProvider.overrideWithValue(ThemeMode.light)],
    child: VisioSoilApp(
      routerConfig: GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: Builder(builder: (context) {
            page = context;
            return const SizedBox();
          })),
        ),
      ]),
    ),
  ));
  return page;
}

void main() {
  testWidgets('material_strings_are_portuguese', (tester) async {
    final strings = MaterialLocalizations.of(await _pumpApp(tester));

    expect(strings.backButtonTooltip, 'Voltar');
    expect(strings.pasteButtonLabel, 'Colar');
    expect(strings.modalBarrierDismissLabel, 'Dispensar');
  });

  testWidgets('cupertino_strings_are_portuguese', (tester) async {
    final strings = CupertinoLocalizations.of(await _pumpApp(tester));

    expect(strings.pasteButtonLabel, 'Colar');
  });

  testWidgets('locale_ignores_the_device', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final page = await _pumpApp(tester);

    expect(Localizations.localeOf(page), const Locale('pt', 'BR'));
  });
}
