import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/compare/compare_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/large_text.dart';

/// A repository that serves records by id, and can fail every read.
final class _RecordsById extends FakeSoilRecordRepository {
  _RecordsById(this.records);

  final Map<int, SoilRecord> records;
  bool fail = false;
  final List<int> getByIdCalls = <int>[];

  @override
  Future<SoilRecord?> getById(int id) async {
    getByIdCalls.add(id);
    if (fail) throw Exception('forced read failure');
    return records[id];
  }
}

void main() {
  final older = SoilRecord(
    id: 1,
    imagePath: 'older.png',
    timestamp: '2026-05-01T09:00:00Z',
    latitude: -23.55052,
    longitude: -46.633308,
    address: 'Fazenda Boa Vista, Talhão norte',
    textureClass: 'Argilosa',
    confidenceScore: 0.91,
    fieldName: 'Talhão 1',
    sampleLabel: 'A',
  );
  final newer = SoilRecord(
    id: 2,
    imagePath: 'newer.png',
    timestamp: '2026-06-15T16:30:00Z',
    latitude: -22.9068,
    longitude: -43.1729,
    address: 'Sítio Esperança',
    textureClass: 'Arenosa',
    confidenceScore: 0.64,
    fieldName: 'Talhão 2',
    sampleLabel: 'B',
  );
  final bare = SoilRecord(
    id: 3,
    imagePath: 'bare.png',
    timestamp: '2026-04-01T08:00:00Z',
  );

  Widget appWith(
    _RecordsById repository,
    int firstId,
    int secondId, {
    ThemeData? theme,
  }) {
    return ProviderScope(
      overrides: [soilRecordRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: theme,
        home: CompareScreen(firstId: firstId, secondId: secondId),
      ),
    );
  }

  testWidgets('compare_shows_both_records', (tester) async {
    await tester.pumpWidget(
      appWith(_RecordsById({1: older, 2: newer}), 1, 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('Comparar registros'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(2));
    for (final record in [older, newer]) {
      expect(find.text(record.labelsSummary), findsOneWidget);
      expect(find.text(record.textureClass!), findsOneWidget);
      expect(find.text(record.formattedConfidence), findsOneWidget);
      expect(find.text(record.formattedTimestamp), findsOneWidget);
      expect(find.text(record.address!), findsOneWidget);
      expect(find.text(record.formattedCoordinates), findsOneWidget);
    }
    for (final caption in [
      'Classe textural',
      'Confiança',
      'Data da coleta',
      'Localização',
    ]) {
      expect(find.text(caption), findsOneWidget);
    }
  });

  testWidgets('compare_orders_older_first', (tester) async {
    // The newer record's id comes first; the older one still sits left.
    await tester.pumpWidget(
      appWith(_RecordsById({1: older, 2: newer}), 2, 1),
    );
    await tester.pumpAndSettle();

    final olderX = tester.getCenter(find.text(older.labelsSummary)).dx;
    final newerX = tester.getCenter(find.text(newer.labelsSummary)).dx;
    expect(olderX, lessThan(newerX));
    expect(
      tester.getCenter(find.text(older.textureClass!)).dx,
      lessThan(tester.getCenter(find.text(newer.textureClass!)).dx),
    );
  });

  testWidgets('compare_shows_missing_values', (tester) async {
    await tester.pumpWidget(
      appWith(_RecordsById({2: newer, 3: bare}), 3, 2),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sem identificação'), findsOneWidget);
    expect(find.text('Não classificado'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('Endereço indisponível'), findsOneWidget);
    expect(find.text(bare.formattedCoordinates), findsNothing);
    expect(find.text(newer.formattedCoordinates), findsOneWidget);
  });

  testWidgets('compare_reports_a_missing_record', (tester) async {
    await tester.pumpWidget(appWith(_RecordsById({1: older}), 1, 99));
    await tester.pumpAndSettle();

    expect(find.text('Registro não encontrado'), findsOneWidget);
    expect(find.text(older.labelsSummary), findsNothing);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  testWidgets('compare_reports_a_load_error', (tester) async {
    final repository = _RecordsById({1: older, 2: newer})..fail = true;
    await tester.pumpWidget(appWith(repository, 1, 2));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar os registros.'), findsOneWidget);

    repository
      ..fail = false
      ..getByIdCalls.clear();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    expect(repository.getByIdCalls, containsAll(<int>[1, 2]));
    expect(find.text(older.labelsSummary), findsOneWidget);
    expect(find.text(newer.labelsSummary), findsOneWidget);
  });

  testWidgets('compare_is_read_only', (tester) async {
    final repository = _RecordsById({1: older, 2: newer});
    await tester.pumpWidget(ProviderScope(
      overrides: [soilRecordRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const CompareScreen(firstId: 1, secondId: 2),
          ),
          for (final path in ['/details', '/preview', '/capture'])
            GoRoute(
              path: path,
              builder: (_, _) => Scaffold(body: Text('STUB $path')),
            ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    for (final icon in [
      Icons.edit,
      Icons.share_outlined,
      Icons.delete_outline,
      Icons.add_a_photo_outlined,
    ]) {
      expect(find.byIcon(icon), findsNothing);
    }
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Compartilhar'), findsNothing);

    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('STUB'), findsNothing);
    expect(find.text('Comparar registros'), findsOneWidget);
  });

  testWidgets('compare_scales_to_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);
    final long = 'Fazenda Santa Maria da Serra, estrada vicinal sem número, '
        'quilômetro 42, zona rural';
    await tester.pumpWidget(appWith(
      _RecordsById({
        1: older.copyWith(
          address: long,
          fieldName: 'Talhão de soja da encosta sul perto do açude',
          sampleLabel: 'Amostra profunda 0–20 cm',
        ),
        2: newer.copyWith(address: long),
      }),
      1,
      2,
    ));
    await tester.pumpAndSettle();
    await scrollToTheEnd(tester);

    expect(tester.takeException(), isNull);
  });

  // The screen passes Flutter's four accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('compare_meets_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        appWith(_RecordsById({1: older, 3: bare}), 1, 3, theme: theme),
      );
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
