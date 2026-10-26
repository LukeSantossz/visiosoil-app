// StatCell/StatsRow (redesign v11 §4) back the home's stat row; see
// home_widgets_test.dart for the StatsGrid caller's own coverage.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the value and the label', (tester) async {
    await tester.pumpWidget(host(const StatCell(value: '7', label: 'Análises')));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Análises'), findsOneWidget);
  });

  testWidgets('an icon is optional', (tester) async {
    await tester.pumpWidget(host(const StatCell(
      value: '3',
      label: 'Locais',
      icon: Icons.map_outlined,
    )));
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  });

  testWidgets('default semantics label combines the value and the label',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const StatCell(value: '6', label: 'análises')));
    expect(find.bySemanticsLabel('6 análises'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('semanticLabel overrides the default reading (redesign v11 §8)',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const StatCell(
      value: '6',
      label: 'análises',
      semanticLabel: '6 análises nesta semana',
    )));
    expect(find.bySemanticsLabel('6 análises nesta semana'), findsOneWidget);
    expect(find.bySemanticsLabel('6 análises'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the skeleton renders no value/label text', (tester) async {
    await tester.pumpWidget(host(const StatCell.skeleton()));
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('the skeleton is excluded from semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const StatCell.skeleton()));
    expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
    semantics.dispose();
  });

  testWidgets('StatsRow lays cells out with equal width', (tester) async {
    await tester.pumpWidget(host(const StatsRow(cells: [
      StatCell(value: '1', label: 'a'),
      StatCell(value: '22', label: 'b'),
    ])));

    final widths = tester
        .widgetList<Expanded>(find.descendant(
          of: find.byType(StatsRow),
          matching: find.byType(Expanded),
        ))
        .map((e) => tester.getSize(find.byWidget(e.child)).width)
        .toSet();
    expect(widths, hasLength(1));
  });

  // PNG 08's cards are 120 dp tall even when every label is one line
  // (SPEC 0203; review of #437).
  testWidgets('stats_row_is_at_least_120_dp', (tester) async {
    await tester.pumpWidget(host(const StatsRow(cells: [
      StatCell(value: '1', label: 'a'),
      StatCell(value: '2', label: 'b'),
    ])));
    expect(tester.getSize(find.byType(StatsRow)).height, 120);
  });

  // The skeleton loop stops under reduced motion (redesign v11 §6.5).
  testWidgets('the skeleton does not animate under reduced motion',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(host(const StatCell.skeleton()));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('meets the accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host(const StatsRow(cells: [
      StatCell(value: '7', label: 'Análises', icon: Icons.layers),
      StatCell(value: '80%', label: 'Confiança', icon: Icons.track_changes),
    ])));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    semantics.dispose();
  });
}
