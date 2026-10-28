// The released corpus, read the way the app reads it (SPEC 0227).
//
// The Python release checks the cells against its own copy of the contract;
// this reads the file the APK carries through `AssetCorpusStore` and composes
// every substance key, so a release the app cannot read fails here rather than
// on a device.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/research/asset_corpus_store.dart';
import 'package:visiosoil_app/core/services/research/corpus_composer.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';

void main() {
  final released = File(AssetCorpusStore.corpusAssetKey);

  // The classes the model emits, as the released classifier lists them.
  final classes = [
    for (final name in (jsonDecode(
      File('assets/models/spec.json').readAsStringSync(),
    ) as Map<String, dynamic>)['classes'] as List<dynamic>)
      name as String,
  ];

  Future<Corpus> load() async {
    final store = AssetCorpusStore(
      loadAsset: (key) async =>
          key == AssetCorpusStore.corpusAssetKey
              ? Uint8List.fromList(released.readAsBytesSync())
              : null,
    );
    final corpus = await store.current();
    expect(corpus, isNotNull);
    return corpus!;
  }

  test('the_released_corpus_parses', () async {
    final corpus = await load();

    expect(corpus.corpusVersion, isNotEmpty);
    expect(corpus.disclaimer.trim(), isNotEmpty);
  });

  test('it_holds_every_substance_key', () async {
    final corpus = await load();

    expect(corpus.substance.keys.toSet(), {
      for (final textureClass in classes)
        for (final activity in ClayActivity.values)
          Corpus.substanceKey(textureClass, activity),
    });
    for (final cell in corpus.substance.values) {
      expect(cell.disclaimer?.trim(), isNotEmpty);
    }
  });

  test('every_biome_has_a_default_family', () async {
    final corpus = await load();

    expect(
      corpus.clayActivityDefaultByBiome.keys.toSet(),
      {for (final biome in Biome.values) biome.wireName},
    );
  });

  test('every_substance_key_composes_to_its_cell', () async {
    final corpus = await load();

    for (final textureClass in classes) {
      for (final activity in ClayActivity.values) {
        final result = const CorpusComposer().compose(
          corpus: corpus,
          textureClass: textureClass,
          site: SiteKey(clayActivity: activity),
          landUse: null,
        );
        final cell =
            corpus.substance[Corpus.substanceKey(textureClass, activity)]!;

        expect(result.status, cell.status, reason: '$textureClass $activity');
        expect(result.status, isNot(ManagementTipsStatus.insufficientEvidence));
        expect(result.coverage?.substanceIsGeneric, isFalse);
      }
    }
  });

  test('a_biome_alone_reaches_a_substance_cell', () async {
    final corpus = await load();

    for (final biome in Biome.values) {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: classes.first,
        site: SiteKey(biome: biome),
        landUse: null,
      );

      expect(result.coverage?.clayActivityAssumed, isTrue, reason: '$biome');
      expect(result.coverage?.substanceIsGeneric, isFalse);
    }
  });
}
