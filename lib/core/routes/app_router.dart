import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';
import 'package:visiosoil_app/core/features/splash/splash_screen.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/widgets/route_error_view.dart';

final appRouter = GoRouter(
  initialLocation: '/splash',
  errorBuilder: (context, state) =>
      RouteErrorView(onGoHome: () => context.go('/')),
  routes: [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(path: '/', builder: (context, state) => const MainScreen()),
    GoRoute(path: '/capture', builder: (context, state) => const CaptureScreen()),
    GoRoute(
      path: '/details',
      builder: (context, state) {
        final extra = state.extra;
        final id = extra is int ? extra : -1;
        return DetailsScreen(recordId: id);
      },
    ),
    GoRoute(
      path: '/preview',
      builder: (context, state) {
        final extra = state.extra;
        final id = extra is int ? extra : -1;
        return ImagePreviewScreen(recordId: id);
      },
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
