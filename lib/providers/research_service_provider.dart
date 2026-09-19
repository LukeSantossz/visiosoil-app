import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/corpus_research_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/providers/corpus_store_provider.dart';

/// The [ResearchService] seam, bound to Tier 1: the app composes management tips
/// on the device from the corpus it holds, with no network call and no
/// per-record request at all (ADR 0022).
///
/// This replaced `UnavailableResearchService`, which reported a proxy that was
/// never built as unavailable.
final researchServiceProvider = Provider<ResearchService>((ref) {
  return CorpusResearchService(store: ref.watch(corpusStoreProvider));
});
