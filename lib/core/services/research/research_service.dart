import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// Supplies the bearer token for a proxy request, or null when the caller is
/// unauthenticated. Injected so per-user auth wiring (issue #95) can plug in a
/// real token source without changing the service — mirroring the injected
/// `ModelAssetLoader` seam in `InferenceService`.
typedef TokenProvider = Future<String?> Function();

/// Why a research request could not yield tips. Each value maps to a distinct
/// UI state (error vs offline vs rejected) for the Details section (issue #94).
enum ResearchFailureKind {
  /// The record lacks the data required to ask for tips (uuid or texture class).
  invalidRecord,

  /// Proxy returned 401 — the bearer token is missing, invalid, or expired.
  unauthenticated,

  /// Proxy returned 429 — per-user rate limit or quota exceeded.
  rateLimited,

  /// Proxy returned 5xx — the Groq/Tavily upstream is unavailable.
  upstreamUnavailable,

  /// The request exceeded the configured timeout.
  timeout,

  /// A connection-level error (no network, DNS failure, socket reset).
  network,

  /// A 200 response whose body did not match the documented contract.
  malformedResponse,
}

/// Typed outcome of a research request: tips on success, a [ResearchFailureKind]
/// on failure. The service never throws into the UI — it mirrors
/// `InferenceService` returning instead of throwing, but preserves the cause so
/// the UI can tell an error apart from offline or an abstention.
sealed class ResearchResult {
  const ResearchResult();
}

/// A successful fetch. [tips] may itself be grounded or abstained — that is a
/// valid result, not a failure.
class ResearchSuccess extends ResearchResult {
  const ResearchSuccess(this.tips);

  final ManagementTipsResult tips;
}

/// A failed fetch, with the cause and the HTTP status code when one applies.
class ResearchFailure extends ResearchResult {
  const ResearchFailure(this.kind, {this.statusCode});

  final ResearchFailureKind kind;

  /// The HTTP status code when the failure came from a response, else null.
  final int? statusCode;
}

/// Fetches advisory Management Tips ("dicas de manejo") for a Soil Record from
/// the backend proxy. The abstract seam mirrors `AuthService` so providers and
/// tests can substitute a fake.
abstract class ResearchService {
  /// Requests cited tips for [record]. [locale] selects the response language
  /// (defaults to `pt-BR` when null). Returns a typed [ResearchResult]; never
  /// throws into the caller.
  Future<ResearchResult> fetchTips(SoilRecord record, {String? locale});
}
