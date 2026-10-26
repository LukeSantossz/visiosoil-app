import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';

/// What a step's panel draws (PNG 02 to 07, SPEC 0206).
enum OnboardingArt { account, linked, photograph, triangle, camera }

/// The onboarding's top panel: `surfaceContainer` from the top of the screen,
/// behind the status bar, to 376 dp under the safe area, crossed by contour
/// lines around the step's line art (SPEC 0206). Modo Sol draws it white,
/// without contours, over a black rule.
class OnboardingPanel extends StatelessWidget {
  const OnboardingPanel({super.key, required this.art});

  final OnboardingArt art;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final sun = palette.isSun;
    final height = 376 + MediaQuery.paddingOf(context).top;
    return Container(
      key: const Key('onboarding-panel'),
      height: height,
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: sun ? palette.background : palette.surfaceContainer,
        border: sun
            ? const Border(bottom: BorderSide(color: Colors.black, width: 2))
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!sun)
            CustomPaint(
              key: const Key('onboarding-contours'),
              painter: _ContoursPainter(
                palette.primaryText.withValues(alpha: .17),
              ),
            ),
          Align(
            // The art sits a little under the panel's middle, as the mocks
            // place it.
            alignment: const Alignment(0, 0.03),
            child: ExcludeSemantics(child: _art(palette)),
          ),
        ],
      ),
    );
  }

  Widget _art(AppPalette palette) {
    if (art == OnboardingArt.triangle) {
      return const SizedBox(
        width: 150,
        child: TextureTriangle(highlightClass: 'Média'),
      );
    }
    final (fill, ink) = artColors(palette);
    return CustomPaint(
      size: const Size(160, 124),
      painter: _ArtPainter(
        art: art,
        ink: ink,
        fill: fill,
        badge: palette.primary,
      ),
    );
  }

  /// The art's fill and ink: half `primaryContainer` under `primaryText`;
  /// in high contrast the container solid under its own ink, as the discs
  /// it replaces were (SPEC 0139).
  static (Color fill, Color ink) artColors(AppPalette palette) =>
      palette.highContrast
      ? (palette.primaryContainer, palette.onPrimaryContainer)
      : (palette.primaryContainer.withValues(alpha: .5), palette.primaryText);
}

/// About twenty irregular rings around the art, and a few dots.
class _ContoursPainter extends CustomPainter {
  const _ContoursPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final centre = Offset(size.width * .55, size.height * .55);
    for (var ring = 1; ring <= 20; ring++) {
      final radius = 18.0 + ring * 17;
      final path = Path();
      const points = 72;
      for (var i = 0; i <= points; i++) {
        final angle = i / points * 2 * math.pi;
        final wobble =
            1 +
            .07 * math.sin(3 * angle + ring * .35) +
            .04 * math.sin(5 * angle + 1.3 + ring * .2);
        final point =
            centre +
            Offset(
              math.cos(angle) * radius * wobble * 1.08,
              math.sin(angle) * radius * wobble * .92,
            );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path..close(), pen);
    }
    final random = math.Random(206);
    final dot = Paint()..color = color;
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(
        Offset(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
        ),
        2,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(_ContoursPainter oldDelegate) =>
      color != oldDelegate.color;
}

/// The steps' line art: fills at half `primaryContainer`, 2 dp strokes in
/// `primaryText`, and the check badge in `primary`.
class _ArtPainter extends CustomPainter {
  const _ArtPainter({
    required this.art,
    required this.ink,
    required this.fill,
    required this.badge,
  });

  final OnboardingArt art;
  final Color ink;
  final Color fill;
  final Color badge;

  Paint get _stroke => Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = fill;

  Paint get _dot => Paint()..color = ink;

  void _shape(Canvas canvas, Path path) {
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
  }

  Path _cloud(Rect box) {
    final w = box.width;
    final h = box.height;
    final path = Path()
      ..moveTo(box.left + w * .22, box.bottom)
      ..arcToPoint(
        Offset(box.left + w * .22, box.top + h * .38),
        radius: Radius.circular(h * .31),
      )
      ..arcToPoint(
        Offset(box.left + w * .78, box.top + h * .4),
        radius: Radius.circular(w * .3),
      )
      ..arcToPoint(
        Offset(box.left + w * .78, box.bottom),
        radius: Radius.circular(h * .3),
      )
      ..close();
    return path;
  }

