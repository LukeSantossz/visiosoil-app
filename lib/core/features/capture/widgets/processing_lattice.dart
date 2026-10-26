import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// The large texture triangle ruled at 10 % that PNG 13 draws behind the
/// processing screen's bar and triangle (SPEC 0211). Modo Sol draws none,
/// as it draws no decoration.
class ProcessingLattice extends StatelessWidget {
  const ProcessingLattice({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (palette.isSun) return const SizedBox.shrink();
    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(
          painter: _LatticePainter(
            // The strength that gives PNG 13's #D9E2D9 on its background.
            Color.lerp(palette.background, palette.primary, 0.18)!,
          ),
        ),
      ),
    );
  }
}

class _LatticePainter extends CustomPainter {
  _LatticePainter(this.colour);

  final Color colour;

  static const double _side = 346.4;
  static const double _apexFromRight = 130.25;
  static const double _apexY = -41.6;
  static const double _fadeFrom = 105;
  static const double _fadeTo = 257;

  @override
  void paint(Canvas canvas, Size size) {
    final apex = Offset(size.width - _apexFromRight, _apexY);
    final height = _side * math.sqrt(3) / 2;
    final left = apex + Offset(-_side / 2, height);
    final right = apex + Offset(_side / 2, height);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = ui.Gradient.linear(
        const Offset(0, _fadeFrom),
        const Offset(0, _fadeTo),
        [colour, colour.withValues(alpha: 0)],
      );
    Offset along(Offset a, Offset b, double t) => Offset.lerp(a, b, t)!;
    final path = Path();
    for (var i = 0; i <= 10; i++) {
      final t = i / 10;
      // One line of each direction per tenth, edge to edge.
      final rows = [
        (along(apex, left, t), along(apex, right, t)),
        (along(left, apex, t), along(left, right, t)),
        (along(right, apex, t), along(right, left, t)),
      ];
      for (final (a, b) in rows) {
        path
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LatticePainter oldDelegate) =>
      oldDelegate.colour != colour;
}
