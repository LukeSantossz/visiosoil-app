import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/details/management_tips_section.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import '../../support/management_tips_fakes.dart';

Widget harness({
  required SoilRecord record,
  required FakeManagementTipsRepository repo,
  required ResearchService service,
  required ConnectivityStatus connectivity,
}) {
  return ProviderScope(
    overrides: [
      managementTipsRepositoryProvider.overrideWithValue(repo),
      researchServiceProvider.overrideWithValue(service),
      connectivityServiceProvider
          .overrideWithValue(FakeConnectivityService(connectivity)),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ManagementTipsSection(record: record)),
      ),
    ),
  );
}

ResearchService okService() =>
    FakeResearchService((_) async => ResearchSuccess(groundedTips()));

void main() {
  testWidgets('data state renders cards, chips, sources and disclaimer',
      (tester) async {
    final repo = FakeManagementTipsRepository()..seed('rec-1', groundedTips());
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Dicas de manejo'), findsOneWidget);
    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    expect(find.text('[1]'), findsOneWidget);
    expect(find.text('Fontes'), findsOneWidget);
    expect(find.textContaining('consultivo'), findsOneWidget);
    expect(find.text('Atualizar dicas'), findsOneWidget);
    expect(find.textContaining('recomenda'), findsNothing);
  });

  testWidgets('empty cache online shows the generate button', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sem dicas de manejo ainda'), findsOneWidget);
    expect(find.text('Gerar dicas'), findsOneWidget);
  });

  testWidgets('empty cache offline shows offline state and no button',
      (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.offline,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sem conexão'), findsOneWidget);
    expect(find.text('Gerar dicas'), findsNothing);
  });

  testWidgets('unclassified record shows guidance and no button', (tester) async {
    await tester.pumpWidget(harness(
      record: tipsRecord(textureClass: null),
      repo: FakeManagementTipsRepository(),
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Solo não classificado'), findsOneWidget);
    expect(find.text('Gerar dicas'), findsNothing);
  });

  testWidgets('abstained result shows the abstained message and disclaimer',
      (tester) async {
    final repo = FakeManagementTipsRepository()
      ..seed('rec-1', ManagementTipsResultBuilder.abstained());
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: okService(),
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Não encontramos dicas de manejo'), findsOneWidget);
    expect(find.textContaining('consultiv'), findsOneWidget);
  });

  testWidgets('generation shows a loading indicator then the result',
      (tester) async {
    final gate = Completer<ResearchResult>();
    final service = FakeResearchService((_) => gate.future);
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gerar dicas'));
    await tester.pump();
    expect(find.text('Gerando dicas de manejo…'), findsOneWidget);

    gate.complete(ResearchSuccess(groundedTips()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
  });

  testWidgets('first-generation failure shows a mapped message and retry',
      (tester) async {
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable));
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: FakeManagementTipsRepository(),
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Gerar dicas'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Não foi possível gerar as dicas agora'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('a failed refresh keeps the cached tips and shows a snackbar',
      (tester) async {
    final repo = FakeManagementTipsRepository()..seed('rec-1', groundedTips());
    final service = FakeResearchService(
        (_) async => const ResearchFailure(ResearchFailureKind.upstreamUnavailable));
    await tester.pumpWidget(harness(
      record: tipsRecord(),
      repo: repo,
      service: service,
      connectivity: ConnectivityStatus.online,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Atualizar dicas'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Mantenha cobertura vegetal'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