  void _dashed(Canvas canvas, Path path) {
    final pen = _stroke..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7) {
        canvas.drawPath(metric.extractPath(d, d + 3.5), pen);
      }
    }
  }

  void _check(Canvas canvas, Offset centre, double size, Paint pen) {
    canvas.drawPath(
      Path()
        ..moveTo(centre.dx - size * .5, centre.dy)
        ..lineTo(centre.dx - size * .12, centre.dy + size * .38)
        ..lineTo(centre.dx + size * .55, centre.dy - size * .35),
      pen,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (art) {
      case OnboardingArt.account:
        final phone = RRect.fromRectAndRadius(
          const Rect.fromLTWH(8, 14, 50, 92),
          const Radius.circular(8),
        );
        _shape(canvas, Path()..addRRect(phone));
        canvas.drawCircle(const Offset(26, 46), 3, _dot);
        canvas.drawCircle(const Offset(37, 54), 3, _dot);
        canvas.drawLine(const Offset(25, 92), const Offset(41, 92), _stroke);
        _shape(canvas, _cloud(const Rect.fromLTWH(78, 8, 76, 52)));
        _dashed(
          canvas,
          Path()
            ..moveTo(60, 28)
            ..quadraticBezierTo(68, 6, 90, 14),
        );
        _dashed(
          canvas,
          Path()
            ..moveTo(112, 64)
            ..quadraticBezierTo(104, 100, 60, 96),
        );
        canvas.drawCircle(const Offset(60, 28), 3, _dot);
        canvas.drawCircle(const Offset(112, 64), 3, _dot);
      case OnboardingArt.linked:
        _shape(canvas, _cloud(const Rect.fromLTWH(26, 14, 108, 70)));
        _check(canvas, const Offset(80, 56), 30, _stroke);
      case OnboardingArt.photograph:
        const box = Rect.fromLTWH(20, 0, 120, 120);
        final corners = _stroke..strokeWidth = 2.5;
        for (final (corner, dx, dy) in [
          (box.topLeft, 1.0, 1.0),
          (box.topRight, -1.0, 1.0),
          (box.bottomLeft, 1.0, -1.0),
          (box.bottomRight, -1.0, -1.0),
        ]) {
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx, corner.dy + dy * 20)
              ..lineTo(corner.dx, corner.dy)
              ..lineTo(corner.dx + dx * 20, corner.dy),
            corners,
          );
        }
        canvas.drawRRect(
          RRect.fromRectAndRadius(box.deflate(14), const Radius.circular(8)),
          _fill,
        );
        for (final dot in const [
          Offset(56, 36),
          Offset(84, 30),
          Offset(100, 46),
          Offset(72, 58),
          Offset(58, 76),
          Offset(92, 72),
          Offset(104, 86),
        ]) {
          canvas.drawCircle(dot, 3.5, _dot);
        }
        canvas.drawCircle(const Offset(136, 110), 16, Paint()..color = badge);
        _check(
          canvas,
          const Offset(136, 110),
          14,
          _stroke
            ..color = Colors.white
            ..strokeWidth = 2.5,
        );
      case OnboardingArt.camera:
        _shape(
          canvas,
          Path()..addRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(18, 24, 124, 86),
              const Radius.circular(10),
            ),
          ),
        );
        canvas.drawPath(
          Path()
            ..moveTo(52, 24)
            ..lineTo(58, 12)
            ..lineTo(102, 12)
            ..lineTo(108, 24),
          _stroke,
        );
        canvas.drawCircle(const Offset(80, 67), 30, _stroke);
        canvas.drawCircle(const Offset(80, 67), 22, _stroke);
        canvas.drawCircle(const Offset(75, 62), 3.5, _dot);
        canvas.drawCircle(const Offset(86, 64), 3.5, _dot);
        canvas.drawCircle(const Offset(80, 74), 3.5, _dot);
      case OnboardingArt.triangle:
        break;
    }
  }

  @override
  bool shouldRepaint(_ArtPainter oldDelegate) =>
      art != oldDelegate.art ||
      ink != oldDelegate.ink ||
      fill != oldDelegate.fill ||
      badge != oldDelegate.badge;
}
