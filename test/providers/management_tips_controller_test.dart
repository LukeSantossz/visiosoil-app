import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/core/services/research/corpus_store.dart';
import 'package:visiosoil_app/core/services/research/management_tips_controller.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/site_key.dart';
import '../support/management_tips_fakes.dart';

ManagementTipsController build({
  required FakeManagementTipsRepository repo,
  required FakeResearchService service,
  SiteResolver? resolver,
  CorpusStore? corpusStore,
}) =>
    ManagementTipsController(
      researchService: service,
      repository: repo,
      siteResolver:
          resolver ?? FakeSiteResolver(const SiteKey(unit: 'BR-SP')),
      corpusStore: corpusStore ?? HeldCorpusStore(null),
    );

void main() {
  test('no_corpus_result_is_not_upserted', () async {
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService(
      (_) async => ResearchSuccess(noCorpusTips()),
    );
    final controller = build(repo: repo, service: service);

    final failure = await controller.generate(tipsRecord());

    // Compare the public enum name so RED needs no production enum change.
    expect(failure?.name, 'corpusUnavailable');
    expect(service.calls, 1);
    expect(repo.upsertCount, 0);
    expect(await repo.getByRecordUuid('rec-1'), isNull);
  });

  test('generate success persists tips and returns null', () async {
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final controller = build(repo: repo, service: service);

    final failure = await controller.generate(tipsRecord());

    expect(failure, isNull);
    expect(service.calls, 1);
    expect(repo.upsertCount, 1);
    expect(await repo.getByRecordUuid('rec-1'), isNotNull);
  });

  test('offline_device_still_receives_tips', () async {
    // The connectivity gate was correct while every result came from a proxy.
    // Tier 1 composes on the device, so being offline is not a reason to
    // refuse: the gate belongs to corpus *fetch*, where offline genuinely means
    // "cannot refresh" (SPEC 0068, ADR 0022 §6.5).
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final controller = build(repo: repo, service: service);

    final failure = await controller.generate(tipsRecord());

    expect(failure, isNull);
    expect(service.calls, 1);
    expect(repo.upsertCount, 1);
  });

  test('generate failure returns the kind and leaves the cache untouched',
      () async {
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.rateLimited));
    final controller = build(repo: repo, service: service);

    final failure = await controller.generate(tipsRecord());

    expect(failure, ResearchFailureKind.rateLimited);
    expect(repo.upsertCount, 0);
  });

  test('invalid_record_still_fails_fast', () async {
    // Removing the connectivity gate does not remove the validity gate: a
    // record with no uuid or no class still cannot produce a key.
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final resolver = FakeSiteResolver(const SiteKey.unresolved());
    final controller =
        build(repo: repo, service: service, resolver: resolver);

    final failure = await controller.generate(tipsRecord(textureClass: null));

    expect(failure, ResearchFailureKind.invalidRecord);
    expect(service.calls, 0);
    expect(resolver.calls, 0);
    expect(repo.upsertCount, 0);
  });

  group('the controller resolves, the service does not', () {
    test('resolver_is_given_what_the_record_holds', () async {
      final repo = FakeManagementTipsRepository();
      final service =
          FakeResearchService((_) async => ResearchSuccess(groundedTips()));
      final resolver = FakeSiteResolver(const SiteKey(unit: 'BR-SP'));
      final controller =
          build(repo: repo, service: service, resolver: resolver);

      await controller.generate(tipsRecord(
        latitude: -22.9,
        longitude: -47.05,
        address: 'Rua X, Campinas, São Paulo',
      ));

      expect(resolver.calls, 1);
      expect(resolver.lastLatitude, -22.9);
      expect(resolver.lastLongitude, -47.05);
      expect(resolver.lastAddress, 'Rua X, Campinas, São Paulo');
    });

    test('resolved_key_and_land_use_reach_the_service', () async {
      final repo = FakeManagementTipsRepository();
      final service =
          FakeResearchService((_) async => ResearchSuccess(groundedTips()));
      const key = SiteKey(
        clayActivity: ClayActivity.tbOxidic,
        unit: 'BR-SP',
        biome: Biome.cerrado,
      );
      final controller = build(
        repo: repo,
        service: service,
        resolver: FakeSiteResolver(key),
      );

      await controller.generate(tipsRecord(), landUse: LandUse.pasture);

      expect(service.lastSite, key);
      expect(service.lastLandUse, LandUse.pasture);
    });

    test('a_declined_land_use_is_null_not_a_default', () async {
      final repo = FakeManagementTipsRepository();
      final service =
          FakeResearchService((_) async => ResearchSuccess(groundedTips()));
      final controller = build(repo: repo, service: service);

      await controller.generate(tipsRecord());

      expect(service.lastLandUse, isNull);
    });
  });

  group('isStale (SPEC 0269)', () {
    FakeResearchService unused() =>
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));

    test('stale_when_another_release_answered', () async {
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', groundedTips(corpusVersion: 'v1'));
      final controller = build(
        repo: repo,
        service: unused(),
        corpusStore: HeldCorpusStore(corpusAt('v2')),
      );

      expect(await controller.isStale(tipsRecord()), isTrue);
    });

    test('fresh_when_the_same_release_answered', () async {
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', groundedTips(corpusVersion: 'v2'));
      final controller = build(
        repo: repo,
        service: unused(),
        corpusStore: HeldCorpusStore(corpusAt('v2')),
      );

      expect(await controller.isStale(tipsRecord()), isFalse);
    });

    test('not_stale_without_a_cached_row', () async {
      final controller = build(
        repo: FakeManagementTipsRepository(),
        service: unused(),
        corpusStore: HeldCorpusStore(corpusAt('v2')),
      );

      expect(await controller.isStale(tipsRecord()), isFalse);
    });

    test('not_stale_without_a_held_corpus', () async {
      final repo = FakeManagementTipsRepository()
        ..seed('rec-1', groundedTips());
      final controller = build(
        repo: repo,
        service: unused(),
        corpusStore: HeldCorpusStore(null),
      );

      expect(await controller.isStale(tipsRecord()), isFalse);
    });
  });
}
