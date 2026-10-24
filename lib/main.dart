import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/core/theme/app_haptics.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // First, so an error anywhere after it reaches the report Settings shares
  // (SPEC 0110).
  final errorReport = ErrorReportStore();
  installErrorReporting(errorReport);
  // Read before the first frame, so it is already in the chosen theme
  // (SPEC 0107).
  final appearance = SharedPreferencesAppearanceStore();
  final (baseThemeMode, sunMode) =
      await restoreAppearance(appearance, defaultNightModeSync());
  // Vibration and reduce-motion restored before first frame (redesign v11 §3.11).
  final vibration = await restoreVibration(appearance);
  final reduceMotion = await restoreReduceMotion(appearance);
  // Set static flags before the first frame builds any controllers.
  AppHaptics.enabled = vibration;
  AppMotion.reduceMotion = reduceMotion;
  runApp(ProviderScope(
    overrides: [
      initialBaseThemeModeProvider.overrideWithValue(baseThemeMode),
      initialSunModeProvider.overrideWithValue(sunMode),
      initialVibrationProvider.overrideWithValue(vibration),
      initialReduceMotionProvider.overrideWithValue(reduceMotion),
      errorReportStoreProvider.overrideWithValue(errorReport),
    ],
    child: const VisioSoilApp(),
  ));
}

class VisioSoilApp extends ConsumerWidget {
  const VisioSoilApp({super.key, this.routerConfig});

  /// The router to run; [appRouter] when null. Tests pass their own.
  final GoRouter? routerConfig;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sunMode = ref.watch(sunModeProvider);
    final baseThemeMode = ref.watch(baseThemeModeProvider);
    // Modo Sol forces its own fixed high-contrast light theme and ignores
    // both the base choice and the platform's brightness (redesign v11 §2,
    // SPEC 0186). The platform's own high-contrast signal still turns high
    // contrast on through the two `highContrastTheme`/`highContrastDarkTheme`
    // params below (SPEC 0130) — unrelated to Modo Sol, which must not be
    // knocked out by that signal while it is the explicit override.
    final light = sunMode ? AppTheme.sun : AppTheme.light;
    final dark = sunMode ? AppTheme.sun : AppTheme.dark;
    final highContrastLight = sunMode ? AppTheme.sun : AppTheme.lightHighContrast;
    final highContrastDark = sunMode ? AppTheme.sun : AppTheme.darkHighContrast;
    return MaterialApp.router(
      title: 'VisioSoil',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      highContrastTheme: highContrastLight,
      highContrastDarkTheme: highContrastDark,
      themeMode: nightModeFor(baseThemeMode, sun: sunMode),
      routerConfig: routerConfig ?? appRouter,
      // Fixed, not the device's: the app's own copy is pt-BR only, so Flutter's
      // widgets speak it too (SPEC 0119).
      locale: _locale,
      supportedLocales: const [_locale],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: _statusBarFor(Theme.of(context).brightness),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }

  static const _locale = Locale('pt', 'BR');

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
