import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/live_reading.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// The state a guidance banner is in, read from its colour and its icon.
enum GuidanceTone { ready, caution, alert, neutral }

/// What the guided camera's banner says: a tone and one short sentence.
@immutable
class Guidance {
  const Guidance({
    required this.tone,
    required this.message,
    required this.icon,
  });

  final GuidanceTone tone;
  final String message;
  final IconData icon;

  @override
  bool operator ==(Object other) =>
      other is Guidance &&
      other.tone == tone &&
      other.message == message &&
      other.icon == icon;

  @override
  int get hashCode => Object.hash(tone, message, icon);
}

/// Up to this tilt, in degrees, the phone counts as level (SPEC 0165).
const double levelTiltDegrees = 5.0;

/// Past this tilt, in degrees, the phone counts as tilted.
const double maxTiltDegrees = 12.0;

/// The banner for a smoothed [tilt], or for no tilt at all
/// (`tiltUnavailable`). The level guides and never blocks.
Guidance guidanceForTilt(double? tilt) {
  if (tilt == null) {
    return const Guidance(
      tone: GuidanceTone.neutral,
      message: 'Encaixe a folha no contorno.',
      icon: Icons.crop_portrait,
    );
  }
  if (tilt <= levelTiltDegrees) {
    return const Guidance(
      tone: GuidanceTone.ready,
      message: 'Nivelado. Encaixe a folha no contorno.',
      icon: Icons.check_circle_outline,
    );
  }
  if (tilt <= maxTiltDegrees) {
    return const Guidance(
      tone: GuidanceTone.caution,
      message: 'Quase. Deixe o celular paralelo ao chão.',
      icon: Icons.warning_amber_rounded,
    );
  }
  return const Guidance(
    tone: GuidanceTone.alert,
    message: 'Segure o celular paralelo ao chão, de cima.',
    icon: Icons.error_outline,
  );
}

/// The rows of SPEC 0166's table, in priority order: the first that holds
/// sets the banner.
enum GuidanceRow {
  tilted,
  sheetNotFound,
  sheetCropped,
  tooCoarse,
  sheetMisaligned,
  soilNotMeasured,
  smallSoil,
  almostLevel,
  ready,
}

/// The cause and correction named when a guidance row blocks the shutter
/// (SPEC 0224). Only distance failures belong to the distance chip.
({String cause, String correction, bool isDistance})? blockedGuidance(
  GuidanceRow row,
  SheetAlignment? alignment,
) {
  const tooClose = (
    cause: 'perto demais',
    correction: 'afaste até a folha caber na moldura',
    isDistance: true,
  );
  const tooFar = (
    cause: 'longe demais',
    correction: 'aproxime até a amostra preencher a moldura',
    isDistance: true,
  );
  return switch (row) {
    GuidanceRow.ready => null,
    GuidanceRow.sheetCropped => tooClose,
    GuidanceRow.tooCoarse => tooFar,
    GuidanceRow.tilted || GuidanceRow.almostLevel => (
      cause: 'celular inclinado',
      correction: 'deixe o celular paralelo ao chão',
      isDistance: false,
    ),
    GuidanceRow.sheetNotFound => (
      cause: 'folha fora do contorno',
      correction: 'enquadre a folha A4 inteira no contorno',
      isDistance: false,
    ),
    GuidanceRow.soilNotMeasured => (
      cause: 'solo não medido',
      correction: 'coloque o solo no meio da folha, num círculo de 8 a 10 cm',
      isDistance: false,
    ),
    GuidanceRow.smallSoil => (
      cause: 'pouco solo',
      correction: 'espalhe num círculo de 8 a 10 cm',
      isDistance: false,
    ),
    GuidanceRow.sheetMisaligned => switch (alignment?.fix) {
      MisalignmentFix.farther => tooClose,
      MisalignmentFix.closer => tooFar,
      MisalignmentFix.shift => (
        cause: 'folha fora do centro',
        correction: 'leve o celular para ${_towards(alignment!.arrow!)}',
        isDistance: false,
      ),
      MisalignmentFix.turn => (
        cause: 'folha torta',
        correction: 'gire o celular até a folha ficar reta no contorno',
        isDistance: false,
      ),
      null => null,
    },
  };
}

