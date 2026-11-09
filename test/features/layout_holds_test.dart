// The layout fixes SPEC 0265 names one by one: the guided camera's panel,
// Settings' text-size row, the history chips' target, Profile's statistics
// and where the capture guide is reached from.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visiosoil_app/core/features/capture/guided_camera/capture_guide_overlay.dart';
import 'package:visiosoil_app/core/features/history/widgets/history_filter_bar.dart';
import 'package:visiosoil_app/core/features/profile/profile_screen.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/segmented_control.dart';
import 'package:visiosoil_app/core/widgets/stat_cell.dart';
import 'package:visiosoil_app/main.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../support/guided_camera_harness.dart';

class _SignedOut implements AuthService {
  @override
  AuthAccount? get currentAccount => null;

  @override
  Future<AuthAccount?> restoreSession() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Appearance implements AppearanceStore {
  @override
  Future<ThemeMode> readBaseThemeMode() async => ThemeMode.system;
  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async {}
  @override
  Future<bool> readSunMode() async => false;
  @override
  Future<void> writeSunMode(bool on) async {}
  @override
  Future<bool> readVibration() async => true;
  @override
  Future<void> writeVibration(bool on) async {}
  @override
  Future<bool> readReduceMotion() async => false;
  @override
  Future<void> writeReduceMotion(bool on) async {}
}

class _NoSync implements NightModeSync {
  @override
  Future<void> apply(ThemeMode mode) async {}
}

/// Puts [tester] on a [size] dp phone at [scale] text.
void _phone(WidgetTester tester, Size size, double scale) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _pumpSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        initialBaseThemeModeProvider.overrideWithValue(ThemeMode.light),
        initialSunModeProvider.overrideWithValue(false),
        appearanceStoreProvider.overrideWithValue(_Appearance()),
        nightModeSyncProvider.overrideWithValue(_NoSync()),
        initialVibrationProvider.overrideWithValue(true),
        initialReduceMotionProvider.overrideWithValue(false),
        authServiceProvider.overrideWithValue(_SignedOut()),
        packageInfoProvider.overrideWith(
          (ref) async => PackageInfo(
            appName: 'VisioSoil',
            packageName: 'com.visiosoil.app',
            version: '1.0.0',
            buildNumber: '1',
          ),
        ),
      ],
      child: VisioSoilApp(
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _records = [
  for (final (id, texture) in [(1, 'Argilosa'), (2, 'Arenosa')])
    SoilRecord(
      id: id,
      imagePath: '',
      timestamp: '2026-10-24T12:00:00Z',
      textureClass: texture,
      confidenceScore: .8,
    ),
];

Future<void> _pumpProfile(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authServiceProvider.overrideWithValue(_SignedOut()),
        soilRecordsStreamProvider.overrideWith((ref) => Stream.value(_records)),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream.value(ConnectivityStatus.online),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpChips(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        soilRecordsStreamProvider.overrideWithValue(
          AsyncValue<List<SoilRecord>>.data(_records),
        ),
      ],
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: HistoryFilterBar(
            searchController: TextEditingController(),
            onSearchChanged: (_) {},
            onClearSearch: () {},
            onSelectTexture: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The padded slot around the chip labelled [label].
Finder _chipSlot(String label) => find.ancestor(
  of: find.widgetWithText(FilterChip, label),
  matching: find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_ChipSlot',
  ),
);

void main() {
  testWidgets('guided_camera_outline_stays_above_the_panel_at_large_text', (
    tester,
  ) async {
    _phone(tester, const Size(360, 640), 2);
    await openGuidedCamera(tester);

    final overlay = tester.widget<CaptureGuideOverlay>(
      find.byType(CaptureGuideOverlay),
    );
    final area = tester.getRect(find.byType(CaptureGuideOverlay));
    final layout = CaptureGuideLayout.compute(
      area.size,
      topInset: overlay.topInset,
      bottomInset: overlay.bottomInset,
      preview: overlay.preview,
    );
    final panelTop = tester
        .getRect(find.byKey(const ValueKey('guided-camera-panel')))
        .top;

    expect(area.top + layout.outline.bottom, lessThanOrEqualTo(panelTop));
  });

  testWidgets('text_size_control_sits_below_its_title_at_large_text', (
    tester,
  ) async {
    _phone(tester, const Size(411, 891), 1.3);
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Tamanho do texto'), 200);
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('Tamanho do texto'));
    final control = tester.getRect(
      find.byWidgetPredicate((widget) => widget is SegmentedControl<bool>),
    );

    expect(control.top, greaterThanOrEqualTo(title.bottom));
    expect(control.width, greaterThanOrEqualTo(title.width));
  });

  testWidgets('history_chip_target_follows_the_density', (tester) async {
    await _pumpChips(tester, AppTheme.light);
    expect(
      tester.getSize(_chipSlot('Argilosa')).height,
      greaterThanOrEqualTo(48),
    );

    await _pumpChips(tester, AppTheme.sun);
    expect(
      tester.getSize(_chipSlot('Argilosa')).height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('profile_statistics_stack_at_large_text', (tester) async {
    _phone(tester, const Size(411, 891), 1.3);
    await _pumpProfile(tester);

    final tops = {
      for (final cell in tester.widgetList(find.byType(StatCell)))
        tester.getRect(find.byWidget(cell)).top,
    };
    expect(find.byType(StatCell), findsNWidgets(3));
    expect(tops, hasLength(3));
  });

  testWidgets('the_guide_is_reached_from_settings_not_profile', (tester) async {
    await _pumpProfile(tester);
    expect(find.text('Como fotografar a amostra'), findsNothing);
    expect(find.text('Como fotografar'), findsNothing);

    // A fresh scope: the two screens override different providers.
    await tester.pumpWidget(const SizedBox());
    await _pumpSettings(tester);
    await tester.scrollUntilVisible(find.text('Como fotografar'), 200);
    expect(find.text('Como fotografar'), findsOneWidget);
  });
}
