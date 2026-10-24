// StatusPill is the single reusable widget for a record's sync status
// (redesign v11 §4): one of three semantic colors, never color alone — an
// icon and a label always accompany the fill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';

import '../../support/guidelines.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('sent shows the sent label and icon', (tester) async {
    await tester.pumpWidget(host(const StatusPill(status: StatusPillStatus.sent)));
    expect(find.text('Enviada'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
  });

  testWidgets('pending shows the pending label and icon', (tester) async {
    await tester
        .pumpWidget(host(const StatusPill(status: StatusPillStatus.pending)));
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('error shows the error label and icon', (tester) async {
    await tester
        .pumpWidget(host(const StatusPill(status: StatusPillStatus.error)));
    expect(find.text('Erro'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
  });

  testWidgets('the three statuses use three distinct colors', (tester) async {
    final fills = <Color>{};
    for (final status in StatusPillStatus.values) {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: Scaffold(body: StatusPill(status: status))),
      );
      final container = tester.widget<Container>(find.byType(Container));
      fills.add((container.decoration! as BoxDecoration).color!);
    }
    expect(fills, hasLength(3));
  });

  testWidgets('exposes the status as its semantics label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester
        .pumpWidget(host(const StatusPill(status: StatusPillStatus.pending)));
    expect(find.bySemanticsLabel('Pendente'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('meets the text contrast guideline in both themes',
      (tester) async {
    for (final (_, theme) in appThemes) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(child: StatusPill(status: StatusPillStatus.error)),
        ),
      ));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    }
  });
}
