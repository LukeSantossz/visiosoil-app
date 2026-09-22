import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Orchestrates one "generate management tips" action: validates the record,
/// resolves the corpus key on the device, calls the [ResearchService], and
/// persists a successful result via [ManagementTipsRepository]. Returns `null`
/// on success or the [ResearchFailureKind] on failure; never throws (mirrors the
/// service contract). On failure the cache is left untouched.
///
/// **Resolving is orchestration, so it lives here** rather than inside a
/// service: keeping the resolver out of an implementation leaves that
/// implementation fakeable without a grid asset
/// (`docs/architecture/research-agent.md` §19.3).
///
/// **There is no connectivity gate.** One was correct while every result came
/// from a proxy, but Tier 1 composes on the device and works offline by design,
/// so refusing an offline request would withhold an answer the app already has.
/// The gate belongs to corpus *fetch* (slice A4), where being offline genuinely
/// means "cannot refresh" rather than "cannot answer".
class ManagementTipsController {
  ManagementTipsController({
    required ResearchService researchService,
    required this._repository,
    required SiteResolver siteResolver,
  })  : _research = researchService,
        _resolver = siteResolver;

  final ResearchService _research;
  final ManagementTipsRepository _repository;
  final SiteResolver _resolver;

  /// [landUse] is the one key part the device cannot derive. Null means the user
  /// declined, which §6 accepts.
  Future<ResearchFailureKind?> generate(
    SoilRecord record, {
    LandUse? landUse,
  }) async {
    final uuid = record.uuid;
    if (uuid == null || !record.hasClassification) {
      return ResearchFailureKind.invalidRecord;
    }
    final site = await _resolver.resolve(
      latitude: record.latitude,
      longitude: record.longitude,
      address: record.address,
    );
    final result = await _research.fetchTips(
      record,
      locale: 'pt-BR',
      site: site,
      landUse: landUse,
    );
    switch (result) {
      case ResearchSuccess(:final tips):
        await _repository.upsert(uuid, tips);
        return null;
      case ResearchFailure(:final kind):
        return kind;
    }
  }
}
