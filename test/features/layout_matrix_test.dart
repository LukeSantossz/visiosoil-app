// Every screen lays out whole on a small, a mid and a tall phone, in portrait
// and in landscape, at the text scales the app supports (SPEC 0265). A layout
// overflow is a `FlutterError`, which `takeException` hands back.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/capture/capture_screen.dart';
import 'package:visiosoil_app/core/features/capture/widgets/camera_permission_denied_view.dart';
import 'package:visiosoil_app/core/features/compare/compare_screen.dart';
import 'package:visiosoil_app/core/features/details/details_screen.dart';
import 'package:visiosoil_app/core/features/main/main_screen.dart';
import 'package:visiosoil_app/core/features/onboarding/onboarding_screen.dart';
import 'package:visiosoil_app/core/features/preview/image_preview_screen.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/classification_report.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/core/services/inference_service.dart';
import 'package:visiosoil_app/core/services/permission_service.dart';
import 'package:visiosoil_app/core/services/research/research_service.dart';
import 'package:visiosoil_app/core/theme/app_motion.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/error_state.dart';
import 'package:visiosoil_app/core/widgets/permission_denied_view.dart';
import 'package:visiosoil_app/core/widgets/route_error_view.dart';
import 'package:visiosoil_app/models/soil_record.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/inference_provider.dart';
import 'package:visiosoil_app/providers/main_tab_index_provider.dart';
import 'package:visiosoil_app/providers/management_tips_repository_provider.dart';
import 'package:visiosoil_app/providers/onboarding_store_provider.dart';
import 'package:visiosoil_app/providers/research_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../support/fake_capture_guide_store.dart';
import '../support/fake_onboarding_store.dart';
import '../support/fake_soil_record_repository.dart';
import '../support/management_tips_fakes.dart';

const _sizes = {
  'small portrait': Size(320, 568),
  'mid portrait': Size(360, 640),
  'tall portrait': Size(411, 891),
  'mid landscape': Size(640, 360),
  'tall landscape': Size(891, 411),
};

const _scales = [1.0, 1.3, 2.0];

final _classified = SoilRecord(
  id: 1,
  imagePath: 'missing.png',
  latitude: -23.5,
  longitude: -46.6,
  address: 'Fazenda Boa Vista, Talhão norte, São Paulo, SP',
  timestamp: '2026-06-26T12:00:00Z',
  textureClass: 'Argilosa',
  confidenceScore: 0.82,
  sampleLabel: 'Amostra 12',
);

final _failed = SoilRecord(
  id: 2,
  imagePath: 'missing.png',
  timestamp: '2026-06-27T12:00:00Z',
  classificationFailure: ClassificationFailureCause.sheetNotFound,
);

final _records = [_classified, _failed];

class _RecordsById extends FakeSoilRecordRepository {
  @override
  Future<SoilRecord?> getById(int id) async =>
      _records.where((r) => r.id == id).firstOrNull;
}

