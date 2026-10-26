// The settings row and group, the segmented control's separator and compact
// mode, the Google button and the account card follow PNG 21 and 23 as
// SPEC 0204 measures them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/account_card.dart';
import 'package:visiosoil_app/core/widgets/google_sign_in_button.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.light,
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

BoxDecoration _groupDecoration(WidgetTester tester) =>
    tester
            .widget<Container>(find.byKey(const Key('settings-group')))
            .decoration!
        as BoxDecoration;

void main() {
  testWidgets('settings_rows_match_the_mock', (tester) async {
    await tester.pumpWidget(
      _host(
        SettingsTile(
          icon: LucideIcons.ruler,
          title: 'Unidades',
          subtitle: 'Distância em cm',
          onTap: () {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(SettingsTile)).height, 56);
    final icon = tester.widget<Icon>(find.byIcon(LucideIcons.ruler));
    expect(icon.size, 22);
    expect(icon.color, AppPalette.light.primaryText);
    final title = tester.widget<Text>(find.text('Unidades'));
    expect(title.style?.fontSize, 15);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(
      tester.widget<Text>(find.text('Distância em cm')).style?.fontSize,
      13,
    );
    final chevron = tester.widget<Icon>(find.byIcon(LucideIcons.chevronRight));
    expect(chevron.color, AppPalette.light.textTertiary);
    expect(chevron.size, 20);
  });

  testWidgets('settings_groups_are_flat', (tester) async {
    const group = SettingsGroup(
      children: [
        SettingsTile(icon: LucideIcons.info, title: 'Versão'),
        SettingsTile(icon: LucideIcons.shield, title: 'Privacidade'),
      ],
    );
    await tester.pumpWidget(_host(group));
    final flat = _groupDecoration(tester);
    expect(flat.color, AppPalette.light.surface);
    expect(flat.borderRadius, BorderRadius.circular(16));
    expect(flat.boxShadow, isNull);
    expect(flat.border, isNull);
    expect(find.byType(Card), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_host(group, theme: AppTheme.sun));
    expect(_groupDecoration(tester).border, isNotNull);
  });

  testWidgets('segments_are_separated', (tester) async {
    await tester.pumpWidget(
      _host(
        SegmentedControl<bool>(
          value: false,
          onChanged: (_) {},
          options: const [
            SegmentedControlOption(value: false, label: 'Análises'),
            SegmentedControlOption(value: true, label: 'Coleção'),
          ],
        ),
      ),
    );
    expect(find.byKey(const Key('segment-separator')), findsOneWidget);
  });

  testWidgets('compact segments draw a 32 dp pill with a 48 dp target', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Align(
          alignment: Alignment.topRight,
          child: SegmentedControl<ThemeMode>(
            compact: true,
            value: ThemeMode.light,
            onChanged: (_) {},
            options: const [
              SegmentedControlOption(value: ThemeMode.system, label: 'Sistema'),
              SegmentedControlOption(value: ThemeMode.light, label: 'Claro'),
              SegmentedControlOption(value: ThemeMode.dark, label: 'Escuro'),
            ],
          ),
        ),
      ),
    );
    final pill = tester.getSize(find.byKey(const Key('segmented-pill')));
    expect(pill.height, 32);
    // Sized to its labels, not to the 768 dp the row offers.
    expect(pill.width, lessThan(768));
    expect(
      tester.getSize(find.byKey(const Key('segment-0'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byKey(const Key('segment-separator')), findsNWidgets(2));
  });

  testWidgets('google_button_wears_google_colours', (tester) async {
    await tester.pumpWidget(
      _host(GoogleSignInButton(isLoading: false, onPressed: () {})),
    );

    final button = find.byType(OutlinedButton);
    expect(tester.getSize(button).height, 48);
    final style = tester.widget<OutlinedButton>(button).style!;
    expect(style.backgroundColor?.resolve({}), Colors.white);
    expect(style.side?.resolve({})?.color, const Color(0xFF747775));
    final label = tester.widget<Text>(find.text('Continuar com o Google'));
    expect(label.style?.color, const Color(0xFF1F1F1F));
    expect(label.style?.fontSize, 17);
  });

  // Modo Sol keeps its 56 dp target (review of #438).
  testWidgets('sun_google_button_keeps_the_56_dp_target', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.sun,
      home: Scaffold(
        body: GoogleSignInButton(isLoading: false, onPressed: () {}),
      ),
    ));

    expect(tester.getSize(find.byType(OutlinedButton)).height, 56);
  });

  // At 200 % text a compact control wider than its room shrinks its
  // segments, and the indicator keeps their width (review of #438).
  testWidgets('compact_segments_fit_their_room', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: SegmentedControl<String>(
                compact: true,
                options: const [
                  SegmentedControlOption(value: 'a', label: 'Claro'),
                  SegmentedControlOption(value: 'b', label: 'Escuro'),
                ],
                value: 'a',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));

    final control = find.byType(SegmentedControl<String>);
    expect(tester.getSize(control).width, lessThanOrEqualTo(160));
    final indicator = find.descendant(
      of: control,
      matching: find.byType(AnimatedPositioned),
    );
    expect(
      tester.getSize(indicator).width,
      closeTo(tester.getSize(find.byKey(const Key('segment-0'))).width, 0.5),
    );
  });

  testWidgets('profile_account_card_matches_the_mock', (tester) async {
    await tester.pumpWidget(_host(const AccountCard(child: Text('Corpo'))));

    final card = tester.widget<Container>(
      find.byKey(const Key('account-card')),
    );
    expect(
      (card.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(24),
    );
    expect(
      tester.getSize(find.byKey(const Key('account-avatar'))),
      const Size(56, 56),
    );
    expect(tester.widget<Icon>(find.byIcon(LucideIcons.user)).size, 28);
    expect(
      tester.widget<Text>(find.text('Sem conta vinculada')).style?.fontSize,
      18,
    );
  });
}
