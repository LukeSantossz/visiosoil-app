import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/settings/export_sheet.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

class _Share extends ShareService {
  List<bool>? options;
  Exception? failure;
  Completer<void>? pending;
  @override
  Future<void> shareExport(
    List<SoilRecord> records, {
    required bool includeDate,
    required bool includeLocation,
    required bool includePhotos,
  }) async {
    options = [includeDate, includeLocation, includePhotos];
    if (failure != null) throw failure!;
    await pending?.future;
  }
}

void main() {
  const record = SoilRecord(
    imagePath: '',
    timestamp: '2026-10-24',
    textureClass: 'Argilosa',
    confidenceScore: .8,
  );
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
    ('sun', AppTheme.sun),
  ]) {
    for (final state in ['ready', 'empty', 'loading', 'error']) {
      testWidgets('export $state in $name exposes accessible column choices', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              soilRecordsStreamProvider.overrideWith(
                (ref) => switch (state) {
                  'loading' => const Stream<List<SoilRecord>>.empty(),
                  'error' => Stream<List<SoilRecord>>.error(
                    Exception('unavailable'),
                  ),
                  _ => Stream.value(state == 'empty' ? [] : [record]),
                },
              ),
            ],
            child: MaterialApp(
              theme: theme,
              home: const Scaffold(body: ExportSheet()),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (state == 'loading') {
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
        }
        if (state == 'error') {
          expect(
            find.text('Não foi possível carregar suas análises.'),
            findsOneWidget,
          );
        }
        if (state == 'ready' || state == 'empty') {
          expect(
            find.text(
              '${state == 'empty' ? 0 : 1} análises em uma planilha CSV.',
            ),
            findsOneWidget,
          );
        }
        expect(
          find.bySemanticsLabel(RegExp('Classe e confiança')),
          findsWidgets,
        );
        final fixed = tester.widget<CheckboxListTile>(
          find.widgetWithText(CheckboxListTile, 'Classe e confiança'),
        );
        expect(fixed.value, isTrue);
        expect(fixed.onChanged, isNull);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
    testWidgets(
      'export in $name shares chosen options and displays a recoverable failure',
      (tester) async {
        final share = _Share()..failure = Exception('private path');
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              soilRecordsStreamProvider.overrideWith(
                (ref) => Stream.value([record]),
              ),
              shareServiceProvider.overrideWithValue(share),
            ],
            child: MaterialApp(
              theme: theme,
              home: const Scaffold(body: ExportSheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Data e hora'));
        await tester.tap(find.text('Localização aproximada'));
        await tester.tap(find.text('Incluir fotos (arquivo .zip)'));
        await tester.tap(find.text('Exportar'));
        await tester.pumpAndSettle();
        expect(share.options, [false, true, true]);
        expect(
          find.text('Não foi possível exportar as análises. Tente de novo.'),
          findsOneWidget,
        );
        expect(find.textContaining('private path'), findsNothing);
        share.failure = null;
        share.pending = Completer<void>();
        await tester.ensureVisible(find.text('Exportar'));
        await tester.tap(find.text('Exportar'));
        await tester.pump();
        expect(find.text('Exportando…'), findsOneWidget);
        share.pending!.complete();
        await tester.pumpAndSettle();
      },
    );
  }
}