/// The banner for a smoothed [tilt] (null: `tiltUnavailable`) and the live
/// [reading] (null: none yet, or no reader), with [tooCoarse] the scale
/// estimate's verdict and [alignment] the guides' (SPEC 0169; null when the
/// corners are not mapped). With no reading, the banner is the tilt's alone.
({GuidanceRow row, Guidance guidance}) guidanceFor({
  required double? tilt,
  required LiveReading? reading,
  required bool tooCoarse,
  SheetAlignment? alignment,
}) {
  if (reading == null) {
    final guidance = guidanceForTilt(tilt);
    final row = switch (guidance.tone) {
      GuidanceTone.alert => GuidanceRow.tilted,
      GuidanceTone.caution => GuidanceRow.almostLevel,
      _ => GuidanceRow.ready,
    };
    return (row: row, guidance: guidance);
  }
  if (tilt != null && tilt > maxTiltDegrees) {
    return (row: GuidanceRow.tilted, guidance: guidanceForTilt(tilt));
  }
  switch (reading) {
    case LiveSheetNotFound():
      return (
        row: GuidanceRow.sheetNotFound,
        guidance: const Guidance(
          tone: GuidanceTone.alert,
          message: 'Enquadre a folha A4 inteira no contorno.',
          icon: Icons.crop_free,
        ),
      );
    case LiveSheetCropped():
      return _cropped(croppedSidesOf(reading, alignment));
    case LiveSheetFound(:final discDiameterMm, :final holdsMinPatches):
      final offScreen = croppedSidesOf(reading, alignment);
      if (offScreen.isNotEmpty) return _cropped(offScreen);
      if (tooCoarse) {
        return (
          row: GuidanceRow.tooCoarse,
          guidance: const Guidance(
            tone: GuidanceTone.caution,
            message: 'Aproxime o celular da folha.',
            icon: Icons.zoom_in,
          ),
        );
      }
      final fix = alignment?.fix;
      if (fix != null) {
        return (
          row: GuidanceRow.sheetMisaligned,
          guidance: _misaligned(fix, alignment!.arrow),
        );
      }
      if (discDiameterMm == null) {
        return (
          row: GuidanceRow.soilNotMeasured,
          guidance: const Guidance(
            tone: GuidanceTone.caution,
            message: 'Coloque o solo no meio da folha, num círculo de 8 a 10 cm.',
            icon: Icons.grain,
          ),
        );
      }
      if (!holdsMinPatches) {
        return (
          row: GuidanceRow.smallSoil,
          guidance: Guidance(
            tone: GuidanceTone.caution,
            message: 'Pouco solo (${_centimetres(discDiameterMm)} cm). '
                'Espalhe num círculo de 8 a 10 cm.',
            icon: Icons.blur_circular,
          ),
        );
      }
  }
  if (tilt != null && tilt > levelTiltDegrees) {
    return (row: GuidanceRow.almostLevel, guidance: guidanceForTilt(tilt));
  }
  return (
    row: GuidanceRow.ready,
    guidance: Guidance(
      tone: GuidanceTone.ready,
      // With no tilt, nothing says the phone is level.
      message: tilt == null ? 'Folha e solo certos.' : 'Pronto. Segure firme.',
      icon: Icons.check_circle,
    ),
  );
}

/// The screen's sides a sheet has left by: the reader's own when it refused
/// the sheet as cropped, or, for a whole sheet, the sides a mapped corner
/// falls past the screen (SPEC 0169). Empty when neither says.
List<FrameSide> croppedSidesOf(
  LiveReading? reading,
  SheetAlignment? alignment,
) =>
    switch (reading) {
      LiveSheetCropped(:final sides) => sides,
      LiveSheetFound() => alignment?.offScreen ?? const [],
      _ => const [],
    };

/// Whether [sides] name one way out: one side, or a first side whose second
/// is adjacent to it. Opposite sides, or three or more, mean the sheet is
/// larger than the screen.
bool _oneWayOut(List<FrameSide> sides) {
  if (sides.length == 1) return true;
  if (sides.length != 2) return false;
  const across = {FrameSide.left, FrameSide.right};
  return across.contains(sides[0]) != across.contains(sides[1]);
}

