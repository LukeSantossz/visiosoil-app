import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visiosoil_app/core/services/research/asset_corpus_store.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';

/// The corpus the app composes from, read from the bundle at first use.
///
/// [AssetCorpusStore] holds nothing while `assets/corpus/` carries no release,
/// which is the state the composition rule already defines: the app answers that
/// there is no coverage. The day the corpus build ships content, it is picked up
/// without an app change.
///
/// A malformed asset is **not** an absent one — it throws, with the asset named.
final corpusStoreProvider = Provider<CorpusStore>((ref) {
  return AssetCorpusStore();
});
