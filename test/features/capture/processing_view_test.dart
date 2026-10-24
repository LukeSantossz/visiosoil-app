import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/widgets/processing_view.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import '../../support/haptics_recorder.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

void main() {
  tearDown(() => AppMotion.reduceMotion = false);
  for (final entry in {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'sun': AppTheme.sun,
  }.entries) {
    testWidgets('${entry.key} processing states and semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      final haptics = recordHaptics(tester);
      var settled = 0;
      Widget host(String? textureClass) => MaterialApp(
        theme: entry.value,
        home: Scaffold(
          body: ProcessingView(
            highlightClass: textureClass,
            onSettled: () => settled++,
          ),
        ),
      );
      await tester.pumpWidget(host(null));
      expect(find.text('Analisando a amostra'), findsOneWidget);
      expect(
        find.textContaining('Comparando com o modelo no aparelho'),
        findsOneWidget,
      );
      expect(find.textContaining('Diagrama ilustrativo'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
        find.bySemanticsLabel('Diagrama do triângulo textural'),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Argilosa'), findsNothing);
      await tester.pumpWidget(host('Argilosa'));
      await tester.pump(const Duration(milliseconds: 1800));
      if (entry.key == 'sun') {
        expect(settled, 1);
        expect(tester.hasRunningAnimations, isFalse);
      } else {
        expect(settled, 0);
        expect(haptics, isEmpty);
        expect(find.text('Argilosa'), findsNothing);
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      if (entry.key != 'sun') expect(settled, 0);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('Argilosa'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Diagrama do triângulo textural, classe Argilosa destacada',
        ),
        findsOneWidget,
      );
      expect(settled, 1);
      expect(haptics, ['HapticFeedbackType.lightImpact']);
      await tester.pump(const Duration(seconds: 3));
      expect(settled, 1);
      semantics.dispose();
    });
    testWidgets(
      '${entry.key} small screen with large text has no overflow and sufficient contrast',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          MaterialApp(
            theme: entry.value,
            home: MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: const Scaffold(
                body: ProcessingView(highlightClass: 'Argilosa'),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantics.dispose();
      },
    );
  }
  testWidgets('enabling the application motion preference stops particles', (
    tester,
  ) async {
    Widget host() =>
        MaterialApp(home: ProcessingView(highlightClass: 'Argilosa'));
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 800));
    AppMotion.reduceMotion = true;
    await tester.pumpWidget(host());
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('Argilosa'), findsOneWidget);
  });

  testWidgets('disposing falling particles emits no late settlement', (
    tester,
  ) async {
    var settled = 0;
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: TextureTriangle(
          highlightClass: 'Argilosa',
          mode: TextureTriangleMode.processing,
          onSettled: () => settled++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(settled, 0);
    expect(haptics, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reducing motion after settlement does not repeat its haptic', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    Widget host() =>
        MaterialApp(home: ProcessingView(highlightClass: 'Argilosa'));
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 2200));
    expect(haptics, ['HapticFeedbackType.lightImpact']);
    AppMotion.reduceMotion = true;
    await tester.pumpWidget(host());
    await tester.pump();
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('static diagram never settles or schedules animation', (
    tester,
  ) async {
    var settled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TextureTriangle(
          highlightClass: 'Argilosa',
          onSettled: () => settled++,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(settled, 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('theme updates do not repeat completed settlement', (
    tester,
  ) async {
    var settled = 0;
    Widget host(ThemeData theme) => MaterialApp(
      theme: theme,
      home: TextureTriangle(
        highlightClass: 'Argilosa',
        mode: TextureTriangleMode.processing,
        onSettled: () => settled++,
      ),
    );
    await tester.pumpWidget(host(AppTheme.light));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(settled, 1);
    await tester.pumpWidget(host(AppTheme.dark));
    await tester.pumpAndSettle();
    expect(settled, 1);
  });

  for (final system in [true, false]) {
    testWidgets(
      'reduced motion via ${system ? 'system' : 'preference'} settles without animation',
      (tester) async {
        AppMotion.reduceMotion = !system;
        var settled = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: system),
              child: Scaffold(
                body: TextureTriangle(
                  highlightClass: 'Argilosa',
                  mode: TextureTriangleMode.processing,
                  onSettled: () => settled++,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(settled, 1);
        expect(tester.hasRunningAnimations, isFalse);
      },
    );
  }
}
