// Guards the offscale_absent criterion of spec 0027: the home/details/preview/
// splash/capture/history layout files must not reassert the off-scale spacing
// (20/18/14/10/7/6) or radius (20/14/32) literals the re-audit snapped to the
// token scale, and must reference the specific target AppSpacing/AppRadius
// tokens. These are layout magnitudes, not element sizes (icon `size:`,
// container width/height, font sizes, shadow blur are intentionally out of
// scope), so the guard pins the exact padding/radius expressions that were
// snapped rather than bare numbers.
//
// A source guard mirrors the accepted code-inspection precedent (specs
// 0007/0009/0024/0026): several of these widgets (splash timers, preview/details
// providers) are impractical to instantiate for a pixel assertion, and the
// criterion is itself source-level. Substring checks run against a
// whitespace-collapsed copy of the source so a forbidden literal cannot hide by
// being reflowed across lines by the formatter (e.g. `horizontal: 10,` and
// `vertical: 4,` on separate lines).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The source with all whitespace and trailing commas removed, so multi-line
/// (with a dangling comma before the close paren) and single-line forms of the
/// same expression collapse to one comparable string.
String _packed(String path) =>
    _read(path).replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',(?=\))'), '');

void main() {
  group('home widgets snap off-scale spacing/radius to tokens', () {
    test('hero_section has no off-scale padding/gap literals', () {
      final src = _packed('lib/core/features/home/widgets/hero_section.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('SizedBox(height:14)')));
      expect(src, isNot(contains('SizedBox(width:10)')));
      expect(src, contains('EdgeInsets.all(AppSpacing.lg)'));
      expect(src, contains('SizedBox(height:AppSpacing.md)'));
    });

    test('primary_action snaps card radius and paddings', () {
      final src = _packed('lib/core/features/home/widgets/primary_action.dart');
      expect(src, isNot(contains('circular(20)')));
      expect(src, isNot(contains('circular(14)')));
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('horizontal:18')));
      expect(src, isNot(contains('SizedBox(width:14)')));
      expect(src, contains('circular(AppRadius.lg)'));
      expect(src, contains('circular(AppRadius.md)'));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.lg,AppSpacing.lg,'
            'AppSpacing.sm)'),
      );
    });

    test('stats_grid snaps its outer and card paddings', () {
      final src = _packed('lib/core/features/home/widgets/stats_grid.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('EdgeInsets.all(10)')));
      expect(src, contains('EdgeInsets.all(AppSpacing.sm)'));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.md,AppSpacing.lg,0)'),
      );
    });

    test('last_analysis_section snaps its paddings and gaps', () {
      final src =
          _packed('lib/core/features/home/widgets/last_analysis_section.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('SizedBox(height:10)')));
      expect(src, isNot(contains('SizedBox(width:6)')));
      expect(src, isNot(contains('horizontal:7')));
      expect(src, isNot(contains('symmetric(vertical:10)')));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.md,AppSpacing.lg,0)'),
      );
      expect(src, contains('symmetric(vertical:AppSpacing.sm)'));
    });
  });

  group('details/preview/capture snap radius and chip padding', () {
    test('details_screen snaps its content padding', () {
      final src = _packed('lib/core/features/details/details_screen.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.lg,AppSpacing.lg,'
            'AppSpacing.xxl)'),
      );
    });

    test('classification_header snaps its badge padding to sm/xs', () {
      final src = _packed(
          'lib/core/features/details/widgets/classification_header.dart');
      expect(src, isNot(contains('horizontal:10')));
      expect(src, contains('horizontal:AppSpacing.sm'));
    });

    test('management_tips_section snaps its citation chip padding to sm/xs', () {
      final src =
          _packed('lib/core/features/details/management_tips_section.dart');
      expect(src, isNot(contains('horizontal:10')));
      expect(src, contains('horizontal:AppSpacing.sm'));
    });

    test('image_preview snaps its bottom-sheet radius to xl', () {
      final src = _packed('lib/core/features/preview/image_preview_screen.dart');
      expect(src, isNot(contains('Radius.circular(20)')));
      expect(src, contains('Radius.circular(AppRadius.xl)'));
    });

    test('capture_image_preview snaps its chip and container radius to lg', () {
      final src =
          _packed('lib/core/features/capture/widgets/capture_image_preview.dart');
      expect(src, isNot(contains('circular(20)')));
      expect(src, isNot(contains('circular(16)')));
      expect(src, contains('circular(AppRadius.lg)'));
    });
  });

  group('splash and history reference the token scale', () {
    test('splash snaps its logo radius to xl and tokenizes its brand shadow',
        () {
      final src = _packed('lib/core/features/splash/splash_screen.dart');
      expect(src, isNot(contains('circular(32)')));
      expect(src, isNot(contains('primary.withValues(alpha:0.3)')));
      expect(src, contains('circular(AppRadius.xl)'));
      expect(src, contains('AppColors.shadowBrand'));
    });

    test('history_grid tokenizes its thumbnail radius to md', () {
      final src = _packed('lib/core/features/history/widgets/history_grid.dart');
      expect(src, isNot(contains('circular(12)')));
      expect(src, contains('circular(AppRadius.md)'));
    });

    test('history_filter_bar tokenizes its search-field radius to md', () {
      final src =
          _packed('lib/core/features/history/widgets/history_filter_bar.dart');
      expect(src, isNot(contains('circular(12)')));
      expect(src, contains('circular(AppRadius.md)'));
    });
  });
}
