import 'package:flutter/material.dart';
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
  soilNotMeasured,
  smallSoil,
  almostLevel,
  ready,
}

/// The banner for a smoothed [tilt] (null: `tiltUnavailable`) and the live
/// [reading] (null: none yet, or no reader), with [tooCoarse] the scale
/// estimate's verdict. With no reading, the banner is the tilt's alone.
({GuidanceRow row, Guidance guidance}) guidanceFor({
  required double? tilt,
  required LiveReading? reading,
  required bool tooCoarse,
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
      return (
        row: GuidanceRow.sheetCropped,
        guidance: const Guidance(
          tone: GuidanceTone.alert,
          message: 'A folha está cortada. Afaste o celular.',
          icon: Icons.zoom_out_map,
        ),
      );
    case LiveSheetFound(:final discDiameterMm, :final holdsMinPatches):
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
