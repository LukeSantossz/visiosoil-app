// AnalysisTile (redesign v11 §4): a record row with normal/pending/error
// states, plus the AnalysisTileSkeleton placeholder. No caller yet (PR 10
// migrates the history screen's grid to this tile).
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../../support/guidelines.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

SoilRecord classifiedRecord({
  double? confidenceScore = 0.9,
  String syncStatus = 'synced',
  ClassificationFailureCause? classificationFailure,
}) =>
    SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T10:42:00Z',
      address: 'Fazenda Boa Vista',
      textureClass: classificationFailure != null ? null : 'Argilosa',
      confidenceScore: classificationFailure != null ? null : confidenceScore,
      syncStatus: syncStatus,
      classificationFailure: classificationFailure,
    );

void main() {
  group('normal state', () {
    testWidgets('shows the texture class, time and a compact confidence badge',
        (tester) async {
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
      expect(find.text('Argilosa'), findsOneWidget);
      expect(find.byType(ConfidenceBadge), findsOneWidget);
    });

    testWidgets('semantics label follows §8: class, time, pct% de confiança',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord(confidenceScore: 0.82))));
      expect(
        find.bySemanticsLabel(RegExp(r'^Argilosa, .+, 82% de confiança$')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('tapping fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(),
        onTap: () => taps++,
      )));
      await tester.tap(find.byType(AnalysisTile));
      expect(taps, 1);
    });

    testWidgets('a non-finite confidence score does not crash and drops the %',
        (tester) async {
      await tester.pumpWidget(host(
        AnalysisTile(record: classifiedRecord(confidenceScore: double.nan)),
      ));
      expect(tester.takeException(), isNull);
    });
  });

  group('pending state', () {
    testWidgets('shows the pending status pill instead of the chevron',
        (tester) async {
      await tester.pumpWidget(host(
        AnalysisTile(record: classifiedRecord(syncStatus: 'pending')),
      ));
      expect(find.byType(StatusPill), findsOneWidget);
      expect(
        tester.widget<StatusPill>(find.byType(StatusPill)).status,
        StatusPillStatus.pending,
      );
    });

    testWidgets('semantics label names the pending sync', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(
        AnalysisTile(record: classifiedRecord(syncStatus: 'pending')),
      ));
      expect(
        find.bySemanticsLabel(RegExp('pendente de sincronização\$')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('error state (classification failure)', () {
    testWidgets('shows the failure reason instead of a texture class',
        (tester) async {
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(
          classificationFailure: ClassificationFailureCause.sheetNotFound,
        ),
      )));
      expect(find.text('Não classificada'), findsOneWidget);
      expect(find.textContaining('Folha A4 não encontrada'), findsOneWidget);
      expect(find.byType(ConfidenceBadge), findsNothing);
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets('semantics label names the failure, not a fabricated class',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(
          classificationFailure: ClassificationFailureCause.sheetNotFound,
        ),
      )));
      expect(
        find.bySemanticsLabel(RegExp(r'Folha A4 não encontrada')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets(
        'a failed and still-unsynced record names both the failure and the '
        'pending sync', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(
          classificationFailure: ClassificationFailureCause.sheetNotFound,
          syncStatus: 'pending',
        ),
      )));
      expect(
        find.bySemanticsLabel(RegExp(
          r'Folha A4 não encontrada.*pendente de sincronização$',
        )),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('shows the outline-colored border, not a texture color',
        (tester) async {
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(
          classificationFailure: ClassificationFailureCause.sheetNotFound,
        ),
      )));
      final decoration = tester
          .widget<Container>(find.byType(Container).first)
          .decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, AppPalette.light.outline);
    });
  });

  group('thumbnail border', () {
    testWidgets('a classified record gets the texture-colored border',
        (tester) async {
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
      final decoration = tester
          .widget<Container>(find.byType(Container).first)
          .decoration as BoxDecoration;
      final border = decoration.border as Border;
      expect(border.top.color, SoilTextureColors.forClass('Argilosa'));
    });
  });

  group('onDelete custom semantics action', () {
    testWidgets('adds an "Excluir" custom action when given', (tester) async {
      final semantics = tester.ensureSemantics();
      var deletes = 0;
      await tester.pumpWidget(host(AnalysisTile(
        record: classifiedRecord(),
        onDelete: () => deletes++,
      )));

      final node = tester.getSemantics(find.byType(AnalysisTile));
      final actionId = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Excluir'),
      );
      expect(node.getSemanticsData().customSemanticsActionIds, contains(actionId));

      tester.binding.renderViews.single.owner!.semanticsOwner!
          .performAction(node.id, SemanticsAction.customAction, actionId);
      expect(deletes, 1);
      semantics.dispose();
    });

    testWidgets('no custom action when onDelete is null', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
      final node = tester.getSemantics(find.byType(AnalysisTile));
      expect(node.getSemanticsData().customSemanticsActionIds, isEmpty);
      semantics.dispose();
    });
  });

  group('dense', () {
    testWidgets('shrinks the thumbnail', (tester) async {
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
      final normalSize = tester.getSize(find.byType(ClipRRect).first);

      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord(), dense: true)));
      final denseSize = tester.getSize(find.byType(ClipRRect).first);

      expect(denseSize.width, lessThan(normalSize.width));
    });
  });

  group('skeleton', () {
    testWidgets('renders no text and is excluded from semantics',
        (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const AnalysisTileSkeleton()));
      expect(find.byType(Text), findsNothing);
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      semantics.dispose();
    });
  });

  testWidgets('meets the accessibility guidelines in both themes',
      (tester) async {
    for (final (_, theme) in appThemes) {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: AnalysisTile(record: classifiedRecord(), onTap: () {}),
        ),
      ));
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    }
  });
}
