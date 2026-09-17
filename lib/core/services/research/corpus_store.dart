import 'package:visiosoil_app/core/services/research/corpus_composer.dart';

/// Holds the corpus the app composes from.
///
/// The seam exists because where a corpus comes from changes and what composes
/// from it does not: today nothing holds one, slice A4 adds the bundled asset
/// and the fetched release, and version comparison between them belongs here
/// rather than in the service (`docs/architecture/research-agent.md` §19.3).
abstract class CorpusStore {
  /// The corpus currently held, or null when none is.
  ///
  /// Null is a normal answer, not an error. Until a reviewed corpus ships there
  /// is nothing to hold, and the app says there is no coverage rather than
  /// reporting a service it never called as unavailable.
  Future<Corpus?> current();
}

/// Holds nothing.
///
/// The v1 binding until slice A4 ships `assets/corpus/`. It exists so the whole
/// Tier 1 path is wired and exercised on a real device from the first slice,
/// instead of waiting for content to prove the wiring works.
class AbsentCorpusStore implements CorpusStore {
  const AbsentCorpusStore();

  @override
  Future<Corpus?> current() async => null;
}
