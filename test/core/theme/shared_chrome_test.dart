// The chrome every screen shares follows the redesign mocks (SPEC 0201):
// Inter throughout, a start-aligned app bar title and Lucide icons.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

void main() {
  test('every_style_is_inter', () {
    final theme = AppTypography.textThemeFor(AppPalette.light);
    for (final style in [
      theme.displaySmall,
      theme.headlineLarge,
      theme.headlineMedium,
      theme.headlineSmall,
      theme.titleLarge,
      theme.titleMedium,
      theme.titleSmall,
      theme.bodyLarge,
      theme.bodyMedium,
      theme.bodySmall,
      theme.labelLarge,
      theme.labelMedium,
      theme.labelSmall,
    ]) {
      expect(style?.fontFamily, startsWith('Inter'));
    }
  });

  // The bundled static Inter has no single-storey "a" (cv11); the mocks
  // set it, so every role reads InterVariable at an optical size equal to
  // its font size, as a browser sets it (SPEC 0201).
  test('every_style_is_the_variable_inter_at_its_optical_size', () {
    final theme = AppTypography.textThemeFor(AppPalette.light);
    for (final style in [
      theme.headlineMedium,
      theme.titleLarge,
      theme.bodyMedium,
      theme.labelSmall,
    ]) {
      expect(style?.fontFamily, 'InterVariable');
      expect(
        style?.fontVariations,
        contains(FontVariation('opsz', style!.fontSize!.clamp(14, 32))),
      );
    }
  });

  test('app_bar_title_matches_the_mock', () {
    expect(AppTypography.titleLarge.fontSize, 20);
    expect(AppTypography.titleLarge.fontWeight, FontWeight.w600);
  });

  group('app_bar_title_starts_left', () {
    testWidgets('without a leading widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(appBar: VisioAppBar(title: 'Histórico')),
        ),
      );
      expect(tester.getTopLeft(find.text('Histórico')).dx, 16);
      expect(tester.getSize(find.byType(AppBar)).height, 64);
    });

    testWidgets('after the back button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const Scaffold(appBar: VisioAppBar(title: 'Resultado')),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.text('Resultado')).dx, 60);
      expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
    });
  });

  for (final (name, width) in [('bar', 400.0), ('rail', 800.0)]) {
    testWidgets('main_navigation_draws_lucide in the $name', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            soilRecordsStreamProvider.overrideWith(
              (ref) => Stream.value(const <SoilRecord>[]),
            ),
            filteredRecordsProvider.overrideWith(
              (ref) => Stream.value(const <SoilRecord>[]),
            ),
            connectivityStatusProvider.overrideWith(
              (ref) => Stream.value(ConnectivityStatus.online),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const MainScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      for (final icon in [
        LucideIcons.house,
        LucideIcons.history,
        LucideIcons.lightbulb,
        LucideIcons.user,
      ]) {
        expect(find.byIcon(icon), findsWidgets, reason: '$icon');
      }
    });
  }
}
