import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Safe default [ResearchService] used until the real proxy transport is wired
/// in issue #95. Performs no network call and reports the proxy as unavailable,
/// so the Details tips section degrades to a clear "unavailable" state instead
/// of crashing.
class UnavailableResearchService implements ResearchService {
  const UnavailableResearchService();

  @override
  Future<ResearchResult> fetchTips(SoilRecord record, {String? locale}) async {
    return const ResearchFailure(ResearchFailureKind.upstreamUnavailable);
  }
}
