// The settings rows and the compact Tema control against PNG 35 and 36
// (SPEC 0215).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';

Widget _group(ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: SettingsGroup(
        children: [
          SettingsRowFrame(
            key: const Key('tema'),
            icon: const Icon(LucideIcons.moon, size: 22),
            title: 'Tema',
            trailing: SegmentedControl<bool>(
              compact: true,
              value: false,
              onChanged: (_) {},
              options: const [
                SegmentedControlOption(value: false, label: 'Claro'),
                SegmentedControlOption(value: true, label: 'Escuro'),
              ],
            ),
          ),
          SettingsTile(
            key: const Key('unidades'),
            icon: LucideIcons.ruler,
            title: 'Unidades',
            subtitle: 'Distância em cm',
            onTap: () {},
          ),
        ],
      ),
    ),
  ),
);

void _wide(WidgetTester tester) {
  // Wide enough for the test font's square glyphs to keep one line.
  tester.view.physicalSize = const Size(1180, 1688);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

void _expectRuleInside(WidgetTester tester, double width) {
  final row = find.byKey(const Key('unidades'));
  final rule = find.byKey(const Key('settings-rule'));
  expect(tester.getSize(row).height, 56);
  expect(tester.getTopLeft(rule).dy, tester.getTopLeft(row).dy);
  expect(tester.getSize(rule).height, width);
}

void main() {
  testWidgets('light_settings_rows_match_png_35', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_group(AppTheme.light));
    expect(tester.getSize(find.byKey(const Key('tema'))).height, 56);
    // The 1 dp rule lies inside the next row's 56 dp, leaving it 55 dp.
    _expectRuleInside(tester, 1);
    final claro = tester.getSize(find.byKey(const Key('segment-0'))).width;
    final escuro = tester.getSize(find.byKey(const Key('segment-1'))).width;
    expect(claro, lessThan(escuro));
    final label = tester.widget<Text>(find.text('Claro'));
    expect(label.style?.fontSize, 12.5);
    expect(label.style?.fontWeight, FontWeight.w500);
    expect(tester.getSize(find.byKey(const Key('segment-0'))).height, 48);
  });

  testWidgets('sun_settings_rows_match_png_36', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_group(AppTheme.sun));
    // The 2 dp rule leaves 54 dp of row, and the target stays 56 dp.
    _expectRuleInside(tester, 2);
    final title = tester.widget<Text>(find.text('Unidades'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.height, 20 / 17);
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.ruler)).color,
      AppPalette.sun.onSurface,
    );
    expect(tester.getSize(find.byKey(const Key('tema'))).height, 60);
    expect(tester.getSize(find.byKey(const Key('segmented-pill'))).height, 44);
    final label = tester.widget<Text>(find.text('Claro'));
    expect(label.style?.fontSize, 14.5);
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(
      tester.getSize(find.byKey(const Key('segment-0'))).height,
      greaterThanOrEqualTo(56),
    );
  });

  // SPEC 0216: the icons are 20 dp at the start of a 22 dp slot.
  testWidgets('settings_row_icons_are_20_dp', (tester) async {
    _wide(tester);
    await tester.pumpWidget(_group(AppTheme.light));
    final icon = find.byIcon(LucideIcons.ruler);
    expect(tester.widget<Icon>(icon).size, 20);
    final row = tester.getTopLeft(find.byKey(const Key('unidades')));
    expect(tester.getTopLeft(icon).dx - row.dx, 16);
    expect(tester.getTopLeft(find.text('Unidades')).dx - row.dx, 16 + 22 + 12);
  });

  testWidgets('unavailable_row_is_greyed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: SettingsTile(
            icon: LucideIcons.cloudUpload,
            title: 'Backup na conta',
            subtitle: 'Requer conta vinculada',
            enabled: false,
          ),
        ),
      ),
    );
    final palette = AppPalette.light;
    expect(
      tester.widget<Text>(find.text('Backup na conta')).style?.color,
      palette.onSurface.withValues(alpha: 0.55),
    );
    expect(
      tester.widget<Text>(find.text('Requer conta vinculada')).style?.color,
      palette.onSurfaceVariant.withValues(alpha: 0.55),
    );
    expect(
      tester.widget<Icon>(find.byIcon(LucideIcons.cloudUpload)).color,
      palette.primaryText,
    );
    expect(find.byIcon(LucideIcons.chevronRight), findsNothing);
  });
}
