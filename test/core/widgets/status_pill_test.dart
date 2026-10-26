// StatusPill is the single reusable widget for a record's sync status
// (redesign v11 §4): one of three semantic colors, never color alone — an
// icon and a label always accompany the fill.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';

import '../../support/guidelines.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('Sun gives every status a 2dp black border', (tester) async {
    for (final status in StatusPillStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: Scaffold(body: StatusPill(status: status)),
        ),
      );
      final decoration =
          tester.widget<Container>(find.byType(Container)).decoration
              as BoxDecoration;
      expect(decoration.border, Border.all(color: Colors.black, width: 2));
    }
  });

  for (final (name, theme, fontSize, minHeight) in [
    ('light', AppTheme.light, 12.0, 24.0),
    ('dark', AppTheme.dark, 12.0, 24.0),
    ('sun', AppTheme.sun, 14.0, 28.0),
  ]) {
    testWidgets('$name uses the v11 pill typography and dimensions', (
      tester,
    ) async {
      for (final status in StatusPillStatus.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(child: StatusPill(status: status)),
            ),
          ),
        );
        final label = tester.widget<Text>(find.text(status.label));
        expect(label.style?.fontSize, fontSize);
        expect(label.style?.fontWeight, FontWeight.w600);
        final container = tester.widget<Container>(find.byType(Container));
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(6));
        expect(container.constraints?.minHeight, minHeight);
        expect(
          tester.getSize(find.byType(StatusPill)).height,
          greaterThanOrEqualTo(minHeight),
        );
      }
    });
  }

  testWidgets('sent shows the sent label and icon', (tester) async {
    await tester.pumpWidget(
      host(const StatusPill(status: StatusPillStatus.sent)),
    );
    expect(find.text('Enviada'), findsOneWidget);
    expect(find.byIcon(LucideIcons.cloudCheck), findsOneWidget);
  });

  testWidgets('pending shows the pending label and icon', (tester) async {
    await tester.pumpWidget(
      host(const StatusPill(status: StatusPillStatus.pending)),
    );
    expect(find.text('Pendente'), findsOneWidget);
    expect(find.byIcon(LucideIcons.refreshCw), findsOneWidget);
  });

  testWidgets('error shows the error label and icon', (tester) async {
    await tester.pumpWidget(
      host(const StatusPill(status: StatusPillStatus.error)),
    );
    expect(find.text('Erro'), findsOneWidget);
    expect(find.byIcon(LucideIcons.cloudOff), findsOneWidget);
  });

  testWidgets('the three statuses use three distinct colors', (tester) async {
    final fills = <Color>{};
    for (final status in StatusPillStatus.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: StatusPill(status: status)),
        ),
      );
      final container = tester.widget<Container>(find.byType(Container));
      fills.add((container.decoration! as BoxDecoration).color!);
    }
    expect(fills, hasLength(3));
  });

  testWidgets('exposes the status as its semantics label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const StatusPill(status: StatusPillStatus.pending)),
    );
    expect(find.bySemanticsLabel('Pendente'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('meets the text contrast guideline in both themes', (
    tester,
  ) async {
    for (final (_, theme) in appThemes) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: Center(child: StatusPill(status: StatusPillStatus.error)),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    }
  });
}
