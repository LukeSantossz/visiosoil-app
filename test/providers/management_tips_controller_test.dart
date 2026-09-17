import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/region/site_resolver.dart';
import 'package:visiosoil_app/core/services/research/management_tips_controller.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/land_use.dart';
import 'package:visiosoil_app/models/site_key.dart';
import '../support/management_tips_fakes.dart';

/// Returns a fixed key and records what it was asked to resolve.
class FakeSiteResolver implements SiteResolver {
  FakeSiteResolver(this.key);

  final SiteKey key;
  int calls = 0;
  double? lastLatitude;
  double? lastLongitude;
  String? lastAddress;

  @override
  Future<SiteKey> resolve({
    double? latitude,
    double? longitude,
    String? address,
  }) async {
    calls++;
    lastLatitude = latitude;
    lastLongitude = longitude;
    lastAddress = address;
    return key;
  }
}

ManagementTipsController build({
  required FakeManagementTipsRepository repo,
  required FakeResearchService service,
  SiteResolver? resolver,
}) =>
    ManagementTipsController(
      researchService: service,
      repository: repo,
      siteResolver:
          resolver ?? FakeSiteResolver(const SiteKey(unit: 'BR-SP')),
    );

void main() {
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
}
