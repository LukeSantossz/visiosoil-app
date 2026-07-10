import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Guards the history texture-filter error state (#117): a provider failure must
/// surface visible feedback with a retry, not silently collapse the chip bar.
void main() {
  testWidgets('filter error branch renders visible feedback and a retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        // Keep the records grid out of an error state so assertions target only
        // the filter chip bar.
        filteredRecordsProvider
            .overrideWith((ref) => Stream.value(<SoilRecord>[])),
        availableTextureClassesProvider.overrideWith(
          (ref) => AsyncValue<List<String>>.error(
            Exception('boom'),
            StackTrace.current,
          ),
        ),
      ],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Não foi possível carregar os filtros'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('retrying the filter re-reads the provider', (tester) async {
    var calls = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        filteredRecordsProvider
            .overrideWith((ref) => Stream.value(<SoilRecord>[])),
        availableTextureClassesProvider.overrideWith((ref) {
          calls++;
          return calls == 1
              ? AsyncValue<List<String>>.error(
                  Exception('boom'),
                  StackTrace.current,
                )
              : const AsyncValue<List<String>>.data(['Argilosa']);
        }),
      ],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    await tester.pumpAndSettle();

    // After the retry the provider succeeds and the chip is rendered.
    expect(find.text('Argilosa'), findsOneWidget);
  });
}
