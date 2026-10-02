// The app starts in the stored theme and keeps the status-bar icons readable
// on it (SPEC 0107).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';

class _MemoryStore implements AppearanceStore {
  _MemoryStore(this.stored);

  ThemeMode stored;

  @override
  Future<ThemeMode> read() async => stored;

  @override
  Future<void> write(ThemeMode mode) async => stored = mode;
}

class _RecordingSync implements NightModeSync {
  @override
  Future<void> apply(ThemeMode mode) async {}
}

Widget _app(ThemeMode stored, void Function(BuildContext) onBuild) =>
    ProviderScope(
      overrides: [
        initialThemeModeProvider.overrideWithValue(stored),
        appearanceStoreProvider.overrideWithValue(_MemoryStore(stored)),
        nightModeSyncProvider.overrideWithValue(_RecordingSync()),
      ],
      child: VisioSoilApp(
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: Builder(builder: (context) {
              onBuild(context);
              return const SizedBox();
            })),
          ),
        ]),
      ),
    );

void main() {
  testWidgets('the_first_frame_is_in_the_stored_theme', (tester) async {
    final seen = <Brightness>[];
    await tester.pumpWidget(
      _app(ThemeMode.dark, (context) => seen.add(Theme.of(context).brightness)),
    );

    expect(seen, isNotEmpty);
    expect(seen.first, Brightness.dark);
  });

  testWidgets('status_bar_icons_follow_the_theme', (tester) async {
    SystemUiOverlayStyle overlay() => tester
        .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byWidgetPredicate(
            (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
          ).first,
        )
        .value;

    await tester.pumpWidget(_app(ThemeMode.dark, (_) {}));
    expect(overlay().statusBarIconBrightness, Brightness.light);
    expect(overlay().statusBarBrightness, Brightness.dark);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ThemeMode.light, (_) {}));
    expect(overlay().statusBarIconBrightness, Brightness.dark);
    expect(overlay().statusBarBrightness, Brightness.light);
  });
}
