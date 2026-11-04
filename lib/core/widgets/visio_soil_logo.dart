import 'package:flutter/material.dart';

/// The official VisioSoil brand mark: a minimalist magnifying glass holding
/// three decreasing soil grains — vision and inspection fused with the texture
/// being measured.
///
/// Painted in code on a 48-unit viewBox, so it needs no SVG runtime. The
/// geometry was first taken from the design system's `assets/logo-mark.svg`
/// (SPEC 0024) and refined by SPEC 0255; [VisioSoilMarkGeometry] is now its
/// canonical source. [color] plays the role of the SVG's `currentColor`,
/// letting the mark sit on any background.
class VisioSoilLogo extends StatelessWidget {
  const VisioSoilLogo({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Center so a fixed-size (tight-constraint) parent cannot stretch the
    // mark past its declared [size].
    return Semantics(
      label: 'VisioSoil',
      image: true,
      child: Center(
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _VisioSoilLogoPainter(color)),
        ),
      ),
    );
  }
}

/// The mark's geometry in the design system's 48-unit viewBox: the lens ring,
/// three decreasing soil grains inside it, and the handle.
///
/// [paintVisioSoilMark] draws from it, and the Android launch drawable
/// `launch_mark.xml` is pinned against it (SPEC 0089), so the mark Flutter
/// paints and the one the native launch window draws cannot drift.
abstract final class VisioSoilMarkGeometry {
  static const double viewBox = 48;

  static const Offset ringCentre = Offset(20, 20);
  static const double ringRadius = 12.6;
  static const double ringStrokeWidth = 3.6;

  /// Largest first.
  static const List<({Offset centre, double radius})> grains = [
    (centre: Offset(16.2, 17.6), radius: 3.2),
    (centre: Offset(23.6, 19.2), radius: 2.2),
    (centre: Offset(19.4, 24.6), radius: 1.5),
  ];

  static const Offset handleStart = Offset(29.4, 29.4);
  static const Offset handleEnd = Offset(39.5, 39.5);
  static const double handleStrokeWidth = 4.0;
}

/// Paints the official VisioSoil mark in [color], scaled to fill [size], onto
/// [canvas]. Shared single source of truth for the geometry: the [VisioSoilLogo]
/// widget and the app-launcher-icon generator both draw through this routine so
/// the in-app mark and the icon can never drift.
void paintVisioSoilMark(Canvas canvas, Size size, Color color) {
  // Stroke widths and coordinates scale from the 48-unit viewBox.
  final s = size.width / VisioSoilMarkGeometry.viewBox;
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final fill = Paint()
    ..color = color
    ..style = PaintingStyle.fill;

  stroke.strokeWidth = VisioSoilMarkGeometry.ringStrokeWidth * s;
  canvas.drawCircle(
    VisioSoilMarkGeometry.ringCentre * s,
    VisioSoilMarkGeometry.ringRadius * s,
    stroke,
  );

  for (final grain in VisioSoilMarkGeometry.grains) {
    canvas.drawCircle(grain.centre * s, grain.radius * s, fill);
  }

  stroke.strokeWidth = VisioSoilMarkGeometry.handleStrokeWidth * s;
  canvas.drawLine(
    VisioSoilMarkGeometry.handleStart * s,
    VisioSoilMarkGeometry.handleEnd * s,
    stroke,
  );
}

class _VisioSoilLogoPainter extends CustomPainter {
  const _VisioSoilLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) =>
      paintVisioSoilMark(canvas, size, color);

  @override
  bool shouldRepaint(_VisioSoilLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
