import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/theme/app_typography.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

/// Boot "Peneira" (redesign v11 §3.1, §6.2, SPEC 0193), timed and drawn as
/// the approved prototype's boot (SPEC 0217): a green circle opens from the
/// lens over the app background, a full-screen sieve of dots ripples out and
/// clears, the mark assembles, the name and tagline rise, and the boot slides
/// up and away as the screen beneath rises into place.
///
/// Replaces the native-launch-window-matching splash of SPEC 0089: the native
/// window draws the app background the boot now starts from.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The native Android launch window's logo tile edge, mark edge and corner
  /// radius, in logical pixels, shown before Flutter's first frame. The launch
  /// drawables are pinned to these (SPEC 0089).
  static const double logoTileSize = 120;
  static const double logoMarkSize = 64;
  static const double logoTileRadius = AppRadius.xl;

  /// When the boot routes on (SPEC 0217): the last dot has cleared and the
  /// tagline is in. Also the entrance controller's duration.
  static const Duration handOffAt = Duration(milliseconds: 1400);

  /// The hand-off: the curtain's 380 ms slide, and the target's 480 ms rise
  /// from 60 ms in.
  static const Duration handOffDuration = Duration(milliseconds: 540);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

/// What the boot passes as the route's `extra` when it routes on, so the
/// target's page knows to run the boot's own transition (SPEC 0217).
enum BootHandOff {
  /// The boot's last frame slides up while the target rises 48 dp.
  slide,

  /// No transition: reduced motion (§6.2, §6.5).
  cut,
}

