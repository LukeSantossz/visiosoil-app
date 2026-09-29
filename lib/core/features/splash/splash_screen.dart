import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/theme/app_colors.dart';
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
  late Animation<double> _scaleAnimation;

  bool _isRequestingPermissions = false;
  String _statusMessage = '';

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

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: AppMotion.emphasized),
    );

    _animationController.forward();

    // Starts the permission requests after the initial animation
    Future.delayed(const Duration(milliseconds: 1200), _requestPermissions);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (!mounted) return;

    setState(() {
      _isRequestingPermissions = true;
      _statusMessage = 'Solicitando permissões...';
    });

    // Requests camera permission
    setState(() => _statusMessage = 'Permissão de câmera...');
    await PermissionService.requestCamera();

    if (!mounted) return;

    // Requests location permission
    setState(() => _statusMessage = 'Permissão de localização...');
    await PermissionService.requestLocation();

    if (!mounted) return;

    setState(() => _statusMessage = 'Iniciando...');

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo container
                Container(
                  width: SplashScreen.logoTileSize,
                  height: SplashScreen.logoTileSize,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.tertiary],
                    ),
                    borderRadius:
                        BorderRadius.circular(SplashScreen.logoTileRadius),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.shadowBrand,
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const VisioSoilLogo(
                    size: SplashScreen.logoMarkSize,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                // Status/loading indicator
                if (_isRequestingPermissions) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _statusMessage,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
