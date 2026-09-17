import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/grid_site_resolver.dart';
import 'package:visiosoil_app/core/services/research/corpus_research_service.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/site_key.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/corpus_store_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/site_resolver_provider.dart';

const _record = SoilRecord(
  id: 1,
  uuid: 'rec-1',
  imagePath: 'x.png',
  timestamp: '2026-06-26T12:00:00Z',
  textureClass: 'Argilosa',
  confidenceScore: 0.9,
);

void main() {
  test('provider_binds_corpus_research_service', () {
    // The moment the feature becomes reachable: it no longer reports a proxy it
    // never called as unavailable.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(
      container.read(researchServiceProvider),
      isA<CorpusResearchService>(),
    );
  });

  test('the_default_binding_answers_without_a_corpus_and_without_a_network',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final result = await container.read(researchServiceProvider).fetchTips(
          _record,
          site: const SiteKey.unresolved(),
        );

    expect(result, isA<ResearchSuccess>());
    final tips = (result as ResearchSuccess).tips;
    expect(tips.status, ManagementTipsStatus.insufficientEvidence);
    expect(tips.disclaimer.trim(), isNotEmpty);
  });

  test('corpus_store_holds_nothing_until_the_asset_slice_lands', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(corpusStoreProvider);
    expect(store, isA<AbsentCorpusStore>());
    expect(await store.current(), isNull);
  });

  test('site_resolver_resolves_the_unit_before_any_grid_ships', () async {
    // The grids are slice A4's; the federative unit comes from the address the
    // app already reverse-geocodes, so it resolves today.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final resolver = container.read(siteResolverProvider);
    expect(resolver, isA<GridSiteResolver>());

    final key = await resolver.resolve(
      latitude: -22.9,
      longitude: -47.05,
      address: 'Rua X, Campinas, São Paulo',
    );

    expect(key.unit, 'BR-SP');
    expect(key.clayActivity, isNull);
    expect(key.biome, isNull);
    expect(key.substanceIsGeneric, isTrue);
  });
}
