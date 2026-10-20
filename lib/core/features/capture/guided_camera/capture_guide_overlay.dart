import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/guide_alignment.dart';
import 'package:visiosoil_app/core/services/descriptors/a4_sheet.dart'
    show FrameSide;
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// An A4 sheet's height over its width, portrait.
const double sheetAspect = 297 / 210;

/// How much of the available width, or height, the outline takes.
const double guideFill = 0.85;

/// The protocol's 8 to 10 cm soil circle, drawn at its middle.
const double targetDiameterMm = 90;

/// An A4 sheet's width, the scale the target is drawn against.
const double sheetWidthMm = 210;

/// Where the guide is drawn on a screen of a given size, between a banner of
/// `topInset` and a footer of `bottomInset` (SPEC 0165), and inside the
/// [preview]'s rectangle when one is given, so a sheet filling the outline is
/// a sheet filling that share of the still (SPEC 0171).
@immutable
class CaptureGuideLayout {
  const CaptureGuideLayout._(
    this.outline,
    this.targetCentre,
    this.targetDiameter,
  );

  factory CaptureGuideLayout.compute(
    Size screen, {
    required double topInset,
    required double bottomInset,
    Rect? preview,
  }) {
    final band = Rect.fromLTRB(
      0,
      topInset,
      screen.width,
      math.max(topInset, screen.height - bottomInset),
    );
    final region = preview == null || !preview.overlaps(band)
        ? band
        : preview.intersect(band);
    final width = math.min(
      guideFill * region.width,
      guideFill * region.height / sheetAspect,
    );
    final centre = region.center;
    final outline = Rect.fromCenter(
      center: centre,
      width: width,
      height: width * sheetAspect,
    );
    return CaptureGuideLayout._(
      outline,
      centre,
      width * targetDiameterMm / sheetWidthMm,
    );
  }

  /// The sheet's outline: where a sheet filling it shows the soil circle at
  /// the size the protocol asks for.
  final Rect outline;
  final Offset targetCentre;
  final double targetDiameter;
}

/// The sheet outline, the soil target and the level, drawn over the preview.
/// Each corner bracket and the target are drawn in their own state, and a
/// sheet off the screen lights the sides it left by under a warning card
/// (SPEC 0169).
class CaptureGuideOverlay extends StatelessWidget {
  const CaptureGuideOverlay({
    super.key,
    required this.topInset,
    required this.bottomInset,
    required this.tilt,
    required this.direction,
    this.brackets = allIdle,
    this.arrow,
    this.target = GuideState.idle,
    this.glow = const [],
    this.warning,
    this.preview,
  });

  final double topInset;
  final double bottomInset;

  /// The preview's rectangle in the overlay's coordinates; null lays the
  /// guide out on the whole overlay.
  final Rect? preview;

  /// The smoothed tilt in degrees; null hides the level (`tiltUnavailable`).
  final double? tilt;

  /// The direction the phone leans toward, as a unit vector or zero.
  final Offset direction;

  final Map<BracketPosition, GuideState> brackets;

  /// The way to move the phone, drawn from each bracket not placed; null
  /// draws no arrow.
  final FrameSide? arrow;

  final GuideState target;

  /// The sides the sheet left the screen by, each lit along its edge.
  final List<FrameSide> glow;

  /// The card over the outline while the sheet is off the screen.
  final ({String title, String line})? warning;

