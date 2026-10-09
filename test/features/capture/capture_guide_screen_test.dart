// The capture guide teaches the onboarding's protocol on its own route, and
// only its primary action returns a go-ahead (SPEC 0142).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';

import '../../support/fake_capture_guide_store.dart';
import '../../support/guidelines.dart';
import '../../support/large_text.dart';

// The onboarding's steps, as SPEC 0104 approved them and its tests pin them.
const _titles = ['Folha A4', 'Amostra', 'Foto'];
const _sentences = [
  'Use uma folha A4 branca, sem nada escrito, sobre uma superfície mais '
      'escura que o papel. Não coloque mais nada sobre ela.',
  'Espalhe o solo em um círculo de 8 a 10 cm no meio da folha.',
  'Fotografe de cima, com a folha inteira no quadro e uma margem em volta, '
      'em luz difusa e sem flash.',
];

/// What the guide's route returned to the host, once it has returned.
class _Returned {
  bool returned = false;
  bool? value;
}

/// The app's own `/capture-guide` route, so these tests also hold the extra
/// that names the primary action.
final _guideRoute = GoRoute(
  path: '/capture-guide',
  builder: appRouter.configuration.routes
      .whereType<GoRoute>()
      .singleWhere((route) => route.path == '/capture-guide')
      .builder,
);

