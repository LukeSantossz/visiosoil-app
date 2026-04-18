import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/capture.dart';
import 'package:visiosoil_app/core/features/details/details.dart';
import 'package:visiosoil_app/core/features/history/history.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const MainScreen()),
    GoRoute(path: '/capture', builder: (context, state) => const CapturePage()),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
    GoRoute(
      path: '/details',
      builder: (context, state) {
        final id = state.extra as int;
        return DetailsPage(recordId: id);
      },
    ),
    GoRoute(
      path: '/preview',
      builder: (context, state) {
        final id = state.extra as int;
        return ImagePreviewScreen(recordId: id);
      },
    ),
  ],
);
