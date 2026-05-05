import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/features/capture/capture.dart';
import 'package:visiosoil_app/core/features/capture/processing_screen.dart';
import 'package:visiosoil_app/core/features/details/details.dart';
import 'package:visiosoil_app/core/features/history/history.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';
import 'package:visiosoil_app/core/features/result/result_screen.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/models/soil_record.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const MainScreen()),
    GoRoute(path: '/capture', builder: (context, state) => const CapturePage()),
    GoRoute(path: '/history', builder: (context, state) => const HistoryPage()),
    GoRoute(
      path: '/details',
      builder: (context, state) {
        final extra = state.extra;
        final id = extra is int ? extra : -1;
        return DetailsPage(recordId: id);
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
      path: '/processing',
      builder: (context, state) {
        final extra = state.extra;
        final imagePath = extra is String ? extra : null;
        return ProcessingScreen(imagePath: imagePath);
      },
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/result',
      builder: (context, state) {
        final extra = state.extra;
        final record = extra is SoilRecord ? extra : null;
        if (record == null) {
          return const Scaffold(
            body: Center(child: Text('Registro nao disponivel')),
          );
        }
        return ResultScreen(record: record);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
  ],
);
