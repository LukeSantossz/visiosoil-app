import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/soil_texture_colors.dart';

/// Static diagrams never schedule frames or emit settlement events.
enum TextureTriangleMode { static, processing }

/// An illustrative diagram, not a plot of measured sample fractions.
class TextureTriangle extends StatefulWidget {
  const TextureTriangle({
    super.key,
    this.highlightClass,
    this.mode = TextureTriangleMode.static,
    this.onSettled,
  });

  final String? highlightClass;
  final TextureTriangleMode mode;
  final VoidCallback? onSettled;

  @override
  State<TextureTriangle> createState() => _TextureTriangleState();
}

class _TextureTriangleState extends State<TextureTriangle>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2400);
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  )..addListener(_tick);
  bool _static = true;
  bool _configured = false;
  bool _settled = false;
  int _generation = 0;
  _TrianglePainter? _painter;
  Object? _painterInputs;
  bool _completed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(TextureTriangle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightClass != widget.highlightClass ||
        oldWidget.mode != widget.mode) {
      _configure(restart: true);
    } else {
      _configure();
    }
  }

  void _configure({bool restart = false}) {
    final static =
        widget.mode == TextureTriangleMode.static ||
        context.palette.isSun ||
        AppMotion.reduceMotion ||
        MediaQuery.disableAnimationsOf(context);
    if (!restart && _configured && _static == static) return;
    _configured = true;
    if (!restart && _completed) {
      _static = static;
      _controller.stop();
      return;
    }
    _static = static;
    if (restart) {
      _settled = false;
      _completed = false;
    }
    final generation = ++_generation;
    if (static) {
      _controller.stop();
      _controller.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) {
          _notifySettled();
          _complete();
        }
      });
    } else {
      _controller.forward(from: 0);
    }
  }

  void _tick() {
    if (_static) return;
    if (_controller.value >= 2100 / 2400) _notifySettled();
    if (_controller.isCompleted) _complete();
  }

  void _notifySettled() {
    if (_settled ||
        widget.highlightClass == null ||
        widget.mode != TextureTriangleMode.processing) {
      return;
    }
    setState(() => _settled = true);
    unawaited(AppHaptics.confirm());
  }

  void _complete() {
    if (_completed ||
        widget.highlightClass == null ||
        widget.mode != TextureTriangleMode.processing) {
      return;
    }
    _completed = true;
    widget.onSettled?.call();
  }

  @override
  void dispose() {
    _painter?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.highlightClass;
    return Semantics(
      label: label == null || (!_static && !_settled)
          ? 'Diagrama do triângulo textural'
          : 'Diagrama do triângulo textural, classe $label destacada',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = math.min(constraints.maxWidth, 300.0);
            final palette = context.palette;
            final textStyle = Theme.of(context).textTheme.bodySmall!;
            final textScaler = MediaQuery.textScalerOf(context);
            final inputs = (
              side,
              palette,
              label,
              widget.mode,
              _static,
              textStyle,
              textScaler,
            );
            if (_painterInputs != inputs) {
              _painter?.dispose();
              _painter = _TrianglePainter(
                animation: _controller,
                palette: palette,
                textureClass: label,
                static: _static,
                side: side,
                textStyle: textStyle,
                textScaler: textScaler,
              );
              _painterInputs = inputs;
            }
            return SizedBox(
              width: side,
              height: side * .82,
              child: CustomPaint(painter: _painter),
            );
          },
        ),
      ),
    );
  }
}

