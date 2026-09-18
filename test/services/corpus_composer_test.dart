// The composition rule of research-agent.md §6.5, pinned by the golden fixture.
//
// The rule is subtle in exactly one spot — citations are indices into their own
// layer's source array and must be re-indexed when the arrays are concatenated —
// and a subtle rule that lives only in code is a rule nobody can review. The
// golden is hand-written for the same reason: one captured from the
// implementation would prove the code is stable, not that it is right.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/research/corpus_composer.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';

void main() {
  final fetchedAt = DateTime.utc(2026, 9, 10);

  Corpus loadFixture() => Corpus.fromJson(
        jsonDecode(File('test/fixtures/corpus/corpus.json').readAsStringSync())
            as Map<String, dynamic>,
        fetchedAt: fetchedAt,
      );

  Map<String, dynamic> loadGolden() =>
      jsonDecode(File('test/fixtures/corpus/golden.json').readAsStringSync())
          as Map<String, dynamic>;

  group('golden fixture', () {
    final corpus = loadFixture();
    final cases = (loadGolden()['cases'] as List).cast<Map<String, dynamic>>();

    test('golden_covers_every_shape_the_rule_distinguishes', () {
      expect(
        cases.map((c) => c['name']),
        containsAll(const [
          'all_layers_present',
          'substance_only_every_overlay_absent',
          'substance_abstains_alone',
          'generic_substance_from_the_biome_default',
          'nothing_resolved_is_the_empty_composition',
        ]),
      );
    });

    for (final golden in cases) {
      final name = golden['name'] as String;
      final input = golden['input'] as Map<String, dynamic>;

      test('golden_$name', () {
        final result = const CorpusComposer().compose(
          corpus: corpus,
          textureClass: input['textureClass'] as String,
          site: SiteKey(
            clayActivity: ClayActivity.fromWire(input['clayActivity'] as String?),
            unit: input['unit'] as String?,
            biome: Biome.fromWire(input['biome'] as String?),
          ),
          landUse: LandUse.fromWire(input['landUse'] as String?),
        );

        expect(result.toJson(), golden['expected']);
      });
    }
  });

  group('the parts of the rule that deserve to fail by name', () {
    final corpus = loadFixture();

    ({int tipIndex, List<int> citations}) citationsOf(String text) {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Argilosa',
        site: const SiteKey(
          clayActivity: ClayActivity.tbOxidic,
          unit: 'BR-SP',
          biome: Biome.cerrado,
        ),
        landUse: LandUse.pasture,
      );
      final index = result.tips.indexWhere((t) => t.text.contains(text));
      return (tipIndex: index, citations: result.tips[index].citations);
    }

    test('citations_are_reindexed_across_layers', () {
      // The unit layer's sources start at offset 3, and its tip cites its own
      // indices 1 and 0 — so the composed citation is [4, 3], in that order.
      expect(citationsOf('extensão rural').citations, [4, 3]);
      // The land-use layer starts at offset 2 and cites its own index 0.
      expect(citationsOf('compactação').citations, [2]);
      // The substance layer starts at 0, so its citations are unchanged.
      expect(citationsOf('não implica alta CTC').citations, [0]);
    });

    test('duplicate_sources_are_not_merged', () {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Argilosa',
        site: const SiteKey(
          clayActivity: ClayActivity.tbOxidic,
          unit: 'BR-SP',
          biome: Biome.cerrado,
        ),
        landUse: LandUse.pasture,
      );

      final shared = result.sources
          .where((s) => s.url == 'https://example.org/compartilhada')
          .toList();

      expect(shared, hasLength(2),
          reason: 'merging would re-index across layers and add a second place '
              'an index can be wrong, to save a repeated line');
      expect(result.sources.indexOf(shared.first), 1);
      expect(result.sources.indexOf(shared.last), 3);
    });

    test('layer_order_is_fixed', () {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Argilosa',
        site: const SiteKey(
          clayActivity: ClayActivity.tbOxidic,
          unit: 'BR-SP',
          biome: Biome.cerrado,
        ),
        landUse: LandUse.pasture,
      );

      expect(result.tips, hasLength(5));
      expect(result.tips[0].text, contains('alta CTC'));
      expect(result.tips[1].text, contains('fósforo'));
      expect(result.tips[2].text, contains('pastagem'));
      expect(result.tips[3].text, contains('extensão'));
      expect(result.tips[4].text, contains('Embrapa'));
    });

    test('limitations_are_deduplicated_by_exact_string', () {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Argilosa',
        site: const SiteKey(clayActivity: ClayActivity.tbOxidic),
        landUse: LandUse.pasture,
      );

      final laboratorial = result.limitations
          .where((l) => l.contains('análise laboratorial'))
          .toList();

      expect(laboratorial, hasLength(1));
    });

    test('empty_composition_still_carries_a_non_empty_disclaimer', () {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Argilosa',
        site: const SiteKey.unresolved(),
        landUse: null,
      );

      expect(result.status, ManagementTipsStatus.insufficientEvidence);
      expect(result.tips, isEmpty);
      expect(result.disclaimer.trim(), isNotEmpty);
    });

    test('composer_is_pure', () {
      const composer = CorpusComposer();
      Map<String, dynamic> run() => composer
          .compose(
            corpus: corpus,
            textureClass: 'Argilosa',
            site: const SiteKey(
              clayActivity: ClayActivity.tbOxidic,
              unit: 'BR-SP',
              biome: Biome.cerrado,
            ),
            landUse: LandUse.pasture,
          )
          .toJson();

      expect(run(), run());
      // retrievedAt is the corpus's, not the clock's.
      expect(run()['retrievedAt'], '2026-09-10T00:00:00.000Z');
    });

    test('an_unknown_class_is_insufficient_evidence_not_a_crash', () {
      final result = const CorpusComposer().compose(
        corpus: corpus,
        textureClass: 'Siltosa',
        site: const SiteKey(clayActivity: ClayActivity.tbOxidic),
        landUse: null,
      );

      expect(result.tips, isEmpty);
      expect(result.disclaimer.trim(), isNotEmpty);
    });
  });

  group('corpus parsing', () {
    test('a_corpus_without_optional_sections_parses', () {
      final corpus = Corpus.fromJson(
        {
          'corpusVersion': 'bare',
          'disclaimer': 'x',
          'substance': <String, dynamic>{},
        },
        fetchedAt: fetchedAt,
      );

      expect(corpus.corpusVersion, 'bare');
      expect(corpus.landUse, isEmpty);
      expect(corpus.unit, isEmpty);
      expect(corpus.biome, isEmpty);
      expect(corpus.clayActivityDefaultByBiome, isEmpty);
    });

    test('an_empty_corpus_disclaimer_is_refused_by_name', () {
      // The result contract says the disclaimer is never empty, and the composer
      // falls back to the corpus's own when no substance cell carries one. An
      // empty value there would produce a result that violates the contract
      // silently, so it is refused where it enters rather than where it shows.
      for (final value in const ['', '   ']) {
        expect(
          () => Corpus.fromJson(
            {
              'corpusVersion': 'bad',
              'disclaimer': value,
              'substance': <String, dynamic>{},
            },
            fetchedAt: fetchedAt,
          ),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('disclaimer'),
          )),
          reason: 'a disclaimer of ${value.isEmpty ? 'empty' : 'blanks'} must '
              'not reach a composed result',
        );
      }
    });

    test('a_cell_without_a_status_is_refused_by_name', () {
      // The build refuses a generation that omits `status` for this exact
      // reason: a default turned malformed output into a grounded cell carrying
      // no guidance. The device reader kept the default, so the same malformed
      // cell composed as grounded once it was in a corpus file.
      expect(
        () => Corpus.fromJson(
          {
            'corpusVersion': 'bad',
            'disclaimer': 'x',
            'substance': {
              'Argilosa|tb_oxidic': {
                'tips': <dynamic>[],
                'sources': <dynamic>[],
              },
            },
          },
          fetchedAt: fetchedAt,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('status'), contains('Argilosa|tb_oxidic')),
        )),
      );
    });

    test('a_citation_outside_its_layer_is_refused_by_name', () {
      // §12.1 makes an unresolvable citation a build failure, so composition may
      // assume resolvable input. A corpus that reaches a device with one anyway
      // must say so rather than compose a citation that points nowhere.
      expect(
        () => Corpus.fromJson(
          {
            'corpusVersion': 'bad',
            'disclaimer': 'x',
            'substance': {
              'Argilosa|tb_oxidic': {
                'status': 'grounded',
                'tips': [
                  {'text': 't', 'citations': [3]},
                ],
                'sources': [
                  {'title': 'a', 'url': 'https://example.org/a'},
                ],
              },
            },
          },
          fetchedAt: fetchedAt,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('citation'),
        )),
      );
    });
  });
}
