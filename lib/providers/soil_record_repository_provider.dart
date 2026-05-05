import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/models/home_stats.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/database_provider.dart';

/// Expõe o repositório **pela interface** [SoilRecordRepository]. As telas
/// nunca devem ler diretamente [DriftSoilRecordRepository].
final soilRecordRepositoryProvider = Provider<SoilRecordRepository>((ref) {
  return DriftSoilRecordRepository(ref.watch(appDatabaseProvider));
});

/// Stream reativa com todos os registros, do mais recente ao mais antigo.
final soilRecordsStreamProvider = StreamProvider<List<SoilRecord>>((ref) {
  return ref.watch(soilRecordRepositoryProvider).watchAll();
});

/// Último registro (ou `null` se não houver nenhum).
///
/// Derivado da [soilRecordsStreamProvider] para aproveitar o mesmo stream e
/// reaproveitar o cache do Riverpod, evitando consultas duplicadas.
final latestSoilRecordProvider = Provider<AsyncValue<SoilRecord?>>((ref) {
  final records = ref.watch(soilRecordsStreamProvider);
  return records.whenData((list) => list.isEmpty ? null : list.first);
});

/// Carrega um registro por id. `family` permite obter o provider específico
/// para o id desejado — o Riverpod cuida do cache.
final soilRecordByIdProvider =
    FutureProvider.family<SoilRecord?, int>((ref, id) {
  return ref.watch(soilRecordRepositoryProvider).getById(id);
});

/// Dados agregados para a HomeScreen, derivados do stream reativo.
///
/// Atualiza automaticamente ao salvar/deletar registros.
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

// --- Filtros do Historico ---

/// Notifier para filtro de classe de textura.
class SelectedTextureFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? textureClass) => state = textureClass;
}

/// Filtro de classe de textura selecionado (null = todas).
final selectedTextureFilterProvider =
    NotifierProvider<SelectedTextureFilterNotifier, String?>(
        SelectedTextureFilterNotifier.new);

/// Notifier para termo de busca.
class SearchTermNotifier extends Notifier<String> {
  @override
  String build() => '';

  void update(String term) => state = term;
}

/// Termo de busca por endereco.
final searchTermProvider =
    NotifierProvider<SearchTermNotifier, String>(SearchTermNotifier.new);

/// Classes de textura disponiveis para filtro.
final availableTextureClassesProvider = FutureProvider<List<String>>((ref) {
  return ref.watch(soilRecordRepositoryProvider).getDistinctTextureClasses();
});

/// Stream de registros filtrados.
///
/// Combina filtro de classe e termo de busca. Atualiza automaticamente
/// quando qualquer filtro muda ou quando o banco e modificado.
final filteredRecordsProvider = StreamProvider<List<SoilRecord>>((ref) {
  final textureClass = ref.watch(selectedTextureFilterProvider);
  final searchTerm = ref.watch(searchTermProvider);

  // Se nenhum filtro ativo, usa stream normal para performance
  if ((textureClass == null || textureClass.isEmpty) &&
      searchTerm.isEmpty) {
    return ref.watch(soilRecordRepositoryProvider).watchAll();
  }

  return ref.watch(soilRecordRepositoryProvider).watchFiltered(
        textureClass: textureClass,
        searchTerm: searchTerm.isEmpty ? null : searchTerm,
      );
});
