import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';

/// The corpus the app composes from.
///
/// Bound to [AbsentCorpusStore] until slice A4 ships `assets/corpus/` and the
/// release fetch. Holding nothing is a normal state: the app answers that there
/// is no coverage rather than reporting a service it never called as
/// unavailable.
final corpusStoreProvider = Provider<CorpusStore>((ref) {
  return const AbsentCorpusStore();
});
