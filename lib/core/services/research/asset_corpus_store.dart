import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart' show rootBundle;
import 'package:visiosoil_app/core/services/research/corpus_composer.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';

/// Loads an asset by key, or returns null when the bundle does not carry it.
///
/// Injected so tests drive a map of bytes instead of the real bundle, mirroring
/// `InferenceService`'s injected `ModelAssetLoader`. It also makes the
/// distinction this store rests on explicit: **returning null is "the bundle
/// does not have it"**, and anything else is a failure worth reporting.
typedef AssetLoader = Future<Uint8List?> Function(String key);

/// The production [AssetLoader]: the app's own bundle.
///
/// The only error it narrows away is "the bundle has no such key", which is the
/// absent case this design treats as normal. Anything else propagates, because a
/// bundle that fails for another reason is not an absent asset.
Future<Uint8List?> loadAssetFromRootBundle(String key) async {
  try {
    final data = await rootBundle.load(key);
    return data.buffer.asUint8List();
  } on FlutterError {
    return null;
  }
}

/// The [CorpusStore] backed by the corpus bundled with the app.
///
/// Reads `assets/corpus/corpus.json` once and caches the parsed [Corpus] for the
/// process. Loading is asynchronous and happens at first use rather than at
/// launch: a file read and a JSON parse are not owed by a session that never
/// opens the feature. It runs on the main isolate, so the `rootBundle`
/// restriction that shapes `InferenceService` does not apply.
///
/// **A missing asset and a malformed one are different states.** Until the
/// corpus build ships content there is nothing to bundle, and the app answers
/// that there is no coverage — the state the composition rule already defines.
/// But an asset that is present and does not parse is a build defect: it throws,
/// with the asset named, because swallowing it would ship guidance-shaped
/// silence that nobody would learn about.
class AssetCorpusStore implements CorpusStore {
  AssetCorpusStore({AssetLoader? loadAsset})
      : _loadAsset = loadAsset ?? loadAssetFromRootBundle;

  /// Where a corpus release is bundled.
  static const String corpusAssetKey = 'assets/corpus/corpus.json';

  final AssetLoader _loadAsset;

  Future<Corpus?>? _pending;

  @override
  Future<Corpus?> current() => _pending ??= _read();

  Future<Corpus?> _read() async {
    final bytes = await _loadAsset(corpusAssetKey);
    if (bytes == null) return null;

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } on Object catch (error) {
      throw FormatException('$corpusAssetKey is not a JSON object: $error');
    }

    final builtAt = json['builtAt'] as String?;
    final fetchedAt = builtAt == null ? null : DateTime.tryParse(builtAt);
    if (fetchedAt == null) {
      // A bundled artifact with no build time has no honest `retrievedAt`, and
      // substituting the load time would claim a freshness it does not have.
      throw FormatException(
        '$corpusAssetKey has no usable builtAt; a bundled corpus must say when '
        'it was built',
      );
    }

    try {
      return Corpus.fromJson(json, fetchedAt: fetchedAt);
    } on FormatException catch (error) {
      // Re-thrown with the asset named: the corpus parser reports which field is
      // wrong, and the reader needs to know which artifact carried it.
      throw FormatException('$corpusAssetKey is not a valid corpus: '
          '${error.message}');
    }
  }
}
