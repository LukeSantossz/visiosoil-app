// AnalysisTile (redesign v11 §4): a record row with normal/pending/error
// states, plus the AnalysisTileSkeleton placeholder. No caller yet (PR 10
// migrates the history screen's grid to this tile).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/core/widgets/confidence_badge.dart';
import 'package:visiosoil_app/core/widgets/status_pill.dart';
import 'package:visiosoil_app/models/soil_record.dart';

import '../../support/guidelines.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

Widget _sun(Widget child) => MaterialApp(
  theme: AppTheme.sun,
  home: Scaffold(body: child),
);

Border? _thumbnailBorder(WidgetTester tester) {
  final thumbnail = tester.widget<Container>(
    find.byKey(const Key('analysis-thumbnail')),
  );
  return (thumbnail.foregroundDecoration as BoxDecoration?)?.border as Border?;
}

SoilRecord classifiedRecord({
  double? confidenceScore = 0.9,
  String syncStatus = 'synced',
  ClassificationFailureCause? classificationFailure,
}) => SoilRecord(
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
  // The fit check measures real glyphs, so the width scenarios load the bundled
  // Inter faces instead of the test font, whose square glyphs are far wider.
  setUpAll(() async {
    for (final family in ['Inter', 'InterVariable']) {
      final loader = FontLoader(family);
      for (final face in ['Regular', 'Medium', 'SemiBold']) {
        final bytes = File('assets/fonts/Inter-$face.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      loader.addFont(
        Future.value(
          ByteData.view(
            File('assets/fonts/InterVariable.ttf').readAsBytesSync().buffer,
          ),
        ),
      );
      await loader.load();
    }
  });

  for (final scenario in [
    (width: 411.0, scale: 1.0, stacked: false),
    (width: 320.0, scale: 1.0, stacked: true),
    (width: 411.0, scale: 1.3, stacked: true),
  ]) {
    testWidgets('pending tile at ${scenario.width}dp and ${scenario.scale}x '
        'stacks: ${scenario.stacked}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(scenario.width, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final record = classifiedRecord(syncStatus: 'pending');
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scenario.scale)),
            child: Scaffold(body: AnalysisTile(record: record)),
          ),
        ),
      );
      final date = find.text(record.formattedTimestampCompact);
      final pill = find.byType(StatusPill);
      expect(pill, findsOneWidget);
      if (scenario.stacked) {
        expect(
          tester.getTopLeft(pill).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(date).dy),
        );
      } else {
        expect(
          tester.getTopLeft(pill).dx,
          greaterThan(tester.getBottomRight(date).dx),
        );
        expect(
          tester.getTopLeft(pill).dy,
          lessThan(tester.getBottomLeft(date).dy),
        );
      }
      expect(
        tester.renderObject<RenderParagraph>(date).didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    '320dp sync tile renders status below the text without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(), showSyncStatus: true)),
      );

      // Home names the status beside a dot (SPEC 0203).
      final metadata = find.textContaining(' · 90%');
      expect(find.text('Enviada'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Enviada')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(metadata).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 1.3]) {
    testWidgets('320dp Sun tile preserves class and date at scale $scale', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final record = classifiedRecord();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.sun,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: AnalysisTile(record: record)),
          ),
        ),
      );
      for (final text in [
        record.displayTextureClass,
        record.formattedTimestampCompact,
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Sun pending tile carries a 2dp black pill border', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.sun,
        home: Scaffold(
          body: AnalysisTile(record: classifiedRecord(syncStatus: 'pending')),
        ),
      ),
    );
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(Container),
      ),
    );
    expect(
      (container.decoration as BoxDecoration).border,
      Border.all(color: Colors.black, width: 2),
    );
  });

  group('normal state', () {
    testWidgets(
      'shows the texture class, time and a compact confidence badge',
      (tester) async {
        await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
        expect(find.text('Argilosa'), findsOneWidget);
        expect(find.byType(ConfidenceBadge), findsOneWidget);
      },
    );

    testWidgets('semantics label follows §8: class, time, pct% de confiança', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(confidenceScore: 0.82))),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Argilosa, .+, 82% de confiança$')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('tapping fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(), onTap: () => taps++)),
      );
      await tester.tap(find.byType(AnalysisTile));
      expect(taps, 1);
    });

    testWidgets(
      'a non-finite confidence score does not crash and drops the %',
      (tester) async {
        await tester.pumpWidget(
          host(
            AnalysisTile(record: classifiedRecord(confidenceScore: double.nan)),
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('pending state', () {
    testWidgets('shows the pending status pill instead of the chevron', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(syncStatus: 'pending'))),
      );
      expect(find.byType(StatusPill), findsOneWidget);
      expect(
        tester.widget<StatusPill>(find.byType(StatusPill)).status,
        StatusPillStatus.pending,
      );
    });

    testWidgets('semantics label names the pending sync', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(syncStatus: 'pending'))),
      );
      expect(
        find.bySemanticsLabel(RegExp('pendente de sincronização\$')),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('error state (classification failure)', () {
    testWidgets('shows the failure reason instead of a texture class', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          AnalysisTile(
            record: classifiedRecord(
              classificationFailure: ClassificationFailureCause.sheetNotFound,
            ),
          ),
        ),
      );
      expect(find.text('Não classificada'), findsOneWidget);
      expect(find.textContaining('Folha A4 não encontrada'), findsOneWidget);
      expect(find.byType(ConfidenceBadge), findsNothing);
      expect(find.byType(StatusPill), findsNothing);
    });

    testWidgets('semantics label names the failure, not a fabricated class', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          AnalysisTile(
            record: classifiedRecord(
              classificationFailure: ClassificationFailureCause.sheetNotFound,
            ),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Folha A4 não encontrada')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets(
      'a failed and still-unsynced record names both the failure and the '
      'pending sync',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            AnalysisTile(
              record: classifiedRecord(
                classificationFailure: ClassificationFailureCause.sheetNotFound,
                syncStatus: 'pending',
              ),
            ),
          ),
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Folha A4 não encontrada.*pendente de sincronização$'),
          ),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    testWidgets('shows the outline-colored border, not a texture color', (
      tester,
    ) async {
      // Only Modo Sol draws the photograph's edge (SPEC 0203).
      await tester.pumpWidget(
        _sun(
          AnalysisTile(
            record: classifiedRecord(
              classificationFailure: ClassificationFailureCause.sheetNotFound,
            ),
          ),
        ),
      );
      final border = _thumbnailBorder(tester)!;
      expect(border.top.color, AppPalette.sun.outline);
    });
  });

  group('thumbnail border', () {
    testWidgets('a classified record gets the texture-colored border', (
      tester,
    ) async {
      await tester.pumpWidget(_sun(AnalysisTile(record: classifiedRecord())));
      final border = _thumbnailBorder(tester)!;
      expect(border.top.color, SoilTextureColors.forClass('Argilosa'));
    });

    // PNG 08 and 16 draw the photograph without an edge (SPEC 0203).
    testWidgets('outside Modo Sol the photograph has no border', (
      tester,
    ) async {
      await tester.pumpWidget(host(AnalysisTile(record: classifiedRecord())));
      expect(_thumbnailBorder(tester), isNull);
    });
  });

  group('onDelete custom semantics action', () {
    testWidgets('adds an "Excluir" custom action when given', (tester) async {
      final semantics = tester.ensureSemantics();
      var deletes = 0;
      await tester.pumpWidget(
        host(
          AnalysisTile(record: classifiedRecord(), onDelete: () => deletes++),
        ),
      );

      final node = tester.getSemantics(find.byType(AnalysisTile));
      final actionId = CustomSemanticsAction.getIdentifier(
        const CustomSemanticsAction(label: 'Excluir'),
      );
      expect(
        node.getSemanticsData().customSemanticsActionIds,
        contains(actionId),
      );

      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.customAction,
        actionId,
      );
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

      await tester.pumpWidget(
        host(AnalysisTile(record: classifiedRecord(), dense: true)),
      );
      final denseSize = tester.getSize(find.byType(ClipRRect).first);

      expect(denseSize.width, lessThan(normalSize.width));
    });
  });

  group('skeleton', () {
    testWidgets('renders no text and is excluded from semantics', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(host(const AnalysisTileSkeleton()));
      expect(find.byType(Text), findsNothing);
      expect(find.bySemanticsLabel(RegExp('.+')), findsNothing);
      semantics.dispose();
    });
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
            body: AnalysisTile(record: classifiedRecord(), onTap: () {}),
          ),
        ),
      );
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    }
  });
}