({GuidanceRow row, Guidance guidance}) _cropped(List<FrameSide> sides) {
  final String message;
  if (sides.isEmpty) {
    message = 'A folha está cortada. Afaste o celular.';
  } else if (_oneWayOut(sides)) {
    final side = switch (sides.first) {
      FrameSide.left => 'esquerda',
      FrameSide.right => 'direita',
      FrameSide.top => 'parte de cima',
      FrameSide.bottom => 'parte de baixo',
    };
    message = 'A folha saiu pela $side.';
  } else {
    message = 'A folha passa da tela. Afaste o celular.';
  }
  return (
    row: GuidanceRow.sheetCropped,
    guidance: Guidance(
      tone: GuidanceTone.alert,
      message: message,
      icon: Icons.zoom_out_map,
    ),
  );
}

/// The way to move the phone, as the banner and the warning name it.
String _towards(FrameSide side) => switch (side) {
      FrameSide.left => 'a esquerda',
      FrameSide.right => 'a direita',
      FrameSide.top => 'cima',
      FrameSide.bottom => 'baixo',
    };

Guidance _misaligned(MisalignmentFix fix, FrameSide? arrow) => switch (fix) {
      MisalignmentFix.shift => Guidance(
          tone: GuidanceTone.caution,
          message: 'Leve o celular para ${_towards(arrow!)}.',
          icon: Icons.open_with,
        ),
      MisalignmentFix.closer => const Guidance(
          tone: GuidanceTone.caution,
          message: 'Aproxime o celular da folha.',
          icon: Icons.zoom_in,
        ),
      MisalignmentFix.farther => const Guidance(
          tone: GuidanceTone.caution,
          message: 'Afaste o celular da folha.',
          icon: Icons.zoom_out_map,
        ),
      MisalignmentFix.turn => const Guidance(
          tone: GuidanceTone.caution,
          message: 'Gire o celular até a folha ficar reta no contorno.',
          icon: Icons.rotate_right,
        ),
    };

/// The warning card drawn over the outline while the sheet is off the
/// screen (SPEC 0169).
({String title, String line}) croppedWarning(List<FrameSide> sides) => (
      title: 'A folha saiu da tela',
      line: sides.isNotEmpty && _oneWayOut(sides)
          ? 'Leve o celular para ${_towards(sides.first)}'
          : 'Afaste o celular da folha',
    );

/// The soil patch the user spread, in centimetres to one decimal with a
/// comma: the disc plus the reader's margin on both sides.
String _centimetres(double discDiameterMm) =>
    ((discDiameterMm + 2 * soilMarginMm) / 10)
        .toStringAsFixed(1)
        .replaceAll('.', ',');

/// Changes the shown row only once two consecutive readings agree on it, so
/// the banner does not flicker between readings (SPEC 0166).
class ReadingDebouncer {
  GuidanceRow? _shown;
  GuidanceRow? _last;

  /// Takes a reading's row and returns the row to show, or null before two
  /// readings have agreed.
  GuidanceRow? accept(GuidanceRow row) {
    if (row == _last) _shown = row;
    _last = row;
    return _shown;
  }
}

/// The banner's colours for a [tone]: each role's container and the ink
/// drawn on it, the pairs the palette holds to WCAG text contrast. The
/// palette holds no ink for the bare `warning`, and white on it is 2.93 : 1.
({Color background, Color foreground}) guidanceColors(
  GuidanceTone tone,
  AppPalette palette,
) =>
    switch (tone) {
      GuidanceTone.ready => (
          background: palette.primaryContainer,
          foreground: palette.onPrimaryContainer,
        ),
      GuidanceTone.caution => (
          background: palette.warningContainer,
          foreground: palette.onWarningContainer,
        ),
      GuidanceTone.alert => (
          background: palette.errorContainer,
          foreground: palette.onErrorContainer,
        ),
      GuidanceTone.neutral => (
          background: palette.surfaceVariant,
          foreground: palette.onSurfaceVariant,
        ),
    };
