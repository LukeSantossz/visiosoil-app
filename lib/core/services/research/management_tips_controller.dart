import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Orchestrates one "generate management tips" action: validates the record,
/// checks connectivity, calls the [ResearchService], and persists a successful
/// result via [ManagementTipsRepository]. Returns `null` on success or the
/// [ResearchFailureKind] on failure; never throws (mirrors the service
/// contract). On failure the cache is left untouched.
class ManagementTipsController {
  ManagementTipsController({
    required ResearchService researchService,
    required ManagementTipsRepository repository,
    required ConnectivityService connectivity,
  })  : _research = researchService,
        _repository = repository,
        _connectivity = connectivity;

  final ResearchService _research;
  final ManagementTipsRepository _repository;
  final ConnectivityService _connectivity;

  Future<ResearchFailureKind?> generate(SoilRecord record) async {
    final uuid = record.uuid;
    if (uuid == null || !record.hasClassification) {
      return ResearchFailureKind.invalidRecord;
    }
    if (await _connectivity.current() == ConnectivityStatus.offline) {
      return ResearchFailureKind.network;
    }
    final result = await _research.fetchTips(record, locale: 'pt-BR');
    switch (result) {
      case ResearchSuccess(:final tips):
        await _repository.upsert(uuid, tips);
        return null;
      case ResearchFailure(:final kind):
        return kind;
    }
  }
}
