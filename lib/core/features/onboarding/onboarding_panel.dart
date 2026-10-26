import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/features/capture/widgets/texture_triangle.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';

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
    final inset = MediaQuery.paddingOf(context).top;
    final height = 376 + inset;
    final width = MediaQuery.sizeOf(context).width;
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
          // The art sits on a 200 × 180 dp canvas whose top left is 100 dp
          // left of the panel's centre and 76 dp under the safe area, so each
          // drawing keeps the coordinates measured on the mocks (SPEC 0206).
          if (art == OnboardingArt.triangle)
            Positioned(
              left: width / 2 - 100 + _triangleOffset.dx,
              top: inset + 76 + _triangleOffset.dy,
              width: _triangleWidth,
              child: const ExcludeSemantics(
                child: TextureTriangle(
                  highlightClass: SoilTextureColors.exampleClass,
                ),
              ),
            )
          else
            Positioned(
              left: width / 2 - 100,
              top: inset + 76,
              width: 200,
              height: 180,
              child: ExcludeSemantics(child: _art(palette)),
            ),
        ],
      ),
    );
  }

  /// Where the triangle's widget sits on the canvas, and how wide, so its
  /// outline spans 26.75 to 172.75 dp with the apex at 15.75 dp, as PNG 06
  /// draws it: the widget draws its outline from 65 to 235 of 300 units.
  static const double _triangleWidth = 146 / 170 * 300;
  static const Offset _triangleOffset = Offset(
    26.75 - 65 * 146 / 170,
    15.75 - 25 * 146 / 170,
  );

  Widget _art(AppPalette palette) {
    final (fill, ink) = artColors(palette);
    return CustomPaint(
      size: const Size(200, 180),
      painter: _ArtPainter(
        art: art,
        ink: ink,
        fill: fill,
        squareFill: palette.highContrast
            ? fill
            : palette.primaryContainer.withValues(alpha: .7),
        ring: palette.highContrast ? ink : palette.textTertiary,
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

/// The steps' line art, in the canvas coordinates measured on PNG 02 to 07
/// (SPEC 0206): fills at half `primaryContainer`, 2 dp strokes in
/// `primaryText`, the camera's outer ring in `textTertiary`, and the check
/// badge in `primary`.
class _ArtPainter extends CustomPainter {
  const _ArtPainter({
    required this.art,
    required this.ink,
    required this.fill,
    required this.squareFill,
    required this.ring,
    required this.badge,
  });

  final OnboardingArt art;
  final Color ink;
  final Color fill;
  final Color squareFill;
  final Color ring;
  final Color badge;

  Paint _stroke([double width = 2]) => Paint()
    ..color = ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = fill;

  Paint get _dot => Paint()..color = ink;

  void _shape(Canvas canvas, Path path) {
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke());
  }

  /// The mocks' cloud: three lobes over a flat base, fitted to [box] (the
  /// stroke's centre line).
  static Path cloud(Rect box) {
    final k = box.width / 106.5;
    Offset at(double x, double y) => box.topLeft + Offset(x * k, y * k);
    Path circle(double x, double y, double r) =>
        Path()..addOval(Rect.fromCircle(center: at(x, y), radius: r * k));
    var path = Path.combine(
      PathOperation.union,
      circle(26, 41.25, 26),
      circle(55.75, 27.25, 28),
    );
    path = Path.combine(PathOperation.union, path, circle(81.75, 42.25, 25));
    return Path.combine(
      PathOperation.union,
      path,
      Path()..addRect(Rect.fromPoints(at(26, 27.25), at(81.75, 67.25))),
    );
  }

  void _dashed(Canvas canvas, Path path) {
    final pen = _stroke(1.5)..strokeCap = StrokeCap.butt;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 7.5) {
        canvas.drawPath(metric.extractPath(d, d + 3), pen);
      }
    }
  }

  void _dots(Canvas canvas, List<(double, double, double)> dots) {
    for (final (x, y, r) in dots) {
      canvas.drawCircle(Offset(x, y), r, _dot);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    switch (art) {
      case OnboardingArt.account:
        _shape(
          canvas,
          Path()..addRRect(
            RRect.fromLTRBR(
              33.75,
              51.75,
              82.75,
              140.75,
              const Radius.circular(8),
            ),
          ),
        );
        _dots(canvas, const [
          (50.75, 85.5, 3.25),
          (64.75, 89.75, 2.25),
          (56.25, 101.5, 1.75),
        ]);
        canvas.drawLine(
          const Offset(51.25, 130.25),
          const Offset(65.25, 130.25),
          _stroke(1.5),
        );
        _shape(
          canvas,
          cloud(const Rect.fromLTRB(104.25, 57.25, 174.75, 102.25)),
        );
        _dashed(
          canvas,
          Path()
            ..moveTo(88, 67)
            ..quadraticBezierTo(106, 40, 124, 63),
        );
        _dashed(
          canvas,
          Path()
            ..moveTo(127, 116)
            ..quadraticBezierTo(106, 144, 88, 126),
        );
        _dots(canvas, const [(86, 72.75, 3), (127.25, 115.25, 2.75)]);
      case OnboardingArt.linked:
        _shape(canvas, cloud(const Rect.fromLTRB(46.25, 52.75, 152.75, 120)));
        canvas.drawPath(
          Path()
            ..moveTo(87.25, 95.75)
            ..lineTo(95.75, 104.25)
            ..lineTo(114.25, 85.75),
          _stroke(),
        );
      case OnboardingArt.photograph:
        canvas.drawRRect(
          RRect.fromLTRBR(52.5, 42.5, 147.5, 137.5, const Radius.circular(12)),
          Paint()..color = squareFill,
        );
        final corners = _stroke()
          ..strokeCap = StrokeCap.square
          ..strokeJoin = StrokeJoin.miter;
        const box = Rect.fromLTRB(40.25, 30.25, 159.25, 149.25);
        for (final (corner, dx, dy) in [
          (box.topLeft, 1.0, 1.0),
          (box.topRight, -1.0, 1.0),
          (box.bottomLeft, 1.0, -1.0),
          (box.bottomRight, -1.0, -1.0),
        ]) {
          canvas.drawPath(
            Path()
              ..moveTo(corner.dx, corner.dy + dy * 19)
              ..lineTo(corner.dx, corner.dy)
              ..lineTo(corner.dx + dx * 19, corner.dy),
            corners,
          );
        }
        _dots(canvas, const [
          (104.5, 68.25, 2.5),
          (76, 73.25, 4.25),
          (121.25, 85, 3.5),
          (90.25, 96.75, 2.25),
          (111.75, 108.75, 4.25),
          (78.5, 111, 3),
          (125.75, 115.75, 1.75),
        ]);
        canvas.drawCircle(const Offset(152, 142), 16, Paint()..color = badge);
        canvas.drawPath(
          Path()
            ..moveTo(145.25, 142.25)
            ..lineTo(150, 147)
            ..lineTo(158.75, 138.25),
          _stroke(2.5)..color = Colors.white,
        );
      case OnboardingArt.camera:
        _shape(
          canvas,
          Path.combine(
            PathOperation.union,
            Path()..addRRect(
              RRect.fromLTRBR(
                38.25,
                66.5,
                161.25,
                138.75,
                const Radius.circular(8),
              ),
            ),
            Path()..addPolygon(const [
              Offset(72.25, 67.5),
              Offset(80.75, 53.75),
              Offset(119.25, 53.75),
              Offset(127.75, 67.5),
            ], true),
          ),
        );
        canvas.drawCircle(
          const Offset(99.75, 100.25),
          31.5,
          _stroke(1.5)..color = ring,
        );
        canvas.drawCircle(const Offset(99.75, 100.25), 23.25, _stroke());
        _dots(canvas, const [
          (93.25, 96.25, 3.25),
          (105, 100.25, 2.5),
          (98.75, 108.75, 1.75),
        ]);
      case OnboardingArt.triangle:
        break;
    }
  }

  @override
  bool shouldRepaint(_ArtPainter oldDelegate) =>
      art != oldDelegate.art ||
      ink != oldDelegate.ink ||
      fill != oldDelegate.fill ||
      squareFill != oldDelegate.squareFill ||
      ring != oldDelegate.ring ||
      badge != oldDelegate.badge;
}
