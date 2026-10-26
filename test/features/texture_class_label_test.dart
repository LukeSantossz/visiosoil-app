import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:visiosoil_app/core/constants/soil_texture_reference.dart';
import 'package:visiosoil_app/core/features/capture/widgets/capture_image_preview.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/services/share_content_builder.dart';
import 'package:visiosoil_app/core/widgets/analysis_tile.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';
import '../support/management_tips_fakes.dart';

// The texture class is shown with its pt-BR accents, while every stored and
// sent value keeps the contract's name (SPEC 0195, #428).

SoilRecord _record(String textureClass) => SoilRecord(
      id: 1,
      uuid: 'rec-1',
      imagePath: 'x.png',
      timestamp: '2026-10-22T10:42:00',
      textureClass: textureClass,
      confidenceScore: 0.82,
    );

void main() {
  test('label_for_accents_the_contract_names', () {
    expect(SoilTextureReference.labelFor('Media'), 'Média');
    expect(SoilTextureReference.labelFor('Muito Argilosa'), 'Muito argilosa');
    for (final unchanged in ['Arenosa', 'Argilosa', 'Siltosa', 'Outra']) {
      expect(SoilTextureReference.labelFor(unchanged), unchanged);
    }
  });

  test('display_texture_class_uses_the_label', () {
    final record = _record('Media');
    expect(record.displayTextureClass, 'Média');
    expect(record.textureClass, 'Media');
    expect(
      SoilRecord(imagePath: 'x.png', timestamp: '2026-10-22T10:42:00')
          .displayTextureClass,
      'Não classificado',
    );
  });

  testWidgets('result_header_shows_the_label', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => _record('Media')),
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
    ));
    await tester.pumpAndSettle();

    expect(find.text('Média'), findsOneWidget);
    expect(find.text('Media'), findsNothing);
  });

  testWidgets('analysis_tile_announces_the_label', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AnalysisTile(record: _record('Muito Argilosa'))),
    ));

    expect(find.text('Muito argilosa'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Muito argilosa, ')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Muito Argilosa')), findsNothing);
    semantics.dispose();
  });

  testWidgets('capture_chip_shows_the_label', (tester) async {
    final dir = Directory.systemTemp.createTempSync('label_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = File('${dir.path}/sample.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CaptureImagePreview(
          image: image,
          isLoading: false,
          isClassifying: false,
          classificationResult: const InferenceResult(
            textureClass: 'Media',
            confidenceScore: 0.82,
          ),
        ),
      ),
    ));

    expect(find.textContaining('Média · '), findsOneWidget);
    expect(find.textContaining('Media'), findsNothing);
  });

  testWidgets('filter_chip_shows_the_label_and_filters_by_name',
      (tester) async {
    String? selected;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data([_record('Media')]),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: HistoryFilterBar(
            searchController: TextEditingController(),
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onSelectTexture: (value) => selected = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Media'), findsNothing);
    await tester.tap(find.text('Média'));
    expect(selected, 'Media');
  });

  test('shared_text_uses_the_label', () {
    final text = ShareContentBuilder.caption(_record('Media'));
    expect(text, contains('Classe: Média'));
  });
}
