import 'package:go_router/go_router.dart';
import '../features/capture/capture.dart';
import '../features/history/history.dart';
import '../features/details/details.dart';
import '../features/home/home_page.dart';
import '../features/main/main_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/', 

  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainScreen(),
    ),
    GoRoute(
      path: '/capture',
      builder: (context, state) => const CapturePage(),
    ),
    GoRoute(
      path: '/history',
      builder: (context, state) => const HistoryPage(),
    ),
    GoRoute(
      path: '/details',
      builder: (context, state) => const DetailsPage(),
    ),
  ]
);