Widget _app(
  FakeCaptureGuideStore store, {
  required bool beforeCamera,
  _Returned? returned,
  ThemeData? theme,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final value = await context.push<bool>(
                  '/capture-guide',
                  extra: beforeCamera,
                );
                returned
                  ?..returned = true
                  ..value = value;
              },
              child: const Text('HOST'),
            ),
          ),
        ),
      ),
      _guideRoute,
    ],
  );
  return ProviderScope(
    overrides: [captureGuideStoreProvider.overrideWithValue(store)],
    child: MaterialApp.router(theme: theme, routerConfig: router),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('HOST'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('guide_teaches_the_onboarding_protocol', (tester) async {
    await tester.pumpWidget(_app(FakeCaptureGuideStore(), beforeCamera: true));
    await _open(tester);

    expect(find.text('Como capturar'), findsOneWidget);
    var previousTop = double.negativeInfinity;
    for (var i = 0; i < _titles.length; i++) {
      final title = find.text('${i + 1}. ${_titles[i]}');
      await tester.scrollUntilVisible(find.text(_sentences[i]), 100);
      expect(title, findsOneWidget);
      expect(find.text(_sentences[i]), findsOneWidget);
      final top = tester.getTopLeft(title).dy;
      expect(top, greaterThan(previousTop), reason: 'step ${i + 1} order');
      previousTop = top;
    }
  });

  testWidgets('primary_before_the_camera_marks_seen_and_returns_true',
      (tester) async {
    final store = FakeCaptureGuideStore();
    final returned = _Returned();
    await tester.pumpWidget(
        _app(store, beforeCamera: true, returned: returned));
    await _open(tester);

    expect(find.text('Entendi'), findsNothing);
    await tester.tap(find.text('Abrir câmera'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(store.seen, isTrue);
    expect(returned.returned, isTrue);
    expect(returned.value, isTrue);
    expect(find.text('HOST'), findsOneWidget);
  });

  testWidgets('on_demand_primary_reads_entendi_and_returns', (tester) async {
    final store = FakeCaptureGuideStore();
    final returned = _Returned();
    await tester.pumpWidget(
        _app(store, beforeCamera: false, returned: returned));
    await _open(tester);

    expect(find.text('Abrir câmera'), findsNothing);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(returned.returned, isTrue);
    expect(find.text('HOST'), findsOneWidget);
  });

  testWidgets('back_returns_nothing_and_leaves_the_guide_unseen',
      (tester) async {
    final store = FakeCaptureGuideStore();
    final returned = _Returned();
    await tester.pumpWidget(
        _app(store, beforeCamera: true, returned: returned));
    await _open(tester);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(store.markCalls, 0);
    expect(store.seen, isFalse);
    expect(returned.returned, isTrue);
    expect(returned.value, isNull);
  });

  // Back pressed while the flag is being written must not let the guide's
  // late pop close the screen beneath it, nor mark a guide the user left.
  testWidgets('back_during_the_write_never_pops_the_caller', (tester) async {
    final gate = Completer<void>();
    final store = FakeCaptureGuideStore(writeGate: gate.future);
    bool? returned;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: ElevatedButton(
              onPressed: () => context.push('/caller'),
              child: const Text('ROOT'),
            ),
          ),
        ),
        GoRoute(
          path: '/caller',
          builder: (context, _) => Scaffold(
            appBar: AppBar(),
            body: ElevatedButton(
              onPressed: () async {
                returned =
                    await context.push<bool>('/capture-guide', extra: true);
              },
              child: const Text('CALLER'),
            ),
          ),
        ),
        _guideRoute,
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [captureGuideStoreProvider.overrideWithValue(store)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('ROOT'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CALLER'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abrir câmera'));
    await tester.pump();
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 50));
    gate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CaptureGuideScreen), findsNothing);
    expect(find.text('CALLER'), findsOneWidget);
    expect(returned, isTrue);
    expect(store.seen, isTrue);
  });

  testWidgets('a_failed_write_still_returns_true', (tester) async {
    final store = FakeCaptureGuideStore(writeError: Exception('disk full'));
    final returned = _Returned();
    await tester.pumpWidget(
        _app(store, beforeCamera: true, returned: returned));
    await _open(tester);

    await tester.tap(find.text('Abrir câmera'));
    await tester.pumpAndSettle();

    expect(store.markCalls, 1);
    expect(returned.value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('guide_scrolls_at_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);
    await tester.pumpWidget(_app(FakeCaptureGuideStore(), beforeCamera: true));
    await _open(tester);
    expect(tester.takeException(), isNull);

    // The action is pinned below the steps, so it is on screen unscrolled.
    final screen = Offset.zero &
        tester.view.physicalSize / tester.view.devicePixelRatio;
    final action = tester.getRect(find.text('Abrir câmera'));
    expect(screen.contains(action.topLeft), isTrue);
    expect(screen.contains(action.bottomRight), isTrue);

    // The last sentence can be scrolled whole into view, above the action.
    await tester.scrollUntilVisible(find.text(_sentences.last), 100);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.text(_sentences.last));
    expect(screen.contains(last.topLeft), isTrue);
    expect(last.bottom, lessThanOrEqualTo(action.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('steps_are_single_semantic_nodes', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(FakeCaptureGuideStore(), beforeCamera: true));
    await _open(tester);

    expect(find.bySemanticsLabel('3 passos'), findsOneWidget);
    for (var i = 0; i < _titles.length; i++) {
      final step = find.bySemanticsLabel(
        '${i + 1}. ${_titles[i]}\n${_sentences[i]}',
      );
      await tester.scrollUntilVisible(find.text(_sentences[i]), 100);
      expect(step, findsOneWidget, reason: 'step ${i + 1}');
    }
    // The steps' icons; the app bar's back button keeps its own label.
    final stepIcons = tester.widgetList<Icon>(find.descendant(
      of: find.descendant(
        of: find.byType(CaptureGuideScreen),
        matching: find.byType(SingleChildScrollView),
      ),
      matching: find.byType(Icon),
    ));
    expect(stepIcons, hasLength(3));
    for (final icon in stepIcons) {
      expect(icon.semanticLabel, isNull);
    }
    semantics.dispose();
  });

  for (final (name, theme) in appThemes) {
    testWidgets('guide_meets_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(
        FakeCaptureGuideStore(),
        beforeCamera: true,
        theme: theme,
      ));
      await _open(tester);

      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
