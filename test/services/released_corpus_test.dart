// The released corpus, read the way the app reads it (SPEC 0227).
//
// The Python release checks the cells against its own copy of the contract;
// this reads the file the APK carries through `AssetCorpusStore` and composes
// every class and family, so a release the app cannot read fails here rather than
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

  // Every class has a generic cell, and every other cell is one family of a
  // known class: a family is refined only where its own sources exist
  // (SPEC 0234).
  test('it_holds_every_generic_key', () async {
    final corpus = await load();

    final generic = {for (final c in classes) Corpus.genericKey(c)};
    final families = {
      for (final c in classes)
        for (final activity in ClayActivity.values)
          Corpus.substanceKey(c, activity),
    };
    expect(corpus.substance.keys.toSet().containsAll(generic), isTrue);
    expect(
      corpus.substance.keys.toSet().difference(generic).difference(families),
      isEmpty,
    );
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

  test('every_class_and_family_composes', () async {
    final corpus = await load();

    for (final textureClass in classes) {
      for (final activity in [...ClayActivity.values, null]) {
        final result = const CorpusComposer().compose(
          corpus: corpus,
          textureClass: textureClass,
          site: SiteKey(clayActivity: activity),
          landUse: null,
        );
        final family = activity == null
            ? null
            : corpus.substance[Corpus.substanceKey(textureClass, activity)];
        final used = family != null && family.tips.isNotEmpty
            ? family
            : corpus.substance[Corpus.genericKey(textureClass)]!;

        expect(result.status, used.status, reason: '$textureClass $activity');
        expect(result.status, isNot(ManagementTipsStatus.insufficientEvidence));
        expect(
          result.coverage?.substanceIsGeneric,
          !identical(used, family),
          reason: '$textureClass $activity',
        );
      }
    }
  });

  // QA on PR #473 rejected these class-denying claims (SPEC 0260).
  const qaRejectedSubstrings = [
    'A textura arenosa do solo não implica em baixa retenção de água',
    'A textura argilosa não significa que o solo é mais propenso a formação de agregados',
  ];

  test('qa_rejected_tip_claims_are_absent', () async {
    final corpus = await load();

    expect(corpus.corpusVersion, '2026.10.31.3');
    for (final cell in corpus.substance.values) {
      for (final tip in cell.tips) {
        for (final rejected in qaRejectedSubstrings) {
          expect(
            tip.text.contains(rejected),
            isFalse,
            reason: 'tip must not contain "$rejected"',
          );
        }
      }
    }
  });

  test('generic_cells_still_grounded_after_drop', () async {
    final corpus = await load();

    final cell = corpus.substance['Arenosa|generic']!;
    expect(cell.status, ManagementTipsStatus.grounded);
    expect(cell.tips.length, greaterThanOrEqualTo(1));
  });

  // Denies a claim instead of advising a practice, and was the last tip of
  // its cell (SPEC 0261).
  test('potassium_denial_tip_is_absent', () async {
    final corpus = await load();

    for (final cell in corpus.substance.values) {
      for (final tip in cell.tips) {
        expect(
          tip.text.contains(
            'potássio não-trocável é predominantemente indisponível',
          ),
          isFalse,
        );
      }
    }
  });

  // The release drops these claims; this checks the file it wrote, compared
  // the way `corpus/src/release.py` compares them (SPEC 0262).
  test('no_released_tip_is_on_the_rejection_list', () async {
    final corpus = await load();
    String normalized(String text) => text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .join(' ');
    final phrases = [
      for (final entry in jsonDecode(
        File('corpus/rejected_tips.json').readAsStringSync(),
      ) as List<dynamic>)
        normalized((entry as Map<String, dynamic>)['phrase'] as String),
    ];

    expect(phrases, isNotEmpty);
    for (final entry in corpus.substance.entries) {
      for (final tip in entry.value.tips) {
        for (final phrase in phrases) {
          expect(
            normalized(tip.text).contains(phrase),
            isFalse,
            reason: '${entry.key} ships the rejected claim "$phrase"',
          );
        }
      }
    }
  });

  // The cell is the abstention `corpus/src/pipeline.py` writes: no tips, the
  // consulted sources kept, and the build's abstention disclaimer (SPEC 0261).
  test('argilosa_generic_abstains', () async {
    final corpus = await load();

    final cell = corpus.substance['Argilosa|generic']!;
    expect(cell.status, ManagementTipsStatus.abstained);
    expect(cell.tips, isEmpty);
    expect(cell.sources, isNotEmpty);
    expect(
      cell.disclaimer,
      'Nenhuma fonte elegível sustentou uma orientação para esta combinação. '
      'Consulte a assistência técnica local.',
    );
  });

  test('a_biome_alone_composes', () async {
    final corpus = await load();

    for (final textureClass in classes) {
      for (final biome in Biome.values) {
        final result = const CorpusComposer().compose(
          corpus: corpus,
          textureClass: textureClass,
          site: SiteKey(biome: biome),
          landUse: null,
        );

        expect(
          result.status,
          isNot(ManagementTipsStatus.insufficientEvidence),
          reason: '$textureClass $biome',
        );
      }
    }
  });
}
