import 'package:flutter/material.dart';

/// Decorative Google mark; the adjacent button label names the provider.
class GoogleGLogo extends StatelessWidget {
  const GoogleGLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: const _GoogleGPainter(),
    ),
  );
}

class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final blue = Path()
      ..moveTo(21.6, 12.23)
      ..cubicTo(21.6, 11.52, 21.54, 10.84, 21.42, 10.18)
      ..lineTo(12, 10.18)
      ..lineTo(12, 14.06)
      ..lineTo(17.38, 14.06)
      ..cubicTo(17.15, 15.31, 16.44, 16.37, 15.38, 17.08)
      ..lineTo(15.38, 19.6)
      ..lineTo(18.62, 19.6)
      ..cubicTo(20.51, 17.86, 21.6, 15.3, 21.6, 12.23)
      ..close();
    final green = Path()
      ..moveTo(12, 22)
      ..cubicTo(14.7, 22, 16.96, 21.1, 18.62, 19.6)
      ..lineTo(15.38, 17.08)
      ..cubicTo(14.48, 17.68, 13.33, 18.04, 12, 18.04)
      ..cubicTo(9.4, 18.04, 7.2, 16.28, 6.41, 13.91)
      ..lineTo(3.06, 13.91)
      ..lineTo(3.06, 16.5)
      ..cubicTo(4.71, 19.76, 8.09, 22, 12, 22)
      ..close();
    final yellow = Path()
      ..moveTo(6.41, 13.91)
      ..cubicTo(6.21, 13.31, 6.09, 12.67, 6.09, 12)
      ..cubicTo(6.09, 11.33, 6.21, 10.69, 6.41, 10.09)
      ..lineTo(6.41, 7.5)
      ..lineTo(3.06, 7.5)
      ..cubicTo(2.38, 8.85, 2, 10.38, 2, 12)
      ..cubicTo(2, 13.62, 2.38, 15.15, 3.06, 16.5)
      ..close();
    final red = Path()
      ..moveTo(12, 5.96)
      ..cubicTo(13.47, 5.96, 14.79, 6.47, 15.82, 7.47)
      ..lineTo(18.69, 4.6)
      ..cubicTo(16.96, 2.98, 14.7, 2, 12, 2)
      ..cubicTo(8.09, 2, 4.71, 4.24, 3.06, 7.5)
      ..lineTo(6.41, 10.09)
      ..cubicTo(7.2, 7.72, 9.4, 5.96, 12, 5.96)
      ..close();
    for (final (path, color) in [
      (blue, const Color(0xFF4285F4)),
      (green, const Color(0xFF34A853)),
      (yellow, const Color(0xFFFBBC05)),
      (red, const Color(0xFFEA4335)),
    ]) {
      canvas.drawPath(path, Paint()..color = color);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GoogleGPainter oldDelegate) => false;
}
