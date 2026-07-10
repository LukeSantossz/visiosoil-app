import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/history/history_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

/// Guards the history texture-filter error state (#117): a provider failure must
/// surface visible feedback with a retry that actually re-reads the underlying
/// records stream, not silently collapse the chip bar.
final class _DisposeSpy extends ProviderObserver {
  final disposed = <Object?>[];

  @override
  void didDisposeProvider(ProviderObserverContext context) {
    disposed.add(context.provider);
  }
}

void main() {
  // A synchronous AsyncError on the root stream reliably drives the chips into
  // the error branch (async stream errors do not settle under flutter_test).
  final rootError = soilRecordsStreamProvider.overrideWithValue(
    AsyncValue<List<SoilRecord>>.error(Exception('boom'), StackTrace.current),
  );
  final emptyGrid =
      filteredRecordsProvider.overrideWith((ref) => Stream.value(<SoilRecord>[]));

  testWidgets('filter error branch renders visible feedback and a retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [emptyGrid, rootError],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();

    expect(find.text('Não foi possível carregar os filtros'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('retry invalidates the root records stream, not just the wrapper',
      (tester) async {
    final spy = _DisposeSpy();
    await tester.pumpWidget(ProviderScope(
      observers: [spy],
      overrides: [emptyGrid, rootError],
      child: const MaterialApp(home: HistoryScreen()),
    ));
    await tester.pump();

    expect(find.text('Tentar novamente'), findsOneWidget);
    spy.disposed.clear();
    await tester.tap(find.text('Tentar novamente'));
    await tester.pump();

    // The retry must invalidate the root records stream so a transient failure
    // actually re-runs; invalidating only the derived wrapper would re-read the
    // same cached failed stream.
    expect(spy.disposed, contains(soilRecordsStreamProvider));
  });
}
