import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;

SheetAlignment alignment(MisalignmentFix fix, [FrameSide? arrow]) =>
    (brackets: allIdle, arrow: arrow, fix: fix, offScreen: const []);

void main() {
  final cases = [
    (
      GuidanceRow.sheetCropped,
      null,
      'perto demais',
      'afaste até a folha caber na moldura',
      true,
    ),
    (
      GuidanceRow.tooCoarse,
      null,
      'longe demais',
      'aproxime até a amostra preencher a moldura',
      true,
    ),
    (
      GuidanceRow.sheetMisaligned,
      alignment(MisalignmentFix.farther),
      'perto demais',
      'afaste até a folha caber na moldura',
      true,
    ),
    (
      GuidanceRow.sheetMisaligned,
      alignment(MisalignmentFix.closer),
      'longe demais',
      'aproxime até a amostra preencher a moldura',
      true,
    ),
    (
      GuidanceRow.tilted,
      null,
      'celular inclinado',
      'deixe o celular paralelo ao chão',
      false,
    ),
    (
      GuidanceRow.almostLevel,
      null,
      'celular inclinado',
      'deixe o celular paralelo ao chão',
      false,
    ),
    (
      GuidanceRow.sheetNotFound,
      null,
      'folha fora do contorno',
      'enquadre a folha A4 inteira no contorno',
      false,
    ),
    (
      GuidanceRow.sheetMisaligned,
      alignment(MisalignmentFix.turn),
      'folha torta',
      'gire o celular até a folha ficar reta no contorno',
      false,
    ),
    (
      GuidanceRow.soilNotMeasured,
      null,
      'solo não medido',
      'coloque o solo no meio da folha, num círculo de 8 a 10 cm',
      false,
    ),
    (
      GuidanceRow.smallSoil,
      null,
      'pouco solo',
      'espalhe num círculo de 8 a 10 cm',
      false,
    ),
  ];
  for (final (index, entry) in cases.indexed) {
    test('blocking_rows_name_their_real_cause_$index', () {
      expect(blockedGuidance(entry.$1, entry.$2), (
        cause: entry.$3,
        correction: entry.$4,
        isDistance: entry.$5,
      ));
    });
  }
  for (final side in FrameSide.values) {
    test('shift_reuses_banner_direction_${side.name}', () {
      final placed = alignment(MisalignmentFix.shift, side);
      final failure = blockedGuidance(GuidanceRow.sheetMisaligned, placed)!;
      final banner = guidanceFor(
        tilt: 0,
        reading: const LiveSheetFound(
          sheetLongSidePx: 900,
          discDiameterMm: 90,
          holdsMinPatches: true,
        ),
        tooCoarse: false,
        alignment: placed,
      ).guidance.message;
      expect(failure.cause, 'folha fora do centro');
      expect(failure.isDistance, isFalse);
      expect('${failure.correction}.', banner.replaceFirst('Leve', 'leve'));
    });
  }
  test('ready_and_missing_fix_have_no_failure', () {
    expect(blockedGuidance(GuidanceRow.ready, null), isNull);
    expect(blockedGuidance(GuidanceRow.sheetMisaligned, null), isNull);
    expect(
      blockedGuidance(GuidanceRow.sheetMisaligned, (
        brackets: allIdle,
        arrow: null,
        fix: null,
        offScreen: const [],
      )),
      isNull,
    );
  });
}
