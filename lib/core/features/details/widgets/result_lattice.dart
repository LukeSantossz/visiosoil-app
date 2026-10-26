import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// The triangle grid behind the result's app bar (redesign v11 PNGs 14, 15,
/// 32, 33; SPEC 0202): an equilateral lattice with its apex at (260, -40) dp,
/// 35 dp sides and 30 dp rows, in 1 dp `primaryText` lines at 16.5 % down to
/// 110 dp that fade to nothing 250 dp down. Modo Sol draws none (PNG 26).
class ResultLattice extends StatelessWidget {
  const ResultLattice({super.key});

  /// How far down the lattice reaches; the date chip sits just below.
  static const double height = 250;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (palette.isSun) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            key: const ValueKey('result-lattice'),
            painter: _LatticePainter(palette.primaryText),
          ),
        ),
      ),
    );
  }
}

class _LatticePainter extends CustomPainter {
  const _LatticePainter(this.color);

  final Color color;

  static const Offset _apex = Offset(260, -40);
  static const double _side = 35;
  static const double _row = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.165),
          color.withValues(alpha: 0.165),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 110 / ResultLattice.height, 1],
      ).createShader(Offset.zero & Size(size.width, ResultLattice.height));
    final rows = ((ResultLattice.height - _apex.dy) / _row).ceil();
    final bottom = _apex.dy + rows * _row;
    final halfBase = rows * _side / 2;
    final left = Offset(_apex.dx - halfBase, bottom);
    final right = Offset(_apex.dx + halfBase, bottom);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Rows parallel to the base.
    for (var k = 1; k <= rows; k++) {
      final y = _apex.dy + k * _row;
      final half = k * _side / 2;
      canvas.drawLine(
        Offset(_apex.dx - half, y),
        Offset(_apex.dx + half, y),
        paint,
      );
    }
    // Lines parallel to each side, one per base step.
    for (var k = 0; k <= rows; k++) {
      final onBase = Offset(left.dx + k * _side, bottom);
      // Parallel to the right side: from the base up-left to the left side.
      final toLeft = Offset.lerp(left, _apex, k / rows)!;
      canvas.drawLine(onBase, toLeft, paint);
      // Parallel to the left side: from the base up-right to the right side.
      final toRight = Offset.lerp(right, _apex, (rows - k) / rows)!;
      canvas.drawLine(onBase, toRight, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LatticePainter old) => old.color != color;
}
