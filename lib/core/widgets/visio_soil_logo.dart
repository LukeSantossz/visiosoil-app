import 'package:flutter/material.dart';

/// The official VisioSoil brand mark: a minimalist magnifying glass holding
/// three decreasing soil grains — vision and inspection fused with the texture
/// being measured.
///
/// Painted directly from the design system's canonical `assets/logo-mark.svg`
/// (viewBox `0 0 48 48`), so it needs no SVG runtime. [color] plays the role of
/// the SVG's `currentColor`, letting the mark sit on any background.
class VisioSoilLogo extends StatelessWidget {
  const VisioSoilLogo({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VisioSoil',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _VisioSoilLogoPainter(color)),
      ),
    );
  }
}

class _VisioSoilLogoPainter extends CustomPainter {
  const _VisioSoilLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Stroke widths and coordinates scale from the 48-unit viewBox.
    final s = size.width / 48.0;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // Lens ring.
    stroke.strokeWidth = 3.2 * s;
    canvas.drawCircle(Offset(20 * s, 20 * s), 13 * s, stroke);

    // Three decreasing soil grains inside the lens.
    canvas.drawCircle(Offset(16.5 * s, 18 * s), 3 * s, fill);
    canvas.drawCircle(Offset(23.5 * s, 19.5 * s), 2.1 * s, fill);
    canvas.drawCircle(Offset(19.5 * s, 24.5 * s), 1.4 * s, fill);

    // Handle.
    stroke.strokeWidth = 3.4 * s;
    canvas.drawLine(Offset(29.5 * s, 29.5 * s), Offset(39 * s, 39 * s), stroke);
  }

  @override
  bool shouldRepaint(_VisioSoilLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
