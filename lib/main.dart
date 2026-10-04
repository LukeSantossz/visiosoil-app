import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/routes/app_router.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
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
  final themeMode = await restoreThemeMode(appearance, defaultNightModeSync());
  final highContrast = await restoreHighContrast(appearance);
  runApp(ProviderScope(
    overrides: [
      initialThemeModeProvider.overrideWithValue(themeMode),
      initialHighContrastProvider.overrideWithValue(highContrast),
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
    final highContrast = ref.watch(highContrastProvider);
    return MaterialApp.router(
      title: 'VisioSoil',
      debugShowCheckedModeBanner: false,
      // The setting turns high contrast on; so does the platform's own signal,
      // through the two high-contrast themes (SPEC 0130).
      theme: highContrast ? AppTheme.lightHighContrast : AppTheme.light,
      darkTheme: highContrast ? AppTheme.darkHighContrast : AppTheme.dark,
      highContrastTheme: AppTheme.lightHighContrast,
      highContrastDarkTheme: AppTheme.darkHighContrast,
      themeMode: ref.watch(themeModeProvider),
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
