import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';

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
}
