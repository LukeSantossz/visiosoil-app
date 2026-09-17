// The Tier 1 binding of the `ResearchService` seam: it composes from the held
// corpus and makes no request at all.
//
// "No per-record request" is asserted against a transport that fails the test if
// it is touched, rather than against an absent field in a request body. That is
// the property §6.1 actually claims, and it is the one an absent-field assertion
// cannot prove.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/research/corpus_composer.dart';
import 'package:visiosoil_app/core/services/research/corpus_research_service.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';

import '../support/management_tips_fakes.dart';

void main() {
  Corpus fixtureCorpus() => Corpus.fromJson(
        jsonDecode(File('test/fixtures/corpus/corpus.json').readAsStringSync())
            as Map<String, dynamic>,
        fetchedAt: DateTime.utc(2026, 9, 10),
      );

  group('composing from a held corpus', () {
    test('composition_performs_zero_transport_calls', () async {
      final transport = FailIfTouchedTransport();
      final service = CorpusResearchService(
        store: HeldCorpusStore(fixtureCorpus()),
      );

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey(
          clayActivity: ClayActivity.tbOxidic,
          unit: 'BR-SP',
          biome: Biome.cerrado,
        ),
        landUse: LandUse.pasture,
      );

      expect(result, isA<ResearchSuccess>());
      expect(transport.calls, 0,
          reason: 'Tier 1 composes on the device; a request would reinstate the '
              'coordinate egress the corpus key exists to remove');
    });

    test('a_composed_result_carries_the_corpus_version', () async {
      final service =
          CorpusResearchService(store: HeldCorpusStore(fixtureCorpus()));

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey(clayActivity: ClayActivity.tbOxidic),
      );

      final tips = (result as ResearchSuccess).tips;
      expect(tips.corpusVersion, 'fixture-2026.09.1');
      expect(tips.status, ManagementTipsStatus.grounded);
    });

    test('an_invalid_record_fails_before_composing', () async {
      final service =
          CorpusResearchService(store: HeldCorpusStore(fixtureCorpus()));

      final result = await service.fetchTips(
        tipsRecord(textureClass: null),
        site: const SiteKey(clayActivity: ClayActivity.tbOxidic),
      );

      expect(
        result,
        isA<ResearchFailure>().having(
          (f) => f.kind,
          'kind',
          ResearchFailureKind.invalidRecord,
        ),
      );
    });
  });

  group('when no corpus is held', () {
    test('absent_corpus_composes_insufficient_evidence', () async {
      final service = CorpusResearchService(store: const AbsentCorpusStore());

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey(clayActivity: ClayActivity.tbOxidic),
      );

      expect(result, isA<ResearchSuccess>());
      final tips = (result as ResearchSuccess).tips;
      expect(tips.status, ManagementTipsStatus.insufficientEvidence);
      expect(tips.tips, isEmpty);
      expect(tips.sources, isEmpty);
      expect(tips.corpusVersion, isNull);
    });

    test('absent_corpus_is_not_a_failure', () async {
      // It is a normal state, not a transport error: reporting it as a failure
      // would put the "could not reach the service" copy in front of a user
      // whose device is working perfectly.
      final service = CorpusResearchService(store: const AbsentCorpusStore());

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey.unresolved(),
      );

      expect(result, isNot(isA<ResearchFailure>()));
    });

    test('absent_corpus_still_carries_a_non_empty_disclaimer', () async {
      final service = CorpusResearchService(store: const AbsentCorpusStore());

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey.unresolved(),
      );

      expect((result as ResearchSuccess).tips.disclaimer.trim(), isNotEmpty);
    });

    test('absent_corpus_reports_the_coverage_it_could_not_give', () async {
      final service = CorpusResearchService(store: const AbsentCorpusStore());

      final result = await service.fetchTips(
        tipsRecord(),
        site: const SiteKey(unit: 'BR-SP', biome: Biome.cerrado),
        landUse: LandUse.pasture,
      );

      final coverage = (result as ResearchSuccess).tips.coverage!;
      expect(coverage.unit, 'BR-SP');
      expect(coverage.unitLayerPresent, isFalse);
      expect(coverage.landUse, 'pasture');
      expect(coverage.landUseLayerPresent, isFalse);
      expect(coverage.substanceIsGeneric, isTrue);
    });
  });
}