/// Geometry, text layouts, paths, intervals and paints are prepared once per
/// layout/theme/class change. The frame loop only updates scalar coordinates.
class _TrianglePainter extends CustomPainter {
  _TrianglePainter({
    required this.animation,
    required this.palette,
    required String? textureClass,
    required this.static,
    required double side,
    required TextStyle textStyle,
    required TextScaler textScaler,
  }) : super(repaint: animation) {
    final region = textureClass == null
        ? null
        : SoilTextureColors.regionForClass(textureClass);
    _hasClass = region != null;
    final vertices = _regions[region ?? SoilTextureRegion.medium]!;
    _region = _polygon(vertices);
    _outline = _polygon(const [
      Offset(150, 25),
      Offset(65, 180),
      Offset(235, 180),
    ]);
    _lines = Path();
    for (final points in _divisions) {
      _lines.moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        _lines.lineTo(points[i].dx, points[i].dy);
      }
    }
    _edge = Paint()
      ..color = palette.isSun ? palette.outline : palette.primaryText
      ..style = PaintingStyle.stroke
      ..strokeWidth = palette.isSun ? 3 : 2.5
      ..strokeJoin = StrokeJoin.round;
    _grid = Paint()
      ..color = palette.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = palette.isSun ? 1.4 : 1;
    _fill = Paint()..color = palette.primary;
    _grain = Paint()
      ..color = textureClass == null
          ? palette.secondary
          : SoilTextureColors.forClass(textureClass);
    _scale = side / 300;
    final random = math.Random(193);
    final bounds = _region.getBounds();
    _particles = List.generate(26, (index) {
      late Offset target;
      do {
        target = Offset(
          bounds.left + random.nextDouble() * bounds.width,
          bounds.top + random.nextDouble() * bounds.height,
        );
      } while (!_region.contains(target));
      final radius = 1 + random.nextDouble();
      final shape = Path()
        ..moveTo(-radius, 0)
        ..lineTo(-radius * .4, -radius)
        ..lineTo(radius, -radius * .4)
        ..lineTo(radius * .7, radius)
        ..lineTo(-radius * .5, radius * .8)
        ..close();
      return _Particle(
        target.dx,
        target.dy,
        target.dx + (random.nextDouble() - .5) * 90,
        -random.nextDouble() * 45,
        radius,
        shape,
        Interval(
          (390 + index * 28) / 2400,
          (390 + index * 28 + 760) / 2400,
          curve: AppMotion.emphasizedDecelerate,
        ),
      );
    });
    _labels = [
      for (final label in ['Argila', 'Areia', 'Silte'])
        TextPainter(
          text: TextSpan(
            text: label,
            style: textStyle.copyWith(
              color: palette.isSun ? palette.onSurface : palette.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout(),
    ];
    _labelOffsets = [
      Offset(150 * _scale - _labels[0].width / 2, 0),
      Offset(60 * _scale, 190 * _scale),
      Offset(240 * _scale - _labels[2].width, 190 * _scale),
    ];
    _grainColors = List.generate(
      281,
      (index) => _grain.color.withValues(
        alpha: 1 - AppMotion.standardAccelerate.transform(index / 280),
      ),
    );
  }

  final AnimationController animation;
  final AppPalette palette;
  final bool static;
  late final bool _hasClass;
  late final Path _region, _outline, _lines;
  late final Paint _edge, _grid, _fill, _grain;
  late final double _scale;
  late final List<_Particle> _particles;
  late final List<TextPainter> _labels;
  late final List<Offset> _labelOffsets;
  late final List<Color> _grainColors;

  static Path _polygon(List<Offset> points) => Path()..addPolygon(points, true);

  // Approximate USDA/SBCS silhouette, deliberately without fraction axes.
  static const _regions = {
    SoilTextureRegion.veryClay: [
      Offset(150, 25),
      Offset(116, 87),
      Offset(184, 87),
    ],
    SoilTextureRegion.clay: [
      Offset(116, 87),
      Offset(184, 87),
      Offset(201, 118),
      Offset(99, 118),
    ],
    SoilTextureRegion.medium: [
      Offset(124, 118),
      Offset(167, 118),
      Offset(178, 139),
      Offset(135, 139),
    ],
    SoilTextureRegion.sand: [
      Offset(80, 153),
      Offset(129, 153),
      Offset(145, 180),
      Offset(65, 180),
    ],
    SoilTextureRegion.silt: [
      Offset(178, 139),
      Offset(212, 139),
      Offset(235, 180),
      Offset(151, 180),
    ],
  };
  static const _divisions = [
    [Offset(112, 96), Offset(124, 118), Offset(167, 118), Offset(184, 87)],
    [Offset(94, 126), Offset(124, 126)],
    [Offset(124, 118), Offset(135, 139), Offset(212, 139)],
    [Offset(80, 149), Offset(129, 149), Offset(135, 139)],
    [Offset(129, 149), Offset(140, 169), Offset(155, 169)],
    [Offset(174, 139), Offset(151, 180)],
    [Offset(222, 161), Offset(211, 161), Offset(201, 180)],
    [Offset(78, 156), Offset(115, 180)],
    [Offset(74, 164), Offset(90, 180)],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(_scale);
    canvas.drawPath(_lines, _grid);
    final time = static ? 2400.0 : animation.value * 2400;
    if (_hasClass && time >= 2100) {
      final pulse = static || animation.isCompleted
          ? 1.0
          : 1 + .04 * math.sin(((time - 2100) / 360).clamp(0, 1) * math.pi);
      canvas.save();
      // Pulse around the region, not around the canvas origin.
      canvas.translate(150, 120);
      canvas.scale(pulse);
      canvas.translate(-150, -120);
      canvas.drawPath(_region, _fill);
      canvas.restore();
    }
    canvas.drawPath(_outline, _edge);
    if (!static && time < 2380) {
      _grain.color = _grainColors[(time - 2100).clamp(0, 280).toInt()];
      for (var i = 0; i < _particles.length; i++) {
        if (time < 390 + i * 28) continue;
        final grain = _particles[i];
        final progress = grain.interval.transform(animation.value);
        final x = grain.startX + (grain.x - grain.startX) * progress;
        final y = grain.startY + (grain.y - grain.startY) * progress;
        canvas.save();
        canvas.translate(x, y);
        if (i.isEven) {
          canvas.drawCircle(Offset.zero, grain.radius, _grain);
        } else {
          canvas.drawPath(grain.shape, _grain);
        }
        canvas.restore();
      }
    }
    canvas.restore();
    for (var i = 0; i < _labels.length; i++) {
      _labels[i].paint(canvas, _labelOffsets[i]);
    }
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) => true;

  void dispose() {
    for (final label in _labels) {
      label.dispose();
    }
  }
}

class _Particle {
  const _Particle(
    this.x,
    this.y,
    this.startX,
    this.startY,
    this.radius,
    this.shape,
    this.interval,
  );
  final double x, y, startX, startY, radius;
  final Path shape;
  final Interval interval;
}
