// Direct render tests for the history screen's extracted widgets (#120):
// HistoryFilterBar (search field + texture chips) and HistoryGrid (results grid
// and empty state). Complements the flow coverage in history_screen_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_grid.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

SoilRecord record({int id = 1, String textureClass = 'Argilosa'}) => SoilRecord(
      id: id,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: textureClass,
      confidenceScore: 0.9,
    );

void main() {
  group('HistoryFilterBar', () {
    testWidgets('renders the search field and a chip per available class',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record()]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HistoryFilterBar(
              searchController: TextEditingController(),
              onSearchChanged: (_) {},
              onClearSearch: () {},
              onSelectTexture: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Argilosa'), findsOneWidget);
    });

    testWidgets('tapping a class chip forwards it to onSelectTexture',
        (tester) async {
      String? selected;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordsStreamProvider.overrideWithValue(
            AsyncValue<List<SoilRecord>>.data([record()]),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: HistoryFilterBar(
              searchController: TextEditingController(),
              onSearchChanged: (_) {},
              onClearSearch: () {},
              onSelectTexture: (value) => selected = value,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Argilosa'));
      expect(selected, 'Argilosa');
    });
  });

  group('HistoryGrid', () {
    Widget gridWith(List<SoilRecord> records) => ProviderScope(
          overrides: [
            filteredRecordsProvider.overrideWith((ref) => Stream.value(records)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: HistoryGrid(
                maxRecords: 150,
                selectedIds: const <int>{},
                isSelectionMode: false,
                onTap: (_) {},
                onLongPress: (_) {},
              ),
            ),
          ),
        );

    testWidgets('renders a thumbnail card per record', (tester) async {
      await tester.pumpWidget(gridWith([record(id: 1), record(id: 2)]));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('shows the empty history state when there are no records',
        (tester) async {
      await tester.pumpWidget(gridWith(const <SoilRecord>[]));
      await tester.pumpAndSettle();

      expect(find.text('Nenhum registro'), findsOneWidget);
    });
  });
}
