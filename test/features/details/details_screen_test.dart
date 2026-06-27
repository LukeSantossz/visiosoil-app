import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/details.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../../support/management_tips_fakes.dart';

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
      child: const MaterialApp(home: DetailsPage(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    final infoDy = tester.getTopLeft(find.text('Localização')).dy;
    final tipsDy = tester.getTopLeft(find.text('Dicas de manejo')).dy;
    final actionsDy = tester.getTopLeft(find.text('Compartilhar')).dy;

    expect(infoDy < tipsDy, isTrue);
    expect(tipsDy < actionsDy, isTrue);
  });
}
