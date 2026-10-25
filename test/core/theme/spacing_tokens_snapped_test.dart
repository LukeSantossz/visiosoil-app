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
  group('home widgets reference the token scale (no off-scale spacing/radius)',
      () {
    test('home_greeting references tokens and no off-scale spacing', () {
      final src = _packed('lib/core/features/home/widgets/home_greeting.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('EdgeInsets.all(10)')));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.lg,AppSpacing.lg,0)'),
      );
    });

    test('hero_capture_card uses token radius/spacing and the brand glow', () {
      final src =
          _packed('lib/core/features/home/widgets/hero_capture_card.dart');
      expect(src, contains('palette.shadowBrand'));
      expect(src, contains('EdgeInsets.all(AppSpacing.lg)'));
      expect(src, contains('AppRadius.borderRadiusXl'));
      expect(src, contains('AppRadius.borderRadiusPill'));
      expect(src, isNot(contains('circular(20)')));
      expect(src, isNot(contains('circular(32)')));
      expect(src, isNot(contains('fromLTRB(20,')));
    });

    test('stats_grid snaps its outer padding', () {
      final src = _packed('lib/core/features/home/widgets/stats_grid.dart');
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(
        src,
        contains('fromLTRB(AppSpacing.lg,AppSpacing.md,AppSpacing.lg,0)'),
      );
    });

    // The card padding moved into the shared StatCell (redesign v11 §4, PR 5):
    // stats_grid no longer duplicates it.
    test('stat_cell snaps its card padding', () {
      final src = _packed('lib/core/widgets/stat_cell.dart');
      expect(src, isNot(contains('EdgeInsets.all(10)')));
      expect(src, contains('EdgeInsets.all(AppSpacing.sm)'));
    });

    test('last_analysis_section references tokens and no off-scale spacing', () {
      final src =
          _packed('lib/core/features/home/widgets/last_analysis_section.dart');
      expect(src, contains('AppSpacing.'));
      expect(src, contains('AppRadius.'));
      expect(src, isNot(contains('fromLTRB(20,')));
      expect(src, isNot(contains('circular(20)')));
      expect(src, isNot(contains('SizedBox(height:10)')));
      expect(src, isNot(contains('horizontal:7')));
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

    test('confidence_badge snaps its badge padding to sm/xs', () {
      // Lives in the shared ConfidenceBadge (redesign v11 §3.14/§4) since
      // classification_header.dart and last_analysis_section.dart no longer
      // carry their own ad-hoc badge. The horizontal padding picks between
      // sm (full) and xs (compact, denser per the trello acceptance
      // criterion), so the token reference sits in that ternary rather than
      // directly on `horizontal:`.
      final src = _packed('lib/core/widgets/confidence_badge.dart');
      expect(src, isNot(contains('horizontal:10')));
      expect(src, contains('horizontal:horizontalPadding'));
      expect(
        src,
        contains('horizontalPadding=compact?AppSpacing.xs:AppSpacing.sm'),
      );
    });

    test('management_tips_section snaps its citation chip padding to sm/xs', () {
      final src =
          _packed('lib/core/features/details/management_tips_section.dart');
      expect(src, isNot(contains('horizontal:10')));
      expect(src, contains('horizontal:AppSpacing.sm'));
    });

    // The viewer's bottom sheet went with SPEC 0125; no off-scale radius may
    // come back.
    test('image_preview has no off-scale radius', () {
      final src = _packed('lib/core/features/preview/image_preview_screen.dart');
      expect(src, isNot(contains('Radius.circular(20)')));
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
    // The boot "Peneira" redesign (v11 §3.1/§6.2, SPEC 0193) replaced the
    // tile-and-shadow splash SPEC 0089 pinned here; its own layout spacing
    // (around the "Pular" button, between the logo and the name) is what
    // stays on the token scale now.
    test('splash snaps its skip-button and name spacing to tokens', () {
      final src = _packed('lib/core/features/splash/splash_screen.dart');
      expect(src, isNot(contains('EdgeInsets.all(10)')));
      expect(src, contains('EdgeInsets.all(AppSpacing.sm)'));
      expect(src, contains('SizedBox(height:AppSpacing.lg)'));
      expect(src, contains('SizedBox(height:AppSpacing.sm)'));
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
