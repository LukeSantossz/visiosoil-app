import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

/// Boot "Peneira" (redesign v11 §3.1, §6.2, SPEC 0193): a full-screen green
/// entrance — a sieve mesh with grains falling and settling behind the brand
/// mark — that hands off to Home with a [Hero] flight of the logo.
///
/// Replaces the native-launch-window-matching splash of SPEC 0089: that
/// design kept a static tile in place through the hand-over so nothing about
/// the mark ever moved; this one is an immersive entrance where the mesh,
/// the grains and the logo itself all animate in, which SPEC 0089's matching
/// native tile can no longer track (see SPEC 0193's Risks and Assumptions).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The native Android launch window's logo tile edge, mark edge and corner
  /// radius, in logical pixels, shown before Flutter's first frame. The launch
  /// drawables are pinned to these (SPEC 0089); the boot screen takes over
  /// from that window (SPEC 0193).
  static const double logoTileSize = 120;
  static const double logoMarkSize = 64;
  static const double logoTileRadius = AppRadius.xl;

  /// Total time the boot holds the screen before routing on: §6.2's "Em
  /// 1,2 s, Hero do logo até a Home". Also [AnimationController.duration] for
  /// the entrance, so the hand-off is exactly when the entrance completes.
  static const Duration heroDelay = Duration(milliseconds: 1200);

  /// The mesh's fade + scale .96→1 (§6.2 step 1).
  static const Duration meshDuration = Duration(milliseconds: 250);

  /// Each grain's fall-and-settle (§6.2 step 2).
  static const Duration grainDuration = Duration(milliseconds: 760);

  /// The stagger between one grain's start and the next's (§6.2 step 2).
  static const Duration grainStagger = Duration(milliseconds: 20);

  /// How many grains fall. Chosen so the last one's window — (count − 1) ×
  /// [grainStagger] to that plus [grainDuration] — still fits inside
  /// [heroDelay] (380 ms–1140 ms) without the per-grain [Interval] clamping.
  static const int grainCount = 20;

  /// Pre-generates grain positions reproducibly (no device-seeded [Random]),
  /// as the no-widget-per-grain [CustomPainter] approach requires.
  static const int grainSeed = 42;

  /// The logo + name's rise + fade (§6.2 step 3).
  static const Duration logoDuration = Duration(milliseconds: 250);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Future<bool> _onboardingCompleted;

  bool _reduceMotion = false;
  bool _ready = false;
  bool _navigated = false;
  List<_Grain> _grains = const [];
  late Interval _meshInterval;
  late Interval _logoInterval;

  @override
  void initState() {
    super.initState();
    // Kicked off now, not awaited later: by the time the 1.2 s entrance
    // completes the result is already in hand, so routing adds no extra
    // wait on top of it (PR 14's "navigate no later than 1.6 s").
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
              : SplashScreen.heroDelay,
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _goHome();
        });

    if (!_reduceMotion) {
      final totalMs = SplashScreen.heroDelay.inMilliseconds;
      _meshInterval = Interval(
        0,
        SplashScreen.meshDuration.inMilliseconds / totalMs,
        curve: AppMotion.emphasizedDecelerate,
      );
      final logoStartMs = SplashScreen.meshDuration.inMilliseconds;
      _logoInterval = Interval(
        logoStartMs / totalMs,
        (logoStartMs + SplashScreen.logoDuration.inMilliseconds) / totalMs,
        curve: AppMotion.standardDecelerate,
      );
      _grains = _generateGrains(totalMs);
    }

    _controller.forward();
  }

  static List<_Grain> _generateGrains(int totalMs) {
    final random = Random(SplashScreen.grainSeed);
    return List.generate(SplashScreen.grainCount, (i) {
      // Uniform scatter inside the mesh's circle (sqrt of a uniform radius
      // fraction avoids the centre-heavy clustering a bare random radius
      // gives), inset from the rim so no grain settles on top of it.
      final angle = random.nextDouble() * 2 * pi;
      final r = sqrt(random.nextDouble()) * 0.85;
      final startMs = i * SplashScreen.grainStagger.inMilliseconds;
      final endMs = startMs + SplashScreen.grainDuration.inMilliseconds;
      return _Grain(
        dxOffset: cos(angle) * r,
        restDyOffset: sin(angle) * r,
        radius: 1.4 + random.nextDouble() * 1.8,
        interval: Interval(
          startMs / totalMs,
          endMs / totalMs,
          curve: AppMotion.emphasizedDecelerate,
        ),
      );
    });
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
    context.go(completed ? '/' : '/onboarding');
  }

  /// "Pular": ends the boot at once (§6.2). Stopping the controller first
  /// keeps its status listener from also firing [_goHome].
  void _skip() {
    _controller.stop();
    _goHome();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.bootBackground,
      body: Stack(
        children: [
          if (!_reduceMotion)
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => CustomPaint(
                    painter: _BootSievePainter(
                      progress: _controller.value,
                      meshInterval: _meshInterval,
                      grains: _grains,
                    ),
                  ),
                ),
              ),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: TextButton(
                  onPressed: _skip,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                  child: const Text('Pular'),
                ),
              ),
            ),
          ),
          Center(
            child: _reduceMotion
                ? FadeTransition(
                    opacity: _controller,
                    child: const HeroMode(
                      enabled: false,
                      child: Hero(
                        tag: visioSoilLogoHeroTag,
                        child: VisioSoilLogo(size: 64, color: Colors.white),
                      ),
                    ),
                  )
                : AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final t = _logoInterval.transform(
                        _controller.value.clamp(0.0, 1.0),
                      );
                      return Opacity(
                        opacity: t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 8),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Hero(
                          tag: visioSoilLogoHeroTag,
                          child: VisioSoilLogo(size: 64, color: Colors.white),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'VisioSoil',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Análise de textura do solo',
                          // Opaque, not a translucent white: against the
                          // boot's own green fills a 70 %-alpha white reads
                          // under 4.5 : 1 (SPEC 0133's contrast guideline).
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// A single grain's pre-generated fall, relative to the mesh's centre and
/// radius so it scales with screen size: [dxOffset]/[restDyOffset] are
/// fractions of the mesh radius (both within ±0.85, inset from the rim), and
/// [interval] is this grain's staggered window within the boot's 0..1
/// progress.
@immutable
class _Grain {
  const _Grain({
    required this.dxOffset,
    required this.restDyOffset,
    required this.radius,
    required this.interval,
  });

  final double dxOffset;
  final double restDyOffset;
  final double radius;
  final Interval interval;
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// Paints the sieve mesh and its falling grains from [progress]
/// (`controller.value`) alone, each grain's position read through its own
/// [Interval] (§6.2, §6.3's established CustomPainter approach) — no widget
/// per grain.
class _BootSievePainter extends CustomPainter {
  const _BootSievePainter({
    required this.progress,
    required this.meshInterval,
    required this.grains,
  });

  final double progress;
  final Interval meshInterval;
  final List<_Grain> grains;

  @override
  void paint(Canvas canvas, Size size) {
    final clamped = progress.clamp(0.0, 1.0);
    final center = Offset(size.width / 2, size.height * 0.4);
    final meshRadius = size.shortestSide * 0.17;

    final meshT = meshInterval.transform(clamped);
    if (meshT > 0) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(_lerp(0.96, 1, meshT));
      canvas.translate(-center.dx, -center.dy);
      _paintMesh(canvas, center, meshRadius, meshT);
      canvas.restore();
    }

    final grainPaint = Paint();
    for (final grain in grains) {
      final t = grain.interval.transform(clamped);
      if (t <= 0) continue;
      final dx = _lerp(
        grain.dxOffset * meshRadius * 0.3,
        grain.dxOffset * meshRadius,
        t,
      );
      final dy = _lerp(-meshRadius * 1.6, grain.restDyOffset * meshRadius, t);
      grainPaint.color = Colors.white.withValues(alpha: 0.85 * t);
      canvas.drawCircle(center + Offset(dx, dy), grain.radius, grainPaint);
    }
  }

  void _paintMesh(Canvas canvas, Offset center, double radius, double opacity) {
    final rim = Paint()
      ..color = Colors.white.withValues(alpha: 0.35 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, rim);

    final wire = Paint()
      ..color = Colors.white.withValues(alpha: 0.22 * opacity)
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );
    const divisions = 6;
    for (var i = -divisions; i <= divisions; i++) {
      final offset = radius * i / divisions;
      canvas.drawLine(
        Offset(center.dx - radius, center.dy + offset),
        Offset(center.dx + radius, center.dy + offset),
        wire,
      );
      canvas.drawLine(
        Offset(center.dx + offset, center.dy - radius),
        Offset(center.dx + offset, center.dy + radius),
        wire,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BootSievePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
