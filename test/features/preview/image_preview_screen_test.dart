// Tests for [ImagePreviewScreen]'s image viewer: the broken-image fallback is
// now provided by `Image.file`'s `errorBuilder` instead of a synchronous
// `existsSync()` pre-check. The private `_ImageViewer` is exercised through the
// public screen, with `soilRecordByIdProvider` overridden to supply the record.
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

  Future<void> pumpPreview(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          soilRecordByIdProvider.overrideWith((ref, id) async => record()),
        ],
        child: MaterialApp(home: const ImagePreviewScreen(recordId: 1)),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  // The viewer is the photograph and one way out; details, underneath it,
  // holds everything else (SPEC 0125).
  testWidgets('viewer_is_photo_only', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => record()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ImagePreviewScreen(recordId: 1),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget);
    expect(find.byTooltip('Fechar'), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar'));
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewScreen), findsNothing);
  });

  testWidgets('viewer_has_no_duplicate_info', (tester) async {
    final located = SoilRecord(
      id: 1,
      imagePath: imagePath,
      timestamp: DateTime.utc(2026, 1, 2, 14, 30).toIso8601String(),
      address: 'Fazenda Boa Vista, Piracicaba',
      latitude: -22.7,
      longitude: -47.6,
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        soilRecordByIdProvider.overrideWith((ref, id) async => located),
      ],
      child: const MaterialApp(home: ImagePreviewScreen(recordId: 1)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Capturado em'), findsNothing);
    expect(find.text('Localização'), findsNothing);
    expect(find.text(located.formattedTimestamp), findsNothing);
    expect(find.textContaining('Fazenda Boa Vista'), findsNothing);
  });
}