  static const double _levelRadius = 28;
  static const double _labelWidth = 160;
  static const double _glowDepth = 34;
  static const double _warningWidth = 220;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final layout = CaptureGuideLayout.compute(
        constraints.biggest,
        topInset: topInset,
        bottomInset: bottomInset,
        preview: preview,
      );
      final tilt = this.tilt;
      final palette = context.palette;
      final warning = this.warning;
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: _GuidePainter(
              layout,
              brackets: brackets,
              arrow: arrow,
              target: target,
              colours: (
                placed: palette.primaryContainer,
                near: palette.warningContainer,
                off: palette.errorContainer,
              ),
            ),
          ),
          for (final side in glow)
            _glowAlong(side, constraints.biggest, palette.errorContainer),
          // The level goes under the warning card, which shares its centre.
          if (tilt != null)
            Positioned(
              key: const ValueKey('guided-camera-level'),
              left: layout.targetCentre.dx - _levelRadius,
              top: layout.targetCentre.dy - _levelRadius,
              width: _levelRadius * 2,
              height: _levelRadius * 2,
              child: CustomPaint(
                painter: _LevelPainter(
                  offset: direction *
                      (math.min(tilt / maxTiltDegrees, 1.0) * _levelRadius),
                  level: tilt <= levelTiltDegrees,
                ),
              ),
            ),
          if (warning == null)
            Positioned(
              left: layout.targetCentre.dx - _labelWidth / 2,
              width: _labelWidth,
              top: layout.targetCentre.dy + layout.targetDiameter / 2 + 8,
              child: const Text(
                '8–10 cm de solo',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            )
          else
            Positioned(
              key: const ValueKey('guided-camera-warning'),
              left: layout.targetCentre.dx - _warningWidth / 2,
              width: _warningWidth,
              top: layout.targetCentre.dy - 44,
              child: _WarningCard(warning: warning, palette: palette),
            ),
        ],
      );
    });
  }

  /// A band along [side] fading from [colour] at the edge to nothing, kept
  /// between the banner and the footer.
  Widget _glowAlong(FrameSide side, Size size, Color colour) {
    final (begin, end) = switch (side) {
      FrameSide.left => (Alignment.centerLeft, Alignment.centerRight),
      FrameSide.right => (Alignment.centerRight, Alignment.centerLeft),
      FrameSide.top => (Alignment.topCenter, Alignment.bottomCenter),
      FrameSide.bottom => (Alignment.bottomCenter, Alignment.topCenter),
    };
    final band = IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: begin,
            end: end,
            colors: [colour, colour.withValues(alpha: 0)],
          ),
        ),
      ),
    );
    final key = ValueKey('guided-camera-glow-${side.name}');
    final height = math.max(0.0, size.height - topInset - bottomInset);
    return switch (side) {
      FrameSide.left => Positioned(
          key: key,
          left: 0,
          top: topInset,
          width: _glowDepth,
          height: height,
          child: band,
        ),
      FrameSide.right => Positioned(
          key: key,
          right: 0,
          top: topInset,
          width: _glowDepth,
          height: height,
          child: band,
        ),
      FrameSide.top => Positioned(
          key: key,
          left: 0,
          right: 0,
          top: topInset,
          height: _glowDepth,
          child: band,
        ),
      FrameSide.bottom => Positioned(
          key: key,
          left: 0,
          right: 0,
          bottom: bottomInset,
          height: _glowDepth,
          child: band,
        ),
    };
  }
}

