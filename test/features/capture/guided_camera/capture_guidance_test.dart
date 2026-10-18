import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;

void main() {
  test('tilt_bands_name_the_sentence', () {
    void expectBand(double? tilt, GuidanceTone tone, String message) {
      final guidance = guidanceForTilt(tilt);
      expect(guidance.tone, tone, reason: '$tilt');
      expect(guidance.message, message, reason: '$tilt');
    }

    const level = 'Nivelado. Encaixe a folha no contorno.';
    const almost = 'Quase. Deixe o celular paralelo ao chão.';
    const tilted = 'Segure o celular paralelo ao chão, de cima.';
    expectBand(0, GuidanceTone.ready, level);
    expectBand(5, GuidanceTone.ready, level);
    expectBand(5.01, GuidanceTone.caution, almost);
    expectBand(12, GuidanceTone.caution, almost);
    expectBand(12.01, GuidanceTone.alert, tilted);
    expectBand(90, GuidanceTone.alert, tilted);
    expectBand(null, GuidanceTone.neutral, 'Encaixe a folha no contorno.');

    final icons = {
      for (final tilt in [0.0, 8.0, 20.0, null]) guidanceForTilt(tilt).icon,
    };
    expect(icons, hasLength(4), reason: 'each state carries its own icon');
  });

  group('live guidance (SPEC 0166)', () {
    const sound = LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: 70,
      holdsMinPatches: true,
    );
    const small = LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: 47.1,
      holdsMinPatches: false,
    );
    const noSoil = LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: null,
      holdsMinPatches: false,
    );

    GuidanceRow rowOf(double? tilt, LiveReading reading, {bool coarse = false}) =>
        guidanceFor(tilt: tilt, reading: reading, tooCoarse: coarse).row;

    test('guidance_follows_the_priority', () {
      expect(rowOf(20, const LiveSheetCropped()), GuidanceRow.tilted);
      expect(rowOf(0, const LiveSheetNotFound()), GuidanceRow.sheetNotFound);
      expect(rowOf(0, const LiveSheetCropped()), GuidanceRow.sheetCropped);
      expect(rowOf(0, small, coarse: true), GuidanceRow.tooCoarse);
      expect(rowOf(0, noSoil), GuidanceRow.soilNotMeasured);
      expect(rowOf(8, small), GuidanceRow.smallSoil);
      expect(rowOf(8, sound), GuidanceRow.almostLevel);
      expect(rowOf(0, sound), GuidanceRow.ready);
      // tiltUnavailable: the tilt rows never hold.
      expect(rowOf(null, const LiveSheetCropped()), GuidanceRow.sheetCropped);
      expect(rowOf(null, sound), GuidanceRow.ready);

      final messages = {
        for (final (tilt, reading, coarse) in [
          (20.0, sound, false),
          (0.0, const LiveSheetNotFound(), false),
          (0.0, const LiveSheetCropped(), false),
          (0.0, sound, true),
          (0.0, noSoil, false),
          (8.0, sound, false),
          (0.0, sound, false),
        ])
          guidanceFor(tilt: tilt, reading: reading, tooCoarse: coarse)
              .guidance
              .message,
      };
      expect(messages, {
        'Segure o celular paralelo ao chão, de cima.',
        'Enquadre a folha A4 inteira no contorno.',
        'A folha está cortada. Afaste o celular.',
        'Aproxime o celular da folha.',
        'Coloque o solo no meio da folha, num círculo de 8 a 10 cm.',
        'Quase. Deixe o celular paralelo ao chão.',
        'Pronto. Segure firme.',
      });
      expect(
        guidanceFor(tilt: null, reading: sound, tooCoarse: false).guidance,
        isA<Guidance>()
            .having((g) => g.message, 'message', 'Folha e solo certos.')
            .having((g) => g.tone, 'tone', GuidanceTone.ready),
      );
      expect(
        guidanceFor(tilt: 0, reading: const LiveSheetCropped(), tooCoarse: false)
            .guidance
            .tone,
        GuidanceTone.alert,
      );
      expect(guidanceFor(tilt: 0, reading: noSoil, tooCoarse: false).guidance.tone,
          GuidanceTone.caution);
    });

    test('no_reading_is_the_tilt_banner', () {
      expect(guidanceFor(tilt: 8, reading: null, tooCoarse: false).guidance,
          guidanceForTilt(8));
    });

    test('the_small_soil_sentence_names_the_size', () {
      expect(
        guidanceFor(tilt: 0, reading: small, tooCoarse: false).guidance.message,
        'Pouco solo (5,1 cm). Espalhe num círculo de 8 a 10 cm.',
      );
    });

    test('one_reading_does_not_change_the_banner', () {
      final debouncer = ReadingDebouncer();
      expect(debouncer.accept(GuidanceRow.sheetCropped), isNull);
      expect(debouncer.accept(GuidanceRow.sheetCropped), GuidanceRow.sheetCropped);
      expect(debouncer.accept(GuidanceRow.ready), GuidanceRow.sheetCropped);
      expect(debouncer.accept(GuidanceRow.ready), GuidanceRow.ready);
      expect(debouncer.accept(GuidanceRow.smallSoil), GuidanceRow.ready);
      expect(debouncer.accept(GuidanceRow.ready), GuidanceRow.ready);
    });
  });

  group('reactive guides (SPEC 0169)', () {
    const sound = LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: 70,
      holdsMinPatches: true,
    );
    const noSoil = LiveSheetFound(
      sheetLongSidePx: 900,
      discDiameterMm: null,
      holdsMinPatches: false,
    );
    const placed = {
      BracketPosition.topLeft: GuideState.placed,
      BracketPosition.topRight: GuideState.placed,
      BracketPosition.bottomRight: GuideState.placed,
      BracketPosition.bottomLeft: GuideState.placed,
    };
    final oneNear = {...placed, BracketPosition.topRight: GuideState.near};

    SheetAlignment misaligned(MisalignmentFix fix, {FrameSide? arrow}) =>
        (brackets: oneNear, arrow: arrow, fix: fix, offScreen: const []);

    String message(
      LiveReading reading,
      SheetAlignment? alignment, {
      bool coarse = false,
    }) => guidanceFor(
      tilt: 0,
      reading: reading,
      tooCoarse: coarse,
      alignment: alignment,
    ).guidance.message;

    test('misalignment_names_its_fix', () {
      expect(
        message(
          sound,
          misaligned(MisalignmentFix.shift, arrow: FrameSide.right),
        ),
        'Leve o celular para a direita.',
      );
      expect(
        message(sound, misaligned(MisalignmentFix.shift, arrow: FrameSide.top)),
        'Leve o celular para cima.',
      );
      expect(
        message(sound, misaligned(MisalignmentFix.closer)),
        'Aproxime o celular da folha.',
      );
      expect(
        message(sound, misaligned(MisalignmentFix.farther)),
        'Afaste o celular da folha.',
      );
      expect(
        message(sound, misaligned(MisalignmentFix.turn)),
        'Gire o celular até a folha ficar reta no contorno.',
      );
      expect(
        guidanceFor(
          tilt: 0,
          reading: sound,
          tooCoarse: false,
          alignment: misaligned(MisalignmentFix.turn),
        ).guidance.tone,
        GuidanceTone.caution,
      );
    });

    test('the_misaligned_row_sits_between_scale_and_soil', () {
      final turned = misaligned(MisalignmentFix.turn);
      GuidanceRow rowOf(LiveReading reading, {bool coarse = false}) =>
          guidanceFor(
            tilt: 0,
            reading: reading,
            tooCoarse: coarse,
            alignment: turned,
          ).row;
      expect(rowOf(noSoil), GuidanceRow.sheetMisaligned);
      expect(rowOf(sound, coarse: true), GuidanceRow.tooCoarse);
      expect(
        guidanceFor(
          tilt: 0,
          reading: sound,
          tooCoarse: false,
          alignment: (
            brackets: placed,
            arrow: null,
            fix: null,
            offScreen: const [],
          ),
        ).row,
        GuidanceRow.ready,
      );
    });

    test('cropped_sentences_name_the_side', () {
      expect(
        message(const LiveSheetCropped(sides: [FrameSide.right]), null),
        'A folha saiu pela direita.',
      );
      expect(
        message(
          const LiveSheetCropped(sides: [FrameSide.top, FrameSide.left]),
          null,
        ),
        'A folha saiu pela parte de cima.',
      );
      expect(
        message(
          const LiveSheetCropped(sides: [FrameSide.left, FrameSide.right]),
          null,
        ),
        'A folha passa da tela. Afaste o celular.',
      );
      expect(
        message(const LiveSheetCropped(), null),
        'A folha está cortada. Afaste o celular.',
      );
      // A whole sheet with a corner past the screen reads as cropped.
      expect(
        guidanceFor(
          tilt: 0,
          reading: sound,
          tooCoarse: false,
          alignment: (
            brackets: oneNear,
            arrow: FrameSide.right,
            fix: MisalignmentFix.shift,
            offScreen: const [FrameSide.right],
          ),
        ),
        isA<({GuidanceRow row, Guidance guidance})>()
            .having((g) => g.row, 'row', GuidanceRow.sheetCropped)
            .having(
              (g) => g.guidance.message,
              'message',
              'A folha saiu pela direita.',
            ),
      );
    });

    test('the_warning_names_the_way_to_move', () {
      expect(croppedWarning(const [FrameSide.right]), (
        title: 'A folha saiu da tela',
        line: 'Leve o celular para a direita',
      ));
      expect(croppedWarning(const [FrameSide.bottom]), (
        title: 'A folha saiu da tela',
        line: 'Leve o celular para baixo',
      ));
      expect(croppedWarning(const [FrameSide.left, FrameSide.right]), (
        title: 'A folha saiu da tela',
        line: 'Afaste o celular da folha',
      ));
      expect(croppedWarning(const []), (
        title: 'A folha saiu da tela',
        line: 'Afaste o celular da folha',
      ));
    });

    test('cropped_sides_come_from_the_reading_or_the_screen', () {
      expect(
        croppedSidesOf(const LiveSheetCropped(sides: [FrameSide.left]), null),
        [FrameSide.left],
      );
      expect(
        croppedSidesOf(sound, (
          brackets: oneNear,
          arrow: null,
          fix: MisalignmentFix.turn,
          offScreen: const [FrameSide.bottom],
        )),
        [FrameSide.bottom],
      );
      expect(croppedSidesOf(sound, null), isEmpty);
      expect(croppedSidesOf(null, null), isEmpty);
    });

    test('no_mapping_keeps_spec_0166', () {
      for (final reading in <LiveReading?>[
        null,
        const LiveSheetNotFound(),
        const LiveSheetCropped(),
        sound,
        noSoil,
      ]) {
        for (final tilt in <double?>[null, 0, 8, 20]) {
          for (final coarse in [false, true]) {
            final withNone = guidanceFor(
              tilt: tilt,
              reading: reading,
              tooCoarse: coarse,
              alignment: null,
            );
            expect(withNone.row, isNot(GuidanceRow.sheetMisaligned));
            expect(
              withNone,
              guidanceFor(tilt: tilt, reading: reading, tooCoarse: coarse),
            );
          }
        }
      }
    });
  });
}
