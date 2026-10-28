// The collection counts the classes the released contract classifies, and
// counts take the singular at one (SPEC 0223).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/core/features/home/widgets/stats_grid.dart';
import 'package:visiosoil_app/core/features/profile/profile_screen.dart';
import 'package:visiosoil_app/core/features/settings/export_sheet.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/utils/formatters.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../support/fake_soil_record_repository.dart';

final _contractClasses = List<String>.from(
  (jsonDecode(File('assets/models/spec.json').readAsStringSync())
          as Map)['classes']
      as List,
);

SoilRecord _record(int id, String? textureClass) => SoilRecord(
  id: id,
  imagePath: 'missing.png',
  timestamp: DateTime.now().toIso8601String(),
  textureClass: textureClass,
  confidenceScore: textureClass == null ? null : .8,
);

final _mixed = [
  _record(1, 'Argilosa'),
  _record(2, 'Argilosa'),
  _record(3, 'Media'),
  _record(4, null),
];

class _Auth implements AuthService {
  @override
  AuthAccount? get currentAccount => null;
  @override
  Future<AuthAccount?> restoreSession() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Override _classes({bool fail = false}) => contractClassesProvider.overrideWith(
  (ref) async => fail ? throw StateError('no contract') : _contractClasses,
);

Future<void> _pumpHistory(
  WidgetTester tester,
  List<SoilRecord> records, {
  bool fail = false,
}) async {
  final data = AsyncData(records);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soilRecordRepositoryProvider.overrideWithValue(
          FakeSoilRecordRepository(),
        ),
        soilRecordsStreamProvider.overrideWithValue(data),
        filteredRecordsProvider.overrideWithValue(data),
        connectivityStatusProvider.overrideWithValue(
          const AsyncData(ConnectivityStatus.online),
        ),
        _classes(fail: fail),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HistoryScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpProfile(
  WidgetTester tester,
  List<SoilRecord> records, {
  bool fail = false,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh scope, so a second pump in one test takes its own records.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_Auth()),
        soilRecordsStreamProvider.overrideWith((ref) => Stream.value(records)),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectivityStatus.online),
        ),
        _classes(fail: fail),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpStats(
  WidgetTester tester,
  List<SoilRecord> records, {
  List<String>? classes,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatsGrid(
          recordsAsync: AsyncData(records),
          collectionClasses: classes,
        ),
      ),
    ),
  );
}

StatCell _collectionCell(WidgetTester tester) => tester
    .widgetList<StatCell>(find.byType(StatCell))
    .firstWhere((cell) => cell.label == 'coleção');

Future<void> _openCollection(WidgetTester tester) async {
  await tester.tap(find.text('Coleção'));
  await tester.pumpAndSettle();
}

void main() {
  test('contract_classes_come_from_the_contract', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      await container.read(contractClassesProvider.future),
      _contractClasses,
    );
  });

  group('collection_counts_contract_classes', () {
    testWidgets('home', (tester) async {
      await _pumpStats(tester, _mixed, classes: _contractClasses);
      final cell = _collectionCell(tester);
      expect(cell.value, '2/4');
      expect(cell.semanticLabel, '2 de 4 classes na coleção');
    });

    testWidgets('profile', (tester) async {
      await _pumpProfile(tester, _mixed);
      final cell = _collectionCell(tester);
      expect(cell.value, '2/4');
      expect(cell.semanticLabel, '2 de 4 classes na coleção');
    });

    testWidgets('history summary', (tester) async {
      await _pumpHistory(tester, _mixed);
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary')),
          matching: find.text('2/4'),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('collection_ignores_names_outside_the_contract', (tester) async {
    final semantics = tester.ensureSemantics();
    final usda = [_record(1, 'Argila')];
    await _pumpStats(tester, usda, classes: _contractClasses);
    expect(_collectionCell(tester).value, '0/4');

    await _pumpHistory(tester, usda);
    await _openCollection(tester);
    expect(find.bySemanticsLabel(RegExp(r', conquistada$')), findsNothing);
    expect(find.text('Argila'), findsNothing);
    semantics.dispose();
  });

  testWidgets('collection_grid_lists_contract_classes', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pumpHistory(tester, _mixed);
    await _openCollection(tester);

    const labels = ['Arenosa', 'Média', 'Muito argilosa', 'Argilosa'];
    final tiles = find.bySemanticsLabel(RegExp(r', (não )?conquistada$'));
    expect(tiles, findsNWidgets(4));
    final tops = [
      for (final label in labels)
        tester.getRect(find.bySemanticsLabel(RegExp('^$label, '))).topLeft,
    ];
    for (var i = 1; i < tops.length; i++) {
      final before = tops[i - 1];
      final after = tops[i];
      expect(
        after.dy > before.dy || (after.dy == before.dy && after.dx > before.dx),
        isTrue,
        reason: '${labels[i]} after ${labels[i - 1]}',
      );
    }
    expect(find.bySemanticsLabel('Argilosa, conquistada'), findsOneWidget);
    expect(find.bySemanticsLabel('Média, conquistada'), findsOneWidget);
    expect(find.bySemanticsLabel('Arenosa, não conquistada'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Muito argilosa, não conquistada'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  group('collection_without_contract_reads_a_dash', () {
    testWidgets('home', (tester) async {
      await _pumpStats(tester, _mixed);
      expect(_collectionCell(tester).value, '—');
      expect(tester.takeException(), isNull);
    });

    testWidgets('profile', (tester) async {
      await _pumpProfile(tester, _mixed, fail: true);
      expect(_collectionCell(tester).value, '—');
      expect(tester.takeException(), isNull);
    });

    testWidgets('history summary', (tester) async {
      await _pumpHistory(tester, _mixed, fail: true);
      expect(
        find.descendant(
          of: find.byKey(const Key('history-summary')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('counts_take_the_singular_at_one', () {
    testWidgets('profile', (tester) async {
      await _pumpProfile(tester, [_record(1, 'Argilosa')]);
      expect(
        find.text('1 análise e 1 classe guardadas neste aparelho'),
        findsOneWidget,
      );
      await _pumpProfile(tester, const []);
      expect(
        find.text('0 análises e 0 classes guardadas neste aparelho'),
        findsOneWidget,
      );
      await _pumpProfile(tester, [_record(1, 'Argilosa'), _record(2, 'Media')]);
      expect(
        find.text('2 análises e 2 classes guardadas neste aparelho'),
        findsOneWidget,
      );
    });

    for (final (count, text) in [
      (0, '0 análises em uma planilha CSV.'),
      (1, '1 análise em uma planilha CSV.'),
      (2, '2 análises em uma planilha CSV.'),
    ]) {
      testWidgets('export sheet with $count', (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              soilRecordsStreamProvider.overrideWith(
                (ref) => Stream.value([
                  for (var id = 1; id <= count; id++) _record(id, 'Argilosa'),
                ]),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(body: ExportSheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget);
      });
    }

    testWidgets('weekly semantics', (tester) async {
      await _pumpStats(tester, [_record(1, 'Argilosa')]);
      expect(
        tester.widgetList<StatCell>(find.byType(StatCell)).first.semanticLabel,
        '1 análise nesta semana',
      );
    });
  });

  test('Formatters.count', () {
    expect(Formatters.count(0, 'análise', 'análises'), '0 análises');
    expect(Formatters.count(1, 'análise', 'análises'), '1 análise');
    expect(Formatters.count(2, 'análise', 'análises'), '2 análises');
  });
}
