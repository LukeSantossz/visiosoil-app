import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guidance.dart';

/// An A4 sheet's height over its width, portrait.
const double sheetAspect = 297 / 210;

/// How much of the available width, or height, the outline takes.
const double guideFill = 0.85;

/// The protocol's 8 to 10 cm soil circle, drawn at its middle.
const double targetDiameterMm = 90;

/// An A4 sheet's width, the scale the target is drawn against.
const double sheetWidthMm = 210;

/// Where the guide is drawn on a screen of a given size, between a banner of
/// `topInset` and a footer of `bottomInset` (SPEC 0165).
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
  }) {
    final available = math.max(0.0, screen.height - topInset - bottomInset);
    final width = math.min(
      guideFill * screen.width,
      guideFill * available / sheetAspect,
    );
    final centre = Offset(screen.width / 2, topInset + available / 2);
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
class CaptureGuideOverlay extends StatelessWidget {
  const CaptureGuideOverlay({
    super.key,
    required this.topInset,
    required this.bottomInset,
    required this.tilt,
    required this.direction,
  });

  final double topInset;
  final double bottomInset;

  /// The smoothed tilt in degrees; null hides the level (`tiltUnavailable`).
  final double? tilt;

  /// The direction the phone leans toward, as a unit vector or zero.
  final Offset direction;

  static const double _levelRadius = 28;
  static const double _labelWidth = 160;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final layout = CaptureGuideLayout.compute(
        constraints.biggest,
        topInset: topInset,
        bottomInset: bottomInset,
      );
      final tilt = this.tilt;
      return Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GuidePainter(layout)),
          Positioned(
            left: layout.targetCentre.dx - _labelWidth / 2,
            width: _labelWidth,
            top: layout.targetCentre.dy + layout.targetDiameter / 2 + 8,
            child: const Text(
              '8–10 cm de solo',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
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
        ],
      );
    });
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.layout);

  final CaptureGuideLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = layout.outline;
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(outline);
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final bracket = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final arm = outline.shortestSide * 0.12;
    for (final (corner, dx, dy) in [
      (outline.topLeft, 1.0, 1.0),
      (outline.topRight, -1.0, 1.0),
      (outline.bottomLeft, 1.0, -1.0),
      (outline.bottomRight, -1.0, -1.0),
    ]) {
      canvas.drawLine(corner, corner + Offset(arm * dx, 0), bracket);
      canvas.drawLine(corner, corner + Offset(0, arm * dy), bracket);
    }

    canvas.drawCircle(
      layout.targetCentre,
      layout.targetDiameter / 2,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.layout.outline != layout.outline ||
      old.layout.targetDiameter != layout.targetDiameter;
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
