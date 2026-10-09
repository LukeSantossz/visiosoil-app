import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/compare/compare_screen.dart';
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
    GoRoute(
      path: '/capture',
      // A photograph recovered after a restart arrives as the extra (SPEC 0096).
      builder: (context, state) {
        final extra = state.extra;
        return CaptureScreen(initialImagePath: extra is String ? extra : null);
      },
    ),
    GoRoute(
      path: '/capture-guide',
      // `true` when the guide stands before the camera (SPEC 0142).
      builder: (context, state) =>
          CaptureGuideScreen(beforeCamera: state.extra == true),
    ),
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
      path: '/compare',
      // The two selected ids, in selection order (SPEC 0150).
      builder: (context, state) {
        final extra = state.extra;
        final ids =
            extra is List<int> && extra.length == 2 ? extra : const [-1, -1];
        return CompareScreen(firstId: ids[0], secondId: ids[1]);
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
