import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/data/repositories/drift_soil_record_repository.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
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
