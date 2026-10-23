// Golden tests for the three palettes: light, dark, and sun.
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

void main() {
  group('palette goldens', () {
    testWidgets('light_palette_golden', (tester) async {
      await tester.pumpWidget(_PaletteSwatches(palette: AppPalette.light));
      await expectLater(
        find.byType(_PaletteSwatches),
        matchesGoldenFile('goldens/palette_light.png'),
      );
    });

    testWidgets('dark_palette_golden', (tester) async {
      await tester.pumpWidget(_PaletteSwatches(palette: AppPalette.dark));
      await expectLater(
        find.byType(_PaletteSwatches),
        matchesGoldenFile('goldens/palette_dark.png'),
      );
    });

    testWidgets('sun_palette_golden', (tester) async {
      await tester.pumpWidget(_PaletteSwatches(palette: AppPalette.sun));
      await expectLater(
        find.byType(_PaletteSwatches),
        matchesGoldenFile('goldens/palette_sun.png'),
      );
    });
  });
}

class _PaletteSwatches extends StatelessWidget {
  const _PaletteSwatches({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: palette.background,
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                _Swatch('primary', palette.primary),
                _Swatch('onPrimary', palette.onPrimary),
                _Swatch('primaryContainer', palette.primaryContainer),
                _Swatch('onPrimaryContainer', palette.onPrimaryContainer),
                _Swatch('primaryText', palette.primaryText),
                _Swatch('secondary', palette.secondary),
                _Swatch('onSecondary', palette.onSecondary),
                _Swatch('secondaryContainer', palette.secondaryContainer),
                _Swatch('onSecondaryContainer', palette.onSecondaryContainer),
                _Swatch('error', palette.error),
                _Swatch('onError', palette.onError),
                _Swatch('errorContainer', palette.errorContainer),
                _Swatch('onErrorContainer', palette.onErrorContainer),
                _Swatch('warning', palette.warning),
                _Swatch('warningContainer', palette.warningContainer),
                _Swatch('onWarningContainer', palette.onWarningContainer),
                _Swatch('background', palette.background),
                _Swatch('onBackground', palette.onBackground),
                _Swatch('surface', palette.surface),
                _Swatch('onSurface', palette.onSurface),
                _Swatch('surfaceContainer', palette.surfaceContainer),
                _Swatch('surfaceContainerHigh', palette.surfaceContainerHigh),
                _Swatch('surfaceVariant', palette.surfaceVariant),
                _Swatch('onSurfaceVariant', palette.onSurfaceVariant),
                _Swatch('textTertiary', palette.textTertiary),
                _Swatch('outline', palette.outline),
                _Swatch('outlineVariant', palette.outlineVariant),
                _Swatch('divider', palette.divider),
                _Swatch('selected', palette.selected),
                _Swatch('destructive', palette.destructive),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final luminance = color.computeLuminance();
    final textColor = luminance > 0.5 ? Colors.black : Colors.white;
    return Container(
      width: 80,
      height: 40,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
