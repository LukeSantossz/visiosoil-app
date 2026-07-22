import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../../support/management_tips_fakes.dart';

/// Records the include-location choice the share flow forwards to the service.
class _RecordingShareService extends ShareService {
  bool? calledIncludeLocation;

  @override
  Future<void> shareRecord(
    SoilRecord record, {
    bool includeLocation = false,
  }) async {
    calledIncludeLocation = includeLocation;
  }
}

SoilRecord _locatedRecord() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      latitude: -23.5,
      longitude: -46.6,
      address: 'São Paulo, SP',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

SoilRecord _unlocatedRecord() => SoilRecord(
      id: 1,
      imagePath: 'x.png',
      timestamp: '2026-06-26T12:00:00Z',
      textureClass: 'Argilosa',
      confidenceScore: 0.9,
    );

Widget _detailsUnderTest({
  required ShareService share,
  required SoilRecord record,
}) {
  return ProviderScope(
    overrides: [
      soilRecordByIdProvider.overrideWith((ref, id) async => record),
      shareServiceProvider.overrideWithValue(share),
      managementTipsRepositoryProvider
          .overrideWithValue(FakeManagementTipsRepository()),
      researchServiceProvider.overrideWithValue(
        FakeResearchService(
          (_) async =>
              const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
        ),
      ),
      connectivityServiceProvider
          .overrideWithValue(FakeConnectivityService(ConnectivityStatus.online)),
    ],
    child: const MaterialApp(home: DetailsScreen(recordId: 1)),
  );
}

void main() {
  testWidgets('tips section sits between the info section and the actions',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => tipsRecord()),
        managementTipsRepositoryProvider
            .overrideWithValue(FakeManagementTipsRepository()),
        researchServiceProvider.overrideWithValue(
          FakeResearchService(
            (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
          ),
        ),
        connectivityServiceProvider
            .overrideWithValue(FakeConnectivityService(ConnectivityStatus.online)),
      ],
      child: const MaterialApp(home: DetailsScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    final infoDy = tester.getTopLeft(find.text('Localização')).dy;
    final tipsDy = tester.getTopLeft(find.text('Dicas de manejo')).dy;
    final actionsDy = tester.getTopLeft(find.text('Compartilhar')).dy;

    expect(infoDy < tipsDy, isTrue);
    expect(tipsDy < actionsDy, isTrue);
  });

  testWidgets('sharing a located record omits location by default',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    // The opt-in dialog appears; its default action shares without location.
    expect(find.text('Compartilhar sem localização'), findsOneWidget);
    await tester.tap(find.text('Compartilhar sem localização'));
    await tester.pumpAndSettle();

    expect(share.calledIncludeLocation, isFalse);
  });

  testWidgets('choosing to include location forwards the opt-in',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _locatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Incluir localização'));
    await tester.pumpAndSettle();

    expect(share.calledIncludeLocation, isTrue);
  });

  testWidgets('a record with no location shares without a dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();

    await tester.pumpWidget(
      _detailsUnderTest(share: share, record: _unlocatedRecord()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compartilhar'));
    await tester.pumpAndSettle();

    expect(find.text('Incluir localização?'), findsNothing);
    expect(share.calledIncludeLocation, isFalse);
  });
}
