// Tests for [ImagePreviewScreen]'s image viewer: the broken-image fallback is
// now provided by `Image.file`'s `errorBuilder` instead of a synchronous
// `existsSync()` pre-check. The private `_ImageViewer` is exercised through the
// public screen, with `soilRecordByIdProvider` overridden to supply the record.
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import '../../support/fake_soil_record_repository.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/visio_app_bar.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/guidelines.dart';

class _RecordingShareService extends ShareService {
  bool shared = false;

  @override
  Future<void> shareRecord(
    SoilRecord record, {
    bool includeLocation = false,
  }) async {
    shared = true;
  }
}

void main() {
  late Directory tempDir;
  late String imagePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('visiosoil_preview_test');
    imagePath = (File(p.join(tempDir.path, 'photo.png'))
          ..writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4))))
        .path;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  SoilRecord record() => SoilRecord(
        id: 1,
        imagePath: imagePath,
        timestamp: DateTime.utc(2026, 1, 2, 14, 30).toIso8601String(),
      );

  Future<void> pumpPreview(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soilRecordByIdProvider.overrideWith((ref, id) async => record()),
        ],
        child: MaterialApp(
          theme: theme,
          home: const ImagePreviewScreen(recordId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The viewer keeps the whole photograph, so zooming out and panning reach
  // its edges (review of #436).
  testWidgets('photo_is_shown_whole', (tester) async {
    await pumpPreview(tester);

    expect(tester.widget<Image>(find.byType(Image)).fit, BoxFit.contain);
  });

  testWidgets(
    'preview_image_file_has_error_builder_rendering_broken_image_fallback',
    (tester) async {
      await pumpPreview(tester);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.errorBuilder, isNotNull);

      final fallback = image.errorBuilder!(
        tester.element(find.byType(Image)),
        Exception('load failed'),
        null,
      );
      expect(fallback, isA<Icon>());
      expect((fallback as Icon).icon, Icons.broken_image);
    },
  );

  testWidgets('a load error shows a retry action', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider
            .overrideWith((ref, id) async => throw Exception('boom')),
      ],
      child: const MaterialApp(home: ImagePreviewScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('a null record shows the not-found view with no retry',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => null),
      ],
      child: const MaterialApp(home: ImagePreviewScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Registro não encontrado'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsNothing);
  });

  // A failed or missing record is the shared error state under the shared bar,
  // on the theme's background, not the viewer's black canvas (SPEC 0124).
  group('one_error_presentation', () {
    Future<void> pumpWith(
      WidgetTester tester,
      Future<SoilRecord?> Function() load,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          soilRecordByIdProvider.overrideWith((ref, id) => load()),
        ],
        child: const MaterialApp(home: ImagePreviewScreen(recordId: 1)),
      ));
      await tester.pumpAndSettle();
    }

    void expectSharedErrorState(WidgetTester tester, String message) {
      expect(find.widgetWithText(ErrorState, message), findsOneWidget);
      expect(find.byType(VisioAppBar), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, isNot(Colors.black));
    }

    testWidgets('preview load error', (tester) async {
      await pumpWith(tester, () async => throw Exception('boom'));

      expectSharedErrorState(tester, 'Não foi possível carregar o registro.');
    });

    testWidgets('preview not found', (tester) async {
      await pumpWith(tester, () async => null);

      expectSharedErrorState(tester, 'Registro não encontrado');
    });

    // Riverpod retries a failing provider on its own until it gives up, which
    // settling waits out; the tap must then ask for the record again.
    testWidgets('retry_still_reloads', (tester) async {
      var loads = 0;
      await pumpWith(tester, () async {
        loads++;
        throw Exception('boom');
      });
      final before = loads;

      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();

      expect(loads, greaterThan(before));
    });
  });

  // SPEC 0118: icon-only buttons carry a pt-BR label.
  testWidgets('icon_buttons_are_labelled', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpPreview(tester);

    expect(find.byTooltip('Fechar'), findsOneWidget);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  });

  // The v11 "Foto da amostra" screen (redesign §3.8, SPEC 0198): the
  // photograph, then what the app knows about it, replacing SPEC 0125's
  // photo-only viewer.
  SoilRecord classified({bool located = true}) => SoilRecord(
        id: 1,
        imagePath: imagePath,
        timestamp: '2026-10-22T10:42:00',
        textureClass: 'Media',
        confidenceScore: 0.82,
        latitude: located ? -17.79 : null,
        longitude: located ? -50.92 : null,
        modelVersion: '1.0.0',
      );

  Future<void> pumpFacts(WidgetTester tester, SoilRecord shown) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => shown),
      ],
      child: const MaterialApp(home: ImagePreviewScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('photo_screen_lists_the_known_facts', (tester) async {
    await pumpFacts(tester, classified());

    expect(find.text('Foto da amostra'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Classe estimada'), findsOneWidget);
    expect(find.text('Média'), findsOneWidget);
    expect(find.text('Alta · 82%'), findsOneWidget);
    expect(find.text('22/10/2026 · 10:42'), findsOneWidget);
    expect(find.text('Coordenadas'), findsOneWidget);
    expect(find.text('no aparelho · v1.0.0'), findsOneWidget);
    expect(find.byTooltip('Fechar'), findsOneWidget);
    expect(find.byTooltip('Compartilhar'), findsOneWidget);
    expect(find.text('Excluir registro'), findsOneWidget);
  });

  testWidgets('a record without coordinates has no coordinates row',
      (tester) async {
    await pumpFacts(tester, classified(located: false));
    expect(find.text('Coordenadas'), findsNothing);
  });

  testWidgets('photo_screen_shares_and_deletes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final share = _RecordingShareService();
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider
            .overrideWith((ref, id) async => classified(located: false)),
        shareServiceProvider.overrideWithValue(share),
        soilRecordRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/preview',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('HOME_STUB')),
            ),
            GoRoute(
              path: '/preview',
              builder: (_, _) => const ImagePreviewScreen(recordId: 1),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Compartilhar'));
    await tester.pumpAndSettle();
    expect(share.shared, isTrue);

    await tester.tap(find.text('Excluir registro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excluir'));
    await tester.pumpAndSettle();
    expect(repository.deleteByIdCalls, [1]);
    expect(find.text('HOME_STUB'), findsOneWidget);
  });

  testWidgets('the photograph carries the record hero tag', (tester) async {
    await pumpFacts(tester, classified());
    expect(
      find.byWidgetPredicate(
        (w) => w is Hero && w.tag == recordPhotoHeroTag(1),
      ),
      findsOneWidget,
    );
  });

  // The viewer passes Flutter's four accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      // No file, as in the other screens' harnesses: the contrast check lets
      // real time pass, and a photograph read then would still be open when
      // tearDown deletes it.
      File(imagePath).deleteSync();
      await pumpPreview(tester, theme: theme);
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }
}