/// "A folha saiu da tela" and the way back, on the error container.
class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warning, required this.palette});

  final ({String title, String line}) warning;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final ink = palette.onErrorContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, color: ink),
            const SizedBox(height: 4),
            Text(
              warning.title,
              textAlign: TextAlign.center,
              style: TextStyle(color: ink, fontWeight: FontWeight.w700),
            ),
            Text(
              warning.line,
              textAlign: TextAlign.center,
              style: TextStyle(color: ink),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _StateColours = ({Color placed, Color near, Color off});

class _GuidePainter extends CustomPainter {
  _GuidePainter(
    this.layout, {
    required this.brackets,
    required this.arrow,
    required this.target,
    required this.colours,
  });

  final CaptureGuideLayout layout;
  final Map<BracketPosition, GuideState> brackets;
  final FrameSide? arrow;
  final GuideState target;
  final _StateColours colours;

  Color _colourOf(GuideState state) => switch (state) {
        GuideState.idle => Colors.white,
        GuideState.placed => colours.placed,
        GuideState.near => colours.near,
        GuideState.off => colours.off,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final outline = layout.outline;
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(outline);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    // A dark rim under every stroke keeps it visible on a pale surface.
    final rim = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final arm = outline.shortestSide * 0.12;
    for (final (position, corner, dx, dy) in [
      (BracketPosition.topLeft, outline.topLeft, 1.0, 1.0),
      (BracketPosition.topRight, outline.topRight, -1.0, 1.0),
      (BracketPosition.bottomLeft, outline.bottomLeft, 1.0, -1.0),
      (BracketPosition.bottomRight, outline.bottomRight, -1.0, -1.0),
    ]) {
      final state = brackets[position] ?? GuideState.idle;
      final colour = _colourOf(state);
      final bracket = Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      for (final paint in [rim, bracket]) {
        canvas.drawLine(corner, corner + Offset(arm * dx, 0), paint);
        canvas.drawLine(corner, corner + Offset(0, arm * dy), paint);
      }
      if (state == GuideState.near || state == GuideState.off) {
        // The halo tells a bracket out of place apart without its colour.
        canvas.drawCircle(
          corner,
          9,
          Paint()..color = colour.withValues(alpha: 0.25),
        );
        final arrow = this.arrow;
        if (arrow != null) _drawArrow(canvas, corner, arrow, colour);
      }
    }

    final radius = layout.targetDiameter / 2;
    if (target == GuideState.idle) {
      _drawDashedCircle(canvas, layout.targetCentre, radius);
    } else {
      final ring = Paint()
        ..color = _colourOf(target)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4;
      canvas.drawCircle(layout.targetCentre, radius, rim);
      canvas.drawCircle(layout.targetCentre, radius, ring);
    }
  }

  /// An arrow from [vertex] toward [side]: the way to move the phone.
  void _drawArrow(Canvas canvas, Offset vertex, FrameSide side, Color colour) {
    final unit = switch (side) {
      FrameSide.left => const Offset(-1, 0),
      FrameSide.right => const Offset(1, 0),
      FrameSide.top => const Offset(0, -1),
      FrameSide.bottom => const Offset(0, 1),
    };
    final start = vertex + unit * 16;
    final end = start + unit * 22;
    final tip = end + unit * 9;
    final across = Offset(-unit.dy, unit.dx) * 7;
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = colour
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo((end + across).dx, (end + across).dy)
        ..lineTo((end - across).dx, (end - across).dy)
        ..close(),
      Paint()..color = colour,
    );
  }

  /// The target as SPEC 0165 drew it, dashed while no soil is measured.
  void _drawDashedCircle(Canvas canvas, Offset centre, double radius) {
    const dashes = 36;
    const sweep = 2 * math.pi / dashes;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.6, false, paint);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.layout.outline != layout.outline ||
      old.layout.targetDiameter != layout.targetDiameter ||
      BracketPosition.values
          .any((position) => old.brackets[position] != brackets[position]) ||
      old.arrow != arrow ||
      old.target != target ||
      old.colours != colours;
}

class _LevelPainter extends CustomPainter {
  _LevelPainter({required this.offset, required this.level});

  final Offset offset;
  final bool level;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    canvas.drawCircle(
      centre,
      size.shortestSide / 2 - 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      centre + offset,
      6,
      Paint()..color = level ? Colors.white : Colors.white70,
    );
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.offset != offset || old.level != level;
}

/// The ring around the shutter that fills across the automatic capture's
/// one-second window (SPEC 0167). A countdown, not a loading spinner, so it
/// is drawn here with the rest of the guide.
class CountdownRingPainter extends CustomPainter {
  CountdownRingPainter(this.progress);

  /// From 0, the window just opened, to 1, the second is up.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(2);
    final track = Paint()
      ..color = Colors.white24
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawOval(rect, track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(CountdownRingPainter old) => old.progress != progress;
}
