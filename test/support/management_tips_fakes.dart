import 'package:visiosoil_app/core/data/repositories/management_tips_repository.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/management_tips_result.dart';
import 'package:visiosoil_app/models/soil_record.dart';

/// In-memory [ManagementTipsRepository] for tests.
class FakeManagementTipsRepository implements ManagementTipsRepository {
  final Map<String, ManagementTipsResult> store = {};
  int upsertCount = 0;

  void seed(String uuid, ManagementTipsResult result) => store[uuid] = result;

  @override
  Future<ManagementTipsResult?> getByRecordUuid(String recordUuid) async =>
      store[recordUuid];

  @override
  Future<void> upsert(String recordUuid, ManagementTipsResult result) async {
    upsertCount++;
    store[recordUuid] = result;
  }

  @override
  Future<void> deleteByRecordUuid(String recordUuid) async =>
      store.remove(recordUuid);
}

/// Scripted [ResearchService]; the handler decides the outcome per call.
class FakeResearchService implements ResearchService {
  FakeResearchService(this.handler);

  final Future<ResearchResult> Function(SoilRecord record) handler;
  int calls = 0;

  @override
  Future<ResearchResult> fetchTips(SoilRecord record, {String? locale}) {
    calls++;
    return handler(record);
  }
}

/// Fixed-status [ConnectivityService] for tests.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService(this.status);

  final ConnectivityStatus status;

  @override
  Future<ConnectivityStatus> current() async => status;

  @override
  Stream<ConnectivityStatus> watch() => Stream.value(status);
}

/// Builds a grounded result for tests.
ManagementTipsResult groundedTips() => ManagementTipsResult(
      status: ManagementTipsStatus.grounded,
      tips: const [
        ManagementTip(
          text: 'Mantenha cobertura vegetal no solo.',
          citations: [0],
        ),
      ],
      sources: const [
        TipSource(
          title: 'Embrapa Solos',
          url: 'https://embrapa.br',
          publisher: 'Embrapa',
        ),
      ],
      disclaimer: 'Conteudo consultivo.',
      model: 'llama-3.3-70b',
      retrievedAt: DateTime.utc(2026, 6, 26, 12),
    );

/// A test Soil Record; pass `textureClass: null` for the unclassified case.
SoilRecord tipsRecord({
  String? uuid = 'rec-1',
  String? textureClass = 'Argilosa',
}) =>
    SoilRecord(
      id: 1,
      uuid: uuid,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: textureClass,
      confidenceScore: 0.9,
    );

/// Builders for non-grounded results.
class ManagementTipsResultBuilder {
  const ManagementTipsResultBuilder._();

  static ManagementTipsResult abstained() => ManagementTipsResult(
        status: ManagementTipsStatus.abstained,
        tips: const [],
        sources: const [],
        disclaimer: 'Conteudo consultivo.',
        model: 'llama-3.3-70b',
        retrievedAt: DateTime.utc(2026, 6, 26, 12),
      );
}