class _Auth implements AuthService {
  @override
  AuthAccount? get currentAccount => null;
  @override
  Future<AuthAccount?> restoreSession() async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Connectivity implements ConnectivityService {
  @override
  Stream<ConnectivityStatus> watch() => Stream.value(ConnectivityStatus.online);
  @override
  Future<ConnectivityStatus> current() async => ConnectivityStatus.online;
}

class _ErrorReport implements ErrorReportStore {
  @override
  Future<bool> get isEmpty async => true;
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

/// Classifies nothing: the run never ends, so capture stays on the photo.
class _Pending extends InferenceService {
  @override
  Future<ClassificationReport> classify(
    String imagePath, {
    Duration? timeout,
    InferenceIsolateEntry? entryPoint,
    ClassificationPhaseCallback? onPhase,
  }) => Completer<ClassificationReport>().future;
}

late String _photo;

Widget _scope(
  Widget child, {
  String? initial,
  List<GoRoute> routes = const [],
}) {
  final router = GoRouter(
    initialLocation: initial ?? '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      ...routes,
      for (final path in [
        '/details',
        '/settings',
        '/capture-guide',
        '/preview',
      ])
        if (!routes.any((r) => r.path == path))
          GoRoute(path: path, builder: (_, _) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      soilRecordRepositoryProvider.overrideWithValue(_RecordsById()),
      soilRecordsStreamProvider.overrideWith((ref) => Stream.value(_records)),
      filteredRecordsProvider.overrideWith((ref) => Stream.value(_records)),
      soilRecordByIdProvider.overrideWith(
        (ref, id) async => _records.where((r) => r.id == id).firstOrNull,
      ),
      connectivityServiceProvider.overrideWithValue(_Connectivity()),
      connectivityStatusProvider.overrideWith(
        (ref) => Stream.value(ConnectivityStatus.online),
      ),
      authServiceProvider.overrideWithValue(_Auth()),
      onboardingStoreProvider.overrideWithValue(FakeOnboardingStore()),
      captureGuideStoreProvider.overrideWithValue(
        FakeCaptureGuideStore(seen: true),
      ),
      errorReportStoreProvider.overrideWithValue(_ErrorReport()),
      inferenceServiceProvider.overrideWithValue(_Pending()),
      managementTipsRepositoryProvider.overrideWithValue(
        FakeManagementTipsRepository(),
      ),
      researchServiceProvider.overrideWithValue(
        FakeResearchService(
          (_) async =>
              const ResearchFailure(ResearchFailureKind.upstreamUnavailable),
        ),
      ),
      initialBaseThemeModeProvider.overrideWithValue(ThemeMode.system),
      initialSunModeProvider.overrideWithValue(false),
      initialVibrationProvider.overrideWithValue(true),
      initialReduceMotionProvider.overrideWithValue(false),
      appearanceStoreProvider.overrideWithValue(_Appearance()),
    ],
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

Widget _capture({String? photo}) => CaptureScreen(
  locate: () async => null,
  checkCameraPermission: () async => AppPermissionStatus.granted,
  requestCameraPermission: () async => AppPermissionStatus.granted,
  deletePickedFile: (_) async {},
  initialImagePath: photo,
);

/// Each screen the matrix pumps, by name. A main tab opens through the tabs'
/// provider, so the screen sits in the shell it is shown in.
final Map<String, Widget Function()> _screens = {
  for (var tab = 0; tab < 4; tab++) 'main tab $tab': () => _MainTab(tab: tab),
  'details classified': () => _scope(const DetailsScreen(recordId: 1)),
  'details failed': () => _scope(const DetailsScreen(recordId: 2)),
  'capture empty': () => _scope(_capture()),
  'capture with a photo': () => _scope(_capture(photo: _photo)),
  'settings': () => _scope(const SettingsScreen()),
  for (var step = 1; step <= 4; step++)
    'onboarding step $step': () => _scope(
      OnboardingScreen(
        requestCameraPermission: () async => AppPermissionStatus.granted,
      ),
    ),
  'image preview': () => _scope(const ImagePreviewScreen(recordId: 1)),
  'compare': () => _scope(const CompareScreen(firstId: 1, secondId: 2)),
  'capture guide': () => _scope(const CaptureGuideScreen(beforeCamera: true)),
  'camera permission denied': () => _scope(
    Scaffold(
      body: CameraPermissionDeniedView(
        status: AppPermissionStatus.permanentlyDenied,
        onRetry: () {},
      ),
    ),
  ),
  'permission denied': () => _scope(
    Scaffold(
      body: PermissionDeniedView(
        icon: LucideIcons.mapPin,
        title: 'Localização negada',
        description:
            'Sem a localização, a análise é salva sem coordenadas. Você pode '
            'permitir o acesso nas configurações do aparelho.',
        isPermanentlyDenied: true,
        onRetry: () {},
      ),
    ),
  ),
  'error state': () => _scope(
    Scaffold(
      body: ErrorState(
        message: 'Não foi possível carregar a análise.',
        onRetry: () {},
      ),
    ),
  ),
  'route error': () => _scope(RouteErrorView(onGoHome: () {})),
};

/// The page each onboarding entry jumps to after the first frame.
const _onboardingPage = {
  'onboarding step 2': 1,
  'onboarding step 3': 2,
  'onboarding step 4': 3,
};

class _MainTab extends StatelessWidget {
  const _MainTab({required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context) => _scope(
    Consumer(
      builder: (context, ref, _) {
        // Selected once, before the shell reads it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ref.read(mainTabIndexProvider) != tab) {
            ref.read(mainTabIndexProvider.notifier).select(tab);
          }
        });
        return const MainScreen();
      },
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('InterVariable')
      ..addFont(
        Future.value(
          ByteData.view(
            File('assets/fonts/InterVariable.ttf').readAsBytesSync().buffer,
          ),
        ),
      );
    await loader.load();
    final dir = Directory.systemTemp.createTempSync('layout_matrix');
    _photo = '${dir.path}/sample.png';
    File(
      _photo,
    ).writeAsBytesSync(img.encodePng(img.Image(width: 64, height: 48)));
  });

  setUp(() => AppMotion.reduceMotion = true);
  tearDown(() => AppMotion.reduceMotion = false);

  for (final MapEntry(key: screen, value: build) in _screens.entries) {
    for (final MapEntry(key: sizeName, value: size) in _sizes.entries) {
      for (final scale in _scales) {
        testWidgets('$screen holds on a $sizeName phone at ${scale}x', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(build());
          await _settle(tester);
          final page = _onboardingPage[screen];
          if (page != null) {
            tester
                .widget<PageView>(find.byType(PageView))
                .controller!
                .jumpToPage(page);
            await _settle(tester);
          }

          expect(tester.takeException(), isNull);
          // Unmounted inside the test, so a pending timer ends with it.
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  }
}
