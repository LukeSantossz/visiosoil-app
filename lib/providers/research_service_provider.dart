import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/services/research/unavailable_research_service.dart';

/// The [ResearchService] seam. Defaults to [UnavailableResearchService] until
/// the real proxy + per-user auth wiring lands in issue #95; overridden in
/// tests with a fake.
final researchServiceProvider = Provider<ResearchService>((ref) {
  return const UnavailableResearchService();
});
