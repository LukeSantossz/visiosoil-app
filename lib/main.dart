import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame, so it is already in the chosen theme
  // (SPEC 0107).
  final themeMode = await restoreThemeMode(
    SharedPreferencesAppearanceStore(),
    defaultNightModeSync(),
  );
  runApp(ProviderScope(
    overrides: [initialThemeModeProvider.overrideWithValue(themeMode)],
    child: const VisioSoilApp(),
  ));
}

class VisioSoilApp extends ConsumerWidget {
  const VisioSoilApp({super.key, this.routerConfig});

  /// The router to run; [appRouter] when null. Tests pass their own.
  final GoRouter? routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'VisioSoil',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: routerConfig ?? appRouter,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _statusBarFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  /// Status-bar icons that read on the theme's background, for screens without
  /// an app bar; an `AppBar` sets its own. Only the icons: the bar colours are
  /// left to the platform (#304).
  static SystemUiOverlayStyle _statusBarFor(Brightness theme) =>
      theme == Brightness.dark
          ? const SystemUiOverlayStyle(
              statusBarIconBrightness: Brightness.light,
              statusBarBrightness: Brightness.dark,
            )
          : const SystemUiOverlayStyle(
              statusBarIconBrightness: Brightness.dark,
              statusBarBrightness: Brightness.light,
            );
}
