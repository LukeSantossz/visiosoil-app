// SettingsSwitchTile (redesign v11 §4): a settings row with a trailing
// switch, tappable anywhere in the row.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/settings_switch_tile.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';

import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  for (final selected in [false, true]) {
    testWidgets('Sun toggle paints black and white when selected=$selected', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: Scaffold(
            body: SettingsSwitchTile(
              title: 'Sol',
              value: selected,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      final containers = tester
          .widgetList<AnimatedContainer>(
            find.descendant(
              of: find.byType(SettingsSwitchTile),
              matching: find.byType(AnimatedContainer),
            ),
          )
          .toList();
      final track = containers.first.decoration! as BoxDecoration;
      final thumb = containers.last.decoration! as BoxDecoration;
      expect(track.color, selected ? Colors.black : Colors.white);
      expect(track.border, Border.all(color: Colors.black, width: 2));
      expect(thumb.color, selected ? Colors.white : Colors.black);
    });
  }

  testWidgets('shows the title and subtitle', (tester) async {
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Vibração',
          subtitle: 'Toques sutis ao capturar e salvar',
          value: true,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.text('Vibração'), findsOneWidget);
    expect(find.text('Toques sutis ao capturar e salvar'), findsOneWidget);
  });

  testWidgets('tapping the row toggles the value', (tester) async {
    bool? toggled;
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Vibração',
          value: false,
          onChanged: (v) => toggled = v,
        ),
      ),
    );

    await tester.tap(find.text('Vibração'));
    expect(toggled, isTrue);
  });

  testWidgets('a null onChanged disables the tile', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Backup na conta',
          value: false,
          onChanged: null,
        ),
      ),
    );

    await tester.tap(find.text('Backup na conta'));
    expect(calls, 0);
  });

  testWidgets('plays the selection haptic by default', (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Guia de enquadramento',
          value: false,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('Guia de enquadramento'));
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('haptic: false silences the default haptic', (tester) async {
    final haptics = recordHaptics(tester);
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Vibração',
          value: false,
          onChanged: (_) {},
          haptic: false,
        ),
      ),
    );

    await tester.tap(find.text('Vibração'));
    expect(haptics, isEmpty);
  });

  testWidgets('exposes toggled and enabled semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(title: 'Vibração', value: true, onChanged: (_) {}),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Vibração'));
    expect(
      node,
      isSemantics(hasToggledState: true, isToggled: true, isEnabled: true),
    );
    semantics.dispose();
  });

  testWidgets('a disabled tile exposes enabled: false', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        const SettingsSwitchTile(
          title: 'Backup na conta',
          value: false,
          onChanged: null,
        ),
      ),
    );
    final node = tester.getSemantics(find.bySemanticsLabel('Backup na conta'));
    expect(node, isSemantics(isEnabled: false));
    semantics.dispose();
  });

  testWidgets('semantics label merges title and subtitle', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SettingsSwitchTile(
          title: 'Vibração',
          subtitle: 'Toques sutis',
          value: true,
          onChanged: (_) {},
        ),
      ),
    );
    expect(find.bySemanticsLabel('Vibração. Toques sutis'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('meets the accessibility guidelines in both themes', (
    tester,
  ) async {
    for (final (_, theme) in appThemes) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SettingsSwitchTile(
              title: 'Vibração',
              subtitle: 'Toques sutis ao capturar e salvar',
              value: true,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    }
  });
}
