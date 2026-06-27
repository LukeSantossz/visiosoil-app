import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/services/research/unavailable_research_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';

void main() {
  test('default researchServiceProvider reports upstreamUnavailable with no call',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final service = container.read(researchServiceProvider);
    expect(service, isA<UnavailableResearchService>());

    final result = await service.fetchTips(
      const SoilRecord(
        id: 1,
        uuid: 'rec-1',
        imagePath: 'x.png',
        timestamp: '2026-06-26T12:00:00Z',
        textureClass: 'Argilosa',
        confidenceScore: 0.9,
      ),
    );

    expect(result, isA<ResearchFailure>());
    expect((result as ResearchFailure).kind,
        ResearchFailureKind.upstreamUnavailable);
  });
}