/// The page for a route the boot routes on to. It runs the hand-off only
/// when the boot asked for it, through [BootHandOff]; any other arrival gets
/// the page GoRouter builds by default.
Page<void> bootHandOffPage(GoRouterState state, Widget child) {
  final handOff = state.extra;
  if (handOff is! BootHandOff) {
    return MaterialPage<void>(
      key: state.pageKey,
      name: state.name ?? state.path,
      restorationId: state.pageKey.value,
      child: child,
    );
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    name: state.name ?? state.path,
    restorationId: state.pageKey.value,
    transitionDuration: handOff == BootHandOff.slide
        ? SplashScreen.handOffDuration
        : Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Once in, the page answers routes pushed over it as every other page
      // does, through the theme's own transition.
      final settled = Theme.of(context).pageTransitionsTheme.buildTransitions(
        ModalRoute.of(context)! as PageRoute<void>,
        context,
        kAlwaysCompleteAnimation,
        secondaryAnimation,
        child,
      );
      return handOff == BootHandOff.slide
          ? _BootHandOffTransition(animation: animation, child: settled)
          : settled;
    },
    child: child,
  );
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Future<bool> _onboardingCompleted;

  bool _reduceMotion = false;
  bool _ready = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // Kicked off now, not awaited later: by the time the entrance completes
    // the result is already in hand, so routing adds no extra wait on top of
    // it (PR 14's "navigate no later than 1.6 s").
    _onboardingCompleted = ref
        .read(onboardingStoreProvider)
        .hasCompletedOnboarding();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _ready = true;

    _reduceMotion =
        AppMotion.reduceMotion || MediaQuery.disableAnimationsOf(context);

    _controller =
        AnimationController(
          vsync: this,
          duration: _reduceMotion
              ? AppMotion.reducedMotion
              : SplashScreen.handOffAt,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _goHome();
        });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Routes on, once — guarded against the status listener and [_skip] both
  /// firing, and against the awaited onboarding read outliving the widget.
  Future<void> _goHome() async {
    if (_navigated || !mounted) return;
    _navigated = true;
    final completed = await _onboardingCompleted;
    if (!mounted) return;
    context.go(
      completed ? '/' : '/onboarding',
      extra: _reduceMotion ? BootHandOff.cut : BootHandOff.slide,
    );
  }

  /// "Pular": ends the boot at once (§6.2), through the same hand-off.
  /// Stopping the controller first keeps its status listener from also
  /// firing [_goHome].
  void _skip() {
    _controller.stop();
    _goHome();
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return _buildReduced(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => _BootFrame(
        ms: _controller.value * SplashScreen.handOffAt.inMilliseconds,
        onSkip: _skip,
      ),
    );
  }

  /// Reduced motion (§6.2, §6.5): the static logo fades in over 150 ms on
  /// the green, with no sieve and no text.
  Widget _buildReduced(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.bootBackground,
      body: Stack(
        children: [
          if (!palette.isSun)
            const Positioned.fill(
              child: CustomPaint(
                key: Key('boot-contours'),
                painter: _BootContoursPainter(),
              ),
            ),
          _SkipButton(color: Colors.white, opacity: 1, onPressed: _skip),
          Center(
            child: FadeTransition(
              opacity: _controller,
              child: const VisioSoilLogo(size: 64, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// [curve] over the window [startMs] to [startMs] + [durationMs], at [ms].
double _phase(double ms, int startMs, int durationMs, Curve curve) =>
    curve.transform(((ms - startMs) / durationMs).clamp(0.0, 1.0));

/// The boot at [ms] into its timeline. With [showDots] off it is the
/// hand-off's curtain: the last frame without the sieve.
class _BootFrame extends StatelessWidget {
  const _BootFrame({
    super.key,
    required this.ms,
    this.onSkip,
    this.showDots = true,
  });

  final double ms;
  final VoidCallback? onSkip;
  final bool showDots;

  /// The mark's edge, and how far its top sits above the screen's centre.
  static const double markSize = 88;
  static const double markTopAboveCentre = 96;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);
    final reveal = _phase(ms, 0, 420, AppMotion.emphasizedDecelerate);
    final name = _phase(ms, 960, 300, AppMotion.standardDecelerate);
    final tagline = _phase(ms, 1040, 300, AppMotion.standardDecelerate);

    return Scaffold(
      backgroundColor: palette.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final markTop = size.height / 2 - markTopAboveCentre;
          final lens = Offset(size.width / 2, markTop + markSize / 2);
          return Stack(
            children: [
              Positioned.fill(
                child: ClipPath(
                  key: const Key('boot-reveal'),
                  clipper: _RevealClipper(centre: lens, progress: reveal),
                  child: ColoredBox(
                    key: const Key('boot-green'),
                    color: palette.bootBackground,
                    // Two clusters of contour rings (PNG 01, SPEC 0207);
                    // Modo Sol draws no decoration.
                    child: palette.isSun
                        ? const SizedBox.expand()
                        : const CustomPaint(
                            key: Key('boot-contours'),
                            painter: _BootContoursPainter(),
                            size: Size.infinite,
                          ),
                  ),
                ),
              ),
              if (showDots)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      key: const Key('boot-sieve'),
                      painter: _BootSievePainter(ms: ms, lens: lens),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                top: markTop,
                child: Column(
                  children: [
                    Semantics(
                      label: 'VisioSoil',
                      image: true,
                      child: CustomPaint(
                        key: const Key('boot-mark'),
                        size: const Size.square(markSize),
                        painter: _BootMarkPainter(ms: ms),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _Rise(
                      t: name,
                      child: Text(
                        'VisioSoil',
                        style: AppTypography.weighted(
                          theme.textTheme.headlineLarge!,
                          700,
                        ).copyWith(color: Colors.white, letterSpacing: -0.8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    _Rise(
                      t: tagline,
                      child: Text(
                        'Análise de textura do solo',
                        // Opaque, not a translucent white: against the
                        // boot's own green fills a 70 %-alpha white reads
                        // under 4.5 : 1 (SPEC 0133's contrast guideline).
                        style: AppTypography.resized(
                          theme.textTheme.bodyLarge!,
                          16,
                          height: 24 / 16,
                        ).copyWith(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              _SkipButton(
                color: Color.lerp(
                  palette.primaryText,
                  Colors.white,
                  _phase(ms, 180, 200, AppMotion.standard),
                )!,
                opacity: _phase(ms, 300, 200, AppMotion.standard),
                onPressed: onSkip ?? () {},
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Fades [child] in as it rises 8 dp, by [t].
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.child});

  final double t;
  final Widget child;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: t,
    child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
  );
}

/// "Pular", top right, with its 48 dp target (§6.2).
class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.color,
    required this.opacity,
    required this.onPressed,
  });

  final Color color;
  final double opacity;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Opacity(
            opacity: opacity,
            child: TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: color,
                minimumSize: const Size(48, 48),
              ),
              child: Text(
                'Pular',
                style: AppTypography.resized(
                  Theme.of(context).textTheme.labelLarge!,
                  17,
                ).copyWith(color: color, letterSpacing: 0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The distance from [point] to the farthest corner of [size].
double _farthestCorner(Size size, Offset point) => [
  Offset.zero,
  Offset(size.width, 0),
  Offset(0, size.height),
  Offset(size.width, size.height),
].map((corner) => (corner - point).distance).reduce(max);

/// The green's circle, about [centre], from nothing at [progress] 0 to the
/// screen's farthest corner at 1.
class _RevealClipper extends CustomClipper<Path> {
  const _RevealClipper({required this.centre, required this.progress});

  final Offset centre;
  final double progress;

  @override
  Path getClip(Size size) => Path()
    ..addOval(
      Rect.fromCircle(
        center: centre,
        radius: _farthestCorner(size, centre) * progress,
      ),
    );

  @override
  bool shouldReclip(_RevealClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.centre != centre;
}

/// The hand-off (SPEC 0217): the boot's last frame, without the sieve,
/// slides up by the screen's height while [child] rises from 48 dp below.
/// The curtain leaves the tree when the transition completes, and [child]
/// keeps its place in the stack, so its state is never rebuilt.
class _BootHandOffTransition extends StatelessWidget {
  const _BootHandOffTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = SplashScreen.handOffDuration.inMilliseconds;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final ms = animation.value * total;
        final rise = _phase(ms, 60, 480, AppMotion.emphasizedDecelerate);
        final lift = _phase(ms, 0, 380, AppMotion.emphasizedAccelerate);
        return Stack(
          children: [
            Transform.translate(
              offset: Offset(0, (1 - rise) * 48),
              child: child,
            ),
            if (!animation.isCompleted)
              FractionalTranslation(
                translation: Offset(0, -lift),
                child: IgnorePointer(
                  child: _BootFrame(
                    key: const Key('boot-curtain'),
                    ms: SplashScreen.handOffAt.inMilliseconds.toDouble(),
                    showDots: false,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The mark as it assembles (SPEC 0217): the three grains pop in, largest
/// first, then the ring draws from its leftmost point through the bottom,
/// then the handle. Once whole it is [paintVisioSoilMark]'s mark.
class _BootMarkPainter extends CustomPainter {
  const _BootMarkPainter({required this.ms});

  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final grains = [
      for (var i = 0; i < 3; i++)
        _phase(ms, 420 + i * 80, 300, AppMotion.emphasizedDecelerate),
    ];
    final ring = _phase(ms, 560, 420, AppMotion.emphasized);
    final handle = _phase(ms, 880, 180, AppMotion.standardDecelerate);
    if (ring == 1 && handle == 1 && grains.every((g) => g == 1)) {
      paintVisioSoilMark(canvas, size, Colors.white);
      return;
    }

    final s = size.width / VisioSoilMarkGeometry.viewBox;
    if (ring > 0) {
      canvas.drawArc(
        Rect.fromCircle(
          center: VisioSoilMarkGeometry.ringCentre * s,
          radius: VisioSoilMarkGeometry.ringRadius * s,
        ),
        pi,
        -2 * pi * ring,
        false,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = VisioSoilMarkGeometry.ringStrokeWidth * s,
      );
    }
    for (final (i, grain) in VisioSoilMarkGeometry.grains.indexed) {
      if (grains[i] <= 0) continue;
      canvas.drawCircle(
        grain.centre * s,
        grain.radius * s * grains[i],
        Paint()..color = Colors.white.withValues(alpha: grains[i]),
      );
    }
    if (handle > 0) {
      final start = VisioSoilMarkGeometry.handleStart * s;
      final end = VisioSoilMarkGeometry.handleEnd * s;
      canvas.drawLine(
        start,
        Offset.lerp(start, end, handle)!,
        Paint()
          ..color = Colors.white
          ..strokeCap = StrokeCap.round
          ..strokeWidth = VisioSoilMarkGeometry.handleStrokeWidth * s,
      );
    }
  }

  @override
  bool shouldRepaint(_BootMarkPainter oldDelegate) => oldDelegate.ms != ms;
}

/// Two clusters of irregular contour rings in white at 12 %, and a few dots,
/// as PNG 01 draws them (SPEC 0207).
class _BootContoursPainter extends CustomPainter {
  const _BootContoursPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = Colors.white.withValues(alpha: .12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (centre, rings, seed) in [
      (Offset(size.width * .77, size.height * .17), 12, 0.4),
      (Offset(size.width * .10, size.height * .90), 10, 1.7),
    ]) {
      for (var ring = 1; ring <= rings; ring++) {
        final radius = 16.0 + ring * 24;
        final path = Path();
        const points = 72;
        for (var i = 0; i <= points; i++) {
          final angle = i / points * 2 * pi;
          final wobble =
              1 +
              .09 * sin(3 * angle + seed + ring * .25) +
              .05 * sin(5 * angle + seed * 2);
          final point =
              centre +
              Offset(
                cos(angle) * radius * wobble,
                sin(angle) * radius * wobble * 1.1,
              );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path..close(), pen);
      }
    }
    final random = Random(207);
    final dot = Paint()..color = Colors.white.withValues(alpha: .15);
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
  bool shouldRepaint(_BootContoursPainter oldDelegate) => false;
}

/// The sieve (SPEC 0217): white dots on a 30 dp hexagonal grid in the mark's
/// three grain sizes, clear of the mark and its text, each rippling out from
/// [lens] — up to 22 %, a hold, then out — so none is left at the hand-off.
/// One painter for every dot, never a widget per dot.
class _BootSievePainter extends CustomPainter {
  const _BootSievePainter({required this.ms, required this.lens});

  final double ms;
  final Offset lens;

  static const double _pitch = 30;
  static const List<double> _radii = [4.8, 3.4, 2.2];

  @override
  void paint(Canvas canvas, Size size) {
    final farthest = _farthestCorner(size, lens);
    final dot = Paint();
    for (var row = 0; row * _pitch < size.height + _pitch; row++) {
      for (var col = 0; (col - .5) * _pitch < size.width + _pitch; col++) {
        final centre = Offset(
          col * _pitch + (row.isOdd ? _pitch / 2 : 0) - _pitch / 4,
          row * _pitch + _pitch / 2,
        );
        final d = centre - lens;
        // The mark and its text's space: no dot falls inside this ellipse.
        if (Offset(.8 * d.dx, d.dy - 40).distance < 120) continue;
        final p = _phase(
          ms,
          (120 + 380 * min(1, d.distance / farthest)).round(),
          900,
          AppMotion.standard,
        );
        if (p <= 0 || p >= 1) continue;
        final double scale;
        final double alpha;
        if (p < .35) {
          scale = p / .35;
          alpha = .22 * scale;
        } else if (p < .7) {
          scale = 1;
          alpha = .22;
        } else {
          final out = (p - .7) / .3;
          scale = 1 - .6 * out;
          alpha = .22 * (1 - out);
        }
        dot.color = Colors.white.withValues(alpha: alpha);
        canvas.drawCircle(centre, _radii[(row + col * 2) % 3] * scale, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_BootSievePainter oldDelegate) =>
      oldDelegate.ms != ms || oldDelegate.lens != lens;
}
