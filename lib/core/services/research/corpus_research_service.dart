import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/services/research/corpus_composer.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// The Tier 1 binding of [ResearchService]: it composes from the corpus the app
/// holds and **makes no request at all**.
///
/// This is the whole point of ADR 0022's architecture. Nothing per-record leaves
/// the device — not a coarsened coordinate, not a region code, not a request —
/// and online and offline take the identical code path, so a class of bug
/// disappears rather than being handled.
class CorpusResearchService implements ResearchService {
  const CorpusResearchService({
    required this._store,
    this._composer = const CorpusComposer(),
  });

  final CorpusStore _store;
  final CorpusComposer _composer;

  @override
  Future<ResearchResult> fetchTips(
    SoilRecord record, {
    String? locale,
    SiteKey? site,
    LandUse? landUse,
  }) async {
    final uuid = record.uuid;
    final textureClass = record.textureClass;
    if (uuid == null ||
        uuid.isEmpty ||
        textureClass == null ||
        textureClass.isEmpty) {
      // No identity or no class to look up. Same gate the transport applied, for
      // the same reason: a key that cannot be built is a defect in the caller.
      return const ResearchFailure(ResearchFailureKind.invalidRecord);
    }

    final key = site ?? const SiteKey.unresolved();
    final corpus = await _store.current();
    if (corpus == null) {
      return ResearchSuccess(_withoutCorpus(key, landUse));
    }
    return ResearchSuccess(
      _composer.compose(
        corpus: corpus,
        textureClass: textureClass,
        site: key,
        landUse: landUse,
      ),
    );
  }

  /// What the app answers while it holds no corpus.
  ///
  /// `insufficient_evidence` with an empty tips list and a non-empty disclaimer,
  /// which §6.5 already defines as a valid composition — and which the surface
  /// reads as "there is no coverage for this region". Reporting it as a
  /// [ResearchFailure] would put a transport error in front of a user whose
  /// device is working perfectly.
  ///
  /// `retrievedAt` is the moment the empty answer was produced, and
  /// `corpusVersion` is null, which reads as unknown and therefore stale at the
  /// next online check.
  ManagementTipsResult _withoutCorpus(SiteKey site, LandUse? landUse) {
    return ManagementTipsResult(
      status: ManagementTipsStatus.insufficientEvidence,
      tips: const [],
      sources: const [],
      disclaimer: AppStrings.managementTipsDisclaimer,
      model: 'corpus:none',
      retrievedAt: DateTime.now().toUtc(),
      limitations: const [],
      alerts: const [],
      followUpQuestions: const [],
      coverage: TipsCoverage(
        clayActivity: site.clayActivity?.wireName,
        substanceIsGeneric: site.substanceIsGeneric,
        unit: site.unit,
        unitLayerPresent: false,
        biome: site.biome?.wireName,
        landUse: landUse?.wireName,
        landUseLayerPresent: false,
      ),
    );
  }
}
