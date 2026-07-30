// Navigation + tab-switch wiring for the redesigned home (#0029): the settings
// avatar, the capture CTA, the record row, and the "Ver tudo" link that opens
// the History tab via mainTabIndexProvider.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

SoilRecord _record() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      address: 'Fazenda Boa Vista',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

GoRouter _router() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const MainScreen()),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('SETTINGS_STUB')),
        ),
        GoRoute(
          path: '/capture',
          builder: (_, _) => const Scaffold(body: Text('CAPTURE_STUB')),
        ),
        GoRoute(
          path: '/details',
          builder: (_, state) =>
              Scaffold(body: Text('DETAILS_STUB ${state.extra}')),
        ),
      ],
    );

// The History tab lives in the same IndexedStack and shows an animating
// loading spinner, so `pumpAndSettle` never settles; advance with fixed-
// duration pumps instead (enough to flush the stream microtask and complete a
// route transition).
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soilRecordsStreamProvider.overrideWith((ref) => Stream.value([_record()])),
        // MainScreen's IndexedStack eagerly builds the History tab, whose grid
        // watches filteredRecordsProvider — which reads the real Drift
        // repository, not soilRecordsStreamProvider. Stub it so the harness
        // never opens a platform database.
        filteredRecordsProvider.overrideWith((ref) => Stream.value([_record()])),
      ],
      child: MaterialApp.router(routerConfig: _router()),
    ),
  );
  await _settle(tester);
}

void main() {
  testWidgets('the settings avatar opens settings', (tester) async {
    await _pump(tester);

    await tester.tap(find.byIcon(Icons.person_outline));
    await _settle(tester);

    expect(find.text('SETTINGS_STUB'), findsOneWidget);
  });

  testWidgets('the capture CTA opens capture', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Nova análise'));
    await _settle(tester);

    expect(find.text('CAPTURE_STUB'), findsOneWidget);
  });

  testWidgets('the record row opens details', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Argilosa'));
    await _settle(tester);

    expect(find.textContaining('DETAILS_STUB'), findsOneWidget);
  });

  testWidgets('"Ver tudo" switches to the History tab', (tester) async {
    await _pump(tester);

    NavigationBar bar = tester.widget(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);

    await tester.tap(find.text('Ver tudo'));
    await _settle(tester);

    bar = tester.widget(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
  });
}
