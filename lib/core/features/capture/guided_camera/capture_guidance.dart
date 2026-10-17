import 'package:flutter/material.dart';
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

/// The banner's colours for a [tone]: each role's container and the ink
/// drawn on it, the pairs the palette holds to WCAG text contrast. The bare
/// `warning` cannot carry a sentence in any ink at 4.5 : 1.
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
