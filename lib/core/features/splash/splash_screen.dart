import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_radius.dart';
import 'package:visiosoil_app/core/theme/app_spacing.dart';
import 'package:visiosoil_app/core/widgets/visio_soil_logo.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';

/// Initial splash screen of the app.
///
/// Displays the VisioSoil logo and requests the required permissions (camera
/// and location). On first launch it then routes to the onboarding; on later
/// launches it goes straight to home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// The logo tile's edge, the mark's edge inside it, and the tile's corner
  /// radius, in logical pixels. The Android launch drawables draw the same tile
  /// and are pinned to these (SPEC 0089).
  static const double logoTileSize = 120;
  static const double logoMarkSize = 64;
  static const double logoTileRadius = AppRadius.xl;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppMotion.reveal,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: AppMotion.standard),
    );

    _animationController.forward();

    // Goes on after the reveal. It asks for no permission: capture asks for
    // the camera and location when it needs them (SPEC 0099).
    Future.delayed(const Duration(milliseconds: 1200), _start);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!mounted) return;

    setState(() => _isStarting = true);

    // Small delay for a smooth transition
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    // First launch shows the onboarding once; later launches go straight home.
    final completed =
        await ref.read(onboardingStoreProvider).hasCompletedOnboarding();
    if (!mounted) return;

    context.go(completed ? '/' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The tile sits where the native launch window draws it, at the centre of
    // the whole view, and neither moves nor fades, so the hand-over from the
    // native window cannot be seen (SPEC 0089). Only what that window does not
    // show animates in: the text below the tile, and the tile's shadow.
    return Scaffold(
      backgroundColor: context.palette.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final tileBottom =
              (constraints.maxHeight + SplashScreen.logoTileSize) / 2;
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: AnimatedBuilder(
                  animation: _fadeAnimation,
                  builder: (context, child) => Container(
                    width: SplashScreen.logoTileSize,
                    height: SplashScreen.logoTileSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        // The brand mark, as the native window draws it, in
                        // both themes (SPEC 0107).
                        colors: [
                          context.palette.brand,
                          context.palette.brandTileEnd,
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(SplashScreen.logoTileRadius),
                      boxShadow: [
                        BoxShadow(
                          color: context.palette.shadowBrand.withValues(
                            alpha: context.palette.shadowBrand.a *
                                _fadeAnimation.value,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                  child: const VisioSoilLogo(
                    size: SplashScreen.logoMarkSize,
                    color: Colors.white,
                  ),
                ),
              ),
              Positioned(
                top: tileBottom + AppSpacing.xl,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // App name
                      Text(
                        'VisioSoil',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Tagline
                      Text(
                        'Análise de textura do solo',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.palette.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      // Status/loading indicator
                      if (_isStarting) ...[
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.palette.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Iniciando...',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: context.palette.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
