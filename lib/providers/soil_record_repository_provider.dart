import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/models/home_stats.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/database_provider.dart';

/// Exposes the repository **through the interface** [SoilRecordRepository]. Screens
/// must never read [DriftSoilRecordRepository] directly.
final soilRecordRepositoryProvider = Provider<SoilRecordRepository>((ref) {
  return DriftSoilRecordRepository(ref.watch(appDatabaseProvider));
});

/// Reactive stream with all records, from most recent to oldest.
final soilRecordsStreamProvider = StreamProvider<List<SoilRecord>>((ref) {
  return ref.watch(soilRecordRepositoryProvider).watchAll();
});

/// Latest record (or `null` if there is none).
///
/// Derived from [soilRecordsStreamProvider] to share the same stream and
/// reuse the Riverpod cache, avoiding duplicate queries.
final latestSoilRecordProvider = Provider<AsyncValue<SoilRecord?>>((ref) {
  final records = ref.watch(soilRecordsStreamProvider);
  return records.whenData((list) => list.isEmpty ? null : list.first);
});

/// Loads a record by id. `family` allows obtaining the specific provider
/// for the desired id — Riverpod takes care of the cache.
final soilRecordByIdProvider =
    FutureProvider.family<SoilRecord?, int>((ref, id) {
  return ref.watch(soilRecordRepositoryProvider).getById(id);
});

/// Aggregated data for the HomeScreen, derived from the reactive stream.
///
/// Updates automatically when records are saved/deleted.
final homeStatsProvider = Provider<AsyncValue<HomeStats>>((ref) {
  final records = ref.watch(soilRecordsStreamProvider);
  return records.whenData((list) {
    final scored = list.where((r) => r.confidenceScore != null).toList();
    final avgConf = scored.isEmpty
        ? null
        : scored.fold<double>(0, (sum, r) => sum + r.confidenceScore!) /
            scored.length;

    return HomeStats(
      totalRecords: list.length,
      distinctLocations: list
          .where((r) => r.hasValidAddress)
          .map((r) => r.address)
          .toSet()
          .length,
      averageConfidence: avgConf,
    );
  });
});

// --- History Filters ---

/// Notifier for the texture class filter.
class SelectedTextureFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? textureClass) => state = textureClass;
}

/// Selected texture class filter (null = all).
final selectedTextureFilterProvider =
    NotifierProvider<SelectedTextureFilterNotifier, String?>(
        SelectedTextureFilterNotifier.new);

/// Notifier for the search term.
class SearchTermNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String term) => state = term;
}

/// Address search term.
final searchTermProvider =
    NotifierProvider<SearchTermNotifier, String>(SearchTermNotifier.new);

/// Distinct texture classes for the history filter, derived reactively from
/// the records stream so chips refresh as records are added or removed.
///
/// Mirrors [latestSoilRecordProvider]/[homeStatsProvider]: shares the single
/// [soilRecordsStreamProvider] subscription instead of a one-shot query that
/// would never refresh.
final availableTextureClassesProvider =
    Provider<AsyncValue<List<String>>>((ref) {
  final records = ref.watch(soilRecordsStreamProvider);
  return records.whenData((list) {
    final classes = <String>{
      for (final record in list)
        if (record.hasClassification) record.textureClass!,
    }.toList()
      ..sort();
    return classes;
  });
});

/// Stream of filtered records.
///
/// Combines class filter and search term. Updates automatically
/// when any filter changes or when the database is modified.
final filteredRecordsProvider = StreamProvider<List<SoilRecord>>((ref) {
  final textureClass = ref.watch(selectedTextureFilterProvider);
  final searchTerm = ref.watch(searchTermProvider);

  // If no filter is active, uses the regular stream for performance
  if ((textureClass == null || textureClass.isEmpty) &&
      searchTerm.isEmpty) {
    return ref.watch(soilRecordRepositoryProvider).watchAll();
  }

  return ref.watch(soilRecordRepositoryProvider).watchFiltered(
        textureClass: textureClass,
        searchTerm: searchTerm.isEmpty ? null : searchTerm,
      );
});
