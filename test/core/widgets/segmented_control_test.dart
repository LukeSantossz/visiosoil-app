// SegmentedControl (redesign v11 §4): a pill control whose indicator slides
// to the selected option.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';

import '../../support/guidelines.dart';
import '../../support/haptics_recorder.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

const options = [
  SegmentedControlOption(value: 'list', label: 'Análises', icon: Icons.history),
  SegmentedControlOption(value: 'coll', label: 'Coleção', icon: Icons.layers),
];

void main() {
  testWidgets('Sun selected segment has black fill and white label and icon', (
    tester,
  ) async {
    for (final value in ['list', 'coll']) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: Scaffold(
            body: SegmentedControl<String>(
              options: options,
              value: value,
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final indicator = tester.widget<Container>(
        find.descendant(
          of: find.byType(AnimatedPositioned),
          matching: find.byType(Container),
        ),
      );
      expect(indicator.color, Colors.black);
      final selected = options.firstWhere((option) => option.value == value);
      final labelColor = tester
          .widget<Text>(find.text(selected.label))
          .style!
          .color!;
      expect(labelColor, Colors.white);
      expect(
        tester.widget<Icon>(find.byIcon(selected.icon!)).color,
        Colors.white,
      );
      final contrast =
          (labelColor.computeLuminance() + 0.05) /
          (indicator.color!.computeLuminance() + 0.05);
      expect(contrast, greaterThanOrEqualTo(7));
      final unselected = options.firstWhere((option) => option.value != value);
      expect(
        tester.widget<Text>(find.text(unselected.label)).style!.color,
        isNot(Colors.white),
      );
    }
  });

  testWidgets('shows every option label', (tester) async {
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (_) {},
    )));
    expect(find.text('Análises'), findsOneWidget);
    expect(find.text('Coleção'), findsOneWidget);
  });

  testWidgets('tapping an unselected option calls onChanged', (tester) async {
    String? selected;
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (v) => selected = v,
    )));

    await tester.tap(find.text('Coleção'));
    expect(selected, 'coll');
  });

  testWidgets('tapping the already-selected option does not call onChanged',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (_) => calls++,
    )));

    await tester.tap(find.text('Análises'));
    expect(calls, 0);
  });

  testWidgets('plays the selection haptic only when the value changes',
      (tester) async {
    final haptics = recordHaptics(tester);

    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (_) {},
    )));

    await tester.tap(find.text('Análises'));
    expect(haptics, isEmpty);

    await tester.tap(find.text('Coleção'));
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });

  testWidgets('the indicator slides to the selected option over AppMotion.base',
      (tester) async {
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (_) {},
    )));
    final before = tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left;

    // A new `value` is a new target for the same AnimatedPositioned: its
    // `left` (the animation's end point) updates on the very next build,
    // ahead of the tween settling there over AppMotion.base.
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'coll',
      onChanged: (_) {},
    )));
    final after = tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left;
    expect(after, isNot(before));

    await tester.pump(AppMotion.base);
  });

  testWidgets('each option exposes button and selected semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(SegmentedControl<String>(
      options: options,
      value: 'list',
      onChanged: (_) {},
    )));

    final selectedNode = tester.getSemantics(find.bySemanticsLabel('Análises'));
    expect(selectedNode, isSemantics(isButton: true, isSelected: true));
    final unselectedNode =
        tester.getSemantics(find.bySemanticsLabel('Coleção'));
    expect(unselectedNode, isSemantics(isButton: true, isSelected: false));
    semantics.dispose();
  });

  testWidgets('meets the accessibility guidelines in both themes',
      (tester) async {
    for (final (_, theme) in appThemes) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SegmentedControl<String>(
            options: options,
            value: 'list',
            onChanged: (_) {},
          ),
        ),
      ));
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    }
  });
}
