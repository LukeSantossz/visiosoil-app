import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/management_tips_controller.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import '../support/management_tips_fakes.dart';

ManagementTipsController build({
  required FakeManagementTipsRepository repo,
  required FakeResearchService service,
  required ConnectivityStatus connectivity,
}) =>
    ManagementTipsController(
      researchService: service,
      repository: repo,
      connectivity: FakeConnectivityService(connectivity),
    );

void main() {
  test('generate success persists tips and returns null', () async {
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final controller =
        build(repo: repo, service: service, connectivity: ConnectivityStatus.online);

    final failure = await controller.generate(tipsRecord());

    expect(failure, isNull);
    expect(service.calls, 1);
    expect(repo.upsertCount, 1);
    expect(await repo.getByRecordUuid('rec-1'), isNotNull);
  });

  test('generate offline returns network and skips the service', () async {
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final controller =
        build(repo: repo, service: service, connectivity: ConnectivityStatus.offline);

    final failure = await controller.generate(tipsRecord());

    expect(failure, ResearchFailureKind.network);
    expect(service.calls, 0);
    expect(repo.upsertCount, 0);
  });

  test('generate failure returns the kind and leaves the cache untouched',
      () async {
    final repo = FakeManagementTipsRepository();
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.rateLimited));
    final controller =
        build(repo: repo, service: service, connectivity: ConnectivityStatus.online);

    final failure = await controller.generate(tipsRecord());

    expect(failure, ResearchFailureKind.rateLimited);
    expect(repo.upsertCount, 0);
  });

  test('generate on an unclassified record returns invalidRecord without calls',
      () async {
    final repo = FakeManagementTipsRepository();
    final service =
        FakeResearchService((_) async => ResearchSuccess(groundedTips()));
    final controller =
        build(repo: repo, service: service, connectivity: ConnectivityStatus.online);

    final failure = await controller.generate(tipsRecord(textureClass: null));

    expect(failure, ResearchFailureKind.invalidRecord);
    expect(service.calls, 0);
    expect(repo.upsertCount, 0);
  });
}
