// Widget tests for the Settings account tile: shows a sign-in affordance when
// signed out and the account identity + sign-out when signed in.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:visiosoil_app/core/constants/app_links.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/features/capture/capture_guide_screen.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/appearance_store.dart';
import 'package:visiosoil_app/core/services/capture_guide_store.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/connectivity_service.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/core/services/share_service.dart';
import 'package:visiosoil_app/core/widgets/loading_indicator.dart';
import 'package:visiosoil_app/core/theme/app_palette.dart';
import 'package:visiosoil_app/core/theme/app_theme.dart';
import 'package:visiosoil_app/core/widgets/settings_tile.dart';
import 'package:visiosoil_app/core/widgets/visio_button.dart';
import 'package:visiosoil_app/providers/appearance_provider.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/capture_guide_store_provider.dart';
import 'package:visiosoil_app/providers/connectivity_provider.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/share_service_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_capture_guide_store.dart';
import '../../support/fake_soil_record_repository.dart';
import '../../support/guidelines.dart';
import '../../support/large_text.dart';

/// In-memory [AppearanceStore] for tests.
class _MemoryAppearanceStore implements AppearanceStore {
  ThemeMode base = ThemeMode.system;
  bool sun = false;
  bool vibration = true;
  bool reduceMotion = false;

  @override
  Future<ThemeMode> readBaseThemeMode() async => base;
  @override
  Future<void> writeBaseThemeMode(ThemeMode mode) async => base = mode;
  @override
  Future<bool> readSunMode() async => sun;
  @override
  Future<void> writeSunMode(bool on) async => sun = on;
  @override
  Future<bool> readVibration() async => vibration;
  @override
  Future<void> writeVibration(bool on) async => vibration = on;
  @override
  Future<bool> readReduceMotion() async => reduceMotion;
  @override
  Future<void> writeReduceMotion(bool on) async => reduceMotion = on;
}

class _FakeAuthService implements AuthService {
  _FakeAuthService(
    this.restored, {
    this.signInError,
    this.signOutError,
    this.signOutClearsBeforeError = false,
    this.deleteAccountError,
  });

  /// When set, [deleteAccount] throws it. An [AccountNotRevokedException] is
  /// thrown after the local session is cleared, as the real service does.
  final Object? deleteAccountError;
  int deleteAccountCalls = 0;

  final AuthAccount? restored;

  /// When set, [signIn] throws it, standing in for an OAuth/network failure.
  final Object? signInError;

  /// When set, [signOut] throws it, standing in for a sign-out failure.
  final Object? signOutError;

  /// With [signOutError] set: when true, [signOut] clears local state before
  /// throwing (models a remote-revoke failure after local cleanup); when false,
  /// it throws with local state intact (models a store-clear failure).
  final bool signOutClearsBeforeError;

  AuthAccount? _current;

  /// How many times [signIn] ran, so a test can prove it never started.
  int signInCalls = 0;

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Future<AuthAccount?> restoreSession() async {
    _current = restored;
    return restored;
  }

  @override
  Future<AuthAccount?> signIn() async {
    signInCalls++;
    final error = signInError;
    if (error != null) throw error;
    return restored;
  }

  @override
  Future<void> signOut() async {
    final error = signOutError;
    if (error != null) {
      if (signOutClearsBeforeError) _current = null;
      throw error;
    }
    _current = null;
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    final error = deleteAccountError;
    if (error is AccountNotRevokedException) _current = null;
    if (error != null) throw error;
    _current = null;
  }
}

/// The report as the screen reaches it: whether it holds an entry, its text,
/// and how often it was cleared. Anything else falls to noSuchMethod.
class _FakeErrorReportStore implements ErrorReportStore {
  _FakeErrorReportStore({this.empty = true});

  bool empty;
  int clearCalls = 0;

  @override
  Future<bool> get isEmpty async => empty;

  @override
  Future<String> render({
    required String appVersion,
    required String osVersion,
  }) async => 'relatorio $appVersion';

  @override
  Future<void> clear() async {
    clearCalls++;
    empty = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the report text handed to the share sheet, or fails as told.
class _RecordingShareService implements ShareService {
  String? sharedReport;
  Exception? failure;

  @override
  Future<void> shareErrorReport(String text) async {
    final error = failure;
    if (error != null) throw error;
    sharedReport = text;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A connectivity source with a fixed reading, or one whose read throws.
class _FakeConnectivityService implements ConnectivityService {
  const _FakeConnectivityService(this.status, {this.readError});

  final ConnectivityStatus status;
  final Object? readError;

  @override
  Stream<ConnectivityStatus> watch() => Stream.value(status);

  @override
  Future<ConnectivityStatus> current() async {
    final error = readError;
    if (error != null) throw error;
    return status;
  }
}

Widget _app(
  AuthAccount? account, {
  Object? signInError,
  Object? signOutError,
  bool signOutClearsBeforeError = false,
  _FakeAuthService? auth,
  SoilRecordRepository? repository,
  ErrorReportStore? errorReport,
  ShareService? shareService,
  ConnectivityService connectivity = const _FakeConnectivityService(
    ConnectivityStatus.online,
  ),
  Future<PackageInfo>? packageInfo,
  ThemeData? theme,
  CaptureGuideStore? captureGuide,
  GoRouter? router,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(
        auth ??
            _FakeAuthService(
              account,
              signInError: signInError,
              signOutError: signOutError,
              signOutClearsBeforeError: signOutClearsBeforeError,
            ),
      ),
      connectivityServiceProvider.overrideWithValue(connectivity),
      packageInfoProvider.overrideWith(
        (ref) =>
            packageInfo ??
            Future.value(
              PackageInfo(
                appName: 'VisioSoil',
                packageName: 'app.visiosoil',
                version: '2.0.0',
                buildNumber: '2',
              ),
            ),
      ),
      if (repository != null)
        soilRecordRepositoryProvider.overrideWithValue(repository),
      errorReportStoreProvider.overrideWithValue(
        errorReport ?? _FakeErrorReportStore(),
      ),
      if (shareService != null)
        shareServiceProvider.overrideWithValue(shareService),
      if (captureGuide != null)
        captureGuideStoreProvider.overrideWithValue(captureGuide),
      // Appearance providers needed for settings switches (redesign v11).
      initialBaseThemeModeProvider.overrideWithValue(ThemeMode.system),
      initialSunModeProvider.overrideWithValue(false),
      initialVibrationProvider.overrideWithValue(true),
      initialReduceMotionProvider.overrideWithValue(false),
      appearanceStoreProvider.overrideWithValue(_MemoryAppearanceStore()),
    ],
    child: router == null
        ? MaterialApp(theme: theme, home: const SettingsScreen())
        : MaterialApp.router(theme: theme, routerConfig: router),
  );
}

void main() {
  testWidgets('settings_shows_sign_in_when_signed_out', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();

    expect(find.text('Conta'), findsOneWidget);
    expect(
      find.text('Não vinculada · dados só neste aparelho'),
      findsOneWidget,
    );
  });

  testWidgets('settings_shows_account_when_signed_in', (tester) async {
    await tester.pumpWidget(
      _app(
        const AuthAccount(email: 'agro@example.com', displayName: 'Agro Nomo'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Conta Google'), findsOneWidget);
    expect(find.text('agro@example.com'), findsOneWidget);
    expect(find.text('Agro Nomo'), findsNothing);
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('settings_shows_failure_snackbar_when_sign_in_throws', (
    tester,
  ) async {
    await tester.pumpWidget(_app(null, signInError: Exception('oauth failed')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conta'));
    await tester.pump(); // start sign-in (loading)
    await tester.pump(); // async throws -> error state -> listener fires
    await tester.pump(); // build the SnackBar

    expect(find.text(_failureMessage), findsOneWidget);
    // The tile stays on the sign-in affordance, so the user can retry.
    expect(find.text('Conta'), findsOneWidget);
    expect(
      find.text('Não vinculada · dados só neste aparelho'),
      findsOneWidget,
    );
  });

  // Signing in cannot reach Google without a connection, so the tap says so
  // instead of starting an attempt bound to fail (SPEC 0114).
  testWidgets('signing_in_offline_names_the_missing_connection', (
    tester,
  ) async {
    final auth = _FakeAuthService(null);
    await tester.pumpWidget(
      _app(
        null,
        auth: auth,
        connectivity: const _FakeConnectivityService(
          ConnectivityStatus.offline,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conta'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_offlineMessage), findsOneWidget);
    expect(find.text(_failureMessage), findsNothing);
    expect(auth.signInCalls, 0);
  });

  testWidgets('an_online_sign_in_failure_keeps_the_generic_message', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        null,
        signInError: Exception('oauth failed'),
        connectivity: const _FakeConnectivityService(ConnectivityStatus.online),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();

    expect(find.text(_failureMessage), findsOneWidget);
    expect(find.text(_offlineMessage), findsNothing);
  });

  testWidgets('an_unreadable_connection_still_tries_to_sign_in', (
    tester,
  ) async {
    final auth = _FakeAuthService(null);
    await tester.pumpWidget(
      _app(
        null,
        auth: auth,
        connectivity: _FakeConnectivityService(
          ConnectivityStatus.offline,
          readError: Exception('plugin unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Conta'));
    await tester.pumpAndSettle();

    expect(auth.signInCalls, 1);
    expect(find.text(_offlineMessage), findsNothing);
  });

  testWidgets('settings_shows_failure_snackbar_when_sign_out_throws', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        const AuthAccount(email: 'agro@example.com', displayName: 'Agro'),
        signOutError: Exception('revoke failed'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sair'), findsOneWidget);

    await tester.tap(find.text('Sair'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text(_failureMessage), findsOneWidget);
    // A failed sign-out that leaves credentials must not claim signed-out: the
    // tile keeps showing the account, not the sign-in affordance.
    expect(find.text('agro@example.com'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Conta'), findsNothing);
  });

  testWidgets(
    'settings_shows_signed_out_when_sign_out_clears_then_remote_fails',
    (tester) async {
      await tester.pumpWidget(
        _app(
          const AuthAccount(email: 'agro@example.com', displayName: 'Agro'),
          signOutError: Exception('revoke failed'),
          signOutClearsBeforeError: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sair'), findsOneWidget);

      await tester.tap(find.text('Sair'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(_failureMessage), findsOneWidget);
      // Local credentials were cleared, so the tile reflects signed-out.
      expect(find.text('Conta'), findsOneWidget);
      expect(
        find.text('Não vinculada · dados só neste aparelho'),
        findsOneWidget,
      );
      expect(find.text('Sair'), findsNothing);
    },
  );

  testWidgets('settings_no_failure_snackbar_on_successful_sign_out', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const AuthAccount(email: 'agro@example.com', displayName: 'Agro')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_failureMessage), findsNothing);
    expect(find.text('Conta'), findsOneWidget);
    expect(
      find.text('Não vinculada · dados só neste aparelho'),
      findsOneWidget,
    );
  });

  group('account deletion (SPEC 0113)', () {
    // The dialog's own button: the action that opens it is a TextButton too
    // since SPEC 0129.
    Finder confirmDeletion() => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Excluir conta'),
    );

    const agro = AuthAccount(email: 'agro@example.com', displayName: 'Agro');

    testWidgets('settings_offers_account_deletion_only_when_signed_in', (
      tester,
    ) async {
      await tester.pumpWidget(_app(agro));
      await tester.pumpAndSettle();
      expect(find.text('Excluir conta'), findsOneWidget);

      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      expect(find.text('Excluir conta'), findsNothing);
    });

    testWidgets('confirming_excluir_conta_deletes_the_account', (tester) async {
      final auth = _FakeAuthService(agro);
      await tester.pumpWidget(_app(agro, auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('use "Limpar dados do aparelho"'),
        ),
        findsOneWidget,
        reason: 'the confirmation names where the records are erased',
      );
      await tester.tap(confirmDeletion());
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 1);
      expect(find.text('Conta excluída do VisioSoil.'), findsOneWidget);
      expect(find.text('Conta'), findsOneWidget);
      expect(
        find.text('Não vinculada · dados só neste aparelho'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling excluir conta deletes nothing', (tester) async {
      final auth = _FakeAuthService(agro);
      await tester.pumpWidget(_app(agro, auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(auth.deleteAccountCalls, 0);
      expect(find.text('agro@example.com'), findsOneWidget);
    });

    testWidgets('a_failed_revoke_says_where_to_revoke', (tester) async {
      final auth = _FakeAuthService(
        agro,
        deleteAccountError: AccountNotRevokedException(Exception('offline')),
      );
      await tester.pumpWidget(_app(agro, auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      await tester.tap(confirmDeletion());
      await tester.pumpAndSettle();

      expect(
        find.textContaining('myaccount.google.com/connections'),
        findsOneWidget,
      );
      expect(find.text(_failureMessage), findsNothing);
      expect(find.text('Conta excluída do VisioSoil.'), findsNothing);
      expect(find.text('Conta'), findsOneWidget);
      expect(
        find.text('Não vinculada · dados só neste aparelho'),
        findsOneWidget,
      );
    });

    testWidgets('any other failure keeps the account and the generic message', (
      tester,
    ) async {
      final auth = _FakeAuthService(
        agro,
        deleteAccountError: Exception('secure storage delete failed'),
      );
      await tester.pumpWidget(_app(agro, auth: auth));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Excluir conta'));
      await tester.pumpAndSettle();
      await tester.tap(confirmDeletion());
      await tester.pumpAndSettle();

      expect(find.text(_failureMessage), findsOneWidget);
      expect(find.text('agro@example.com'), findsOneWidget);
    });
  });

  testWidgets('long email stays on one line at 411dp in Sun mode', (
    tester,
  ) async {
    const email = 'agronomist.with.a.very.long.email.address@example.com';
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      _app(
        const AuthAccount(email: email, displayName: 'Agro'),
        theme: AppTheme.sun,
      ),
    );
    await tester.pumpAndSettle();
    final emailFinder = find.text(email);
    final text = tester.widget<Text>(emailFinder);
    expect(text.maxLines, 1);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(text.softWrap, isFalse);
    expect(
      find.ancestor(of: emailFinder, matching: find.byType(Expanded)),
      findsWidgets,
    );
    expect(find.text('Sair').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'confirming apagar tudo deletes all records and shows a snackbar',
    (tester) async {
      final repository = FakeSoilRecordRepository();
      await tester.pumpWidget(_app(null, repository: repository));
      await tester.pumpAndSettle();

      // Open the shared destructive dialog from the delete-all tile.
      // Below the fold in the test view since SPEC 0130's switch.
      await tester.scrollUntilVisible(
        find.text('Limpar dados do aparelho').hitTestable(),
        200,
      );
      await tester.tap(find.text('Limpar dados do aparelho'));
      await tester.pumpAndSettle();

      expect(find.text('Limpar dados do aparelho?'), findsOneWidget);
      expect(
        find.text(
          'Isso apaga as análises e fotos salvas neste aparelho. '
          'Não dá para desfazer.',
        ),
        findsOneWidget,
      );
      final cancelFinder = find.widgetWithText(TextButton, 'Cancelar');
      expect(tester.widget<TextButton>(cancelFinder).autofocus, isTrue);
      expect(Focus.of(tester.element(find.text('Cancelar'))).hasFocus, isTrue);
      final confirmFinder = find.widgetWithText(TextButton, 'Limpar dados');
      final confirm = tester.widget<TextButton>(confirmFinder);
      expect(
        confirm.style!.foregroundColor!.resolve({}),
        Theme.of(tester.element(confirmFinder)).colorScheme.error,
      );

      // Confirm; the delete-all runs and its own snackbar is shown.
      await tester.tap(find.text('Limpar dados'));
      await tester.pumpAndSettle();

      expect(repository.deleteAllCalls, 1);
      expect(find.text('Todos os dados foram apagados.'), findsOneWidget);
    },
  );

  testWidgets('erasing_all_data_clears_the_error_report', (tester) async {
    // SPEC 0110: the report is data the app keeps, so erasing everything
    // erases it too, and the row then has nothing to send.
    final report = _FakeErrorReportStore(empty: false);
    await tester.pumpWidget(
      _app(null, repository: FakeSoilRecordRepository(), errorReport: report),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.errorReportNothingToSend), findsNothing);

    // Below the fold in the test view since SPEC 0130's switch.
    await tester.scrollUntilVisible(
      find.text('Limpar dados do aparelho').hitTestable(),
      200,
    );
    await tester.tap(find.text('Limpar dados do aparelho'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar dados'));
    await tester.pumpAndSettle();

    expect(report.clearCalls, 1);
    expect(find.text(AppStrings.errorReportNothingToSend), findsOneWidget);
  });

  group('settings_shares_the_error_report', () {
    // SPEC 0110: the row shares the report as a text file when it holds an
    // entry, and is disabled, saying so, when it holds none.
    testWidgets('with entries, the row shares the rendered report', (
      tester,
    ) async {
      final share = _RecordingShareService();
      await tester.pumpWidget(
        _app(
          null,
          repository: FakeSoilRecordRepository(),
          errorReport: _FakeErrorReportStore(empty: false),
          shareService: share,
        ),
      );
      await tester.pumpAndSettle();

      // Below the fold since SPEC 0130's appearance switches.
      await tester.scrollUntilVisible(
        find.text('Enviar comentário').hitTestable(),
        200,
      );
      expect(find.text(AppStrings.errorReportPrivacy), findsOneWidget);
      await tester.tap(find.text('Enviar comentário'));
      await tester.pumpAndSettle();

      expect(share.sharedReport, 'relatorio 2.0.0+2');
    });

    testWidgets('without entries, the row is disabled and says so', (
      tester,
    ) async {
      final share = _RecordingShareService();
      await tester.pumpWidget(
        _app(
          null,
          repository: FakeSoilRecordRepository(),
          errorReport: _FakeErrorReportStore(),
          shareService: share,
        ),
      );
      await tester.pumpAndSettle();

      // Below the fold since SPEC 0130's appearance switches.
      await tester.scrollUntilVisible(
        find.text('Enviar comentário').hitTestable(),
        200,
      );
      expect(find.text(AppStrings.errorReportNothingToSend), findsOneWidget);
      await tester.tap(find.text('Enviar comentário'));
      await tester.pumpAndSettle();

      expect(share.sharedReport, isNull);
    });

    testWidgets('a failed share says so, without the error', (tester) async {
      // R3 on #324: a failure must not pass in silence, and the raw
      // exception never reaches the screen.
      final share = _RecordingShareService()
        ..failure = Exception('platform share failed');
      await tester.pumpWidget(
        _app(
          null,
          repository: FakeSoilRecordRepository(),
          errorReport: _FakeErrorReportStore(empty: false),
          shareService: share,
        ),
      );
      await tester.pumpAndSettle();

      // Below the fold since SPEC 0130's appearance switches.
      await tester.scrollUntilVisible(
        find.text('Enviar comentário').hitTestable(),
        200,
      );
      await tester.tap(find.text('Enviar comentário'));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.errorReportShareFailed), findsOneWidget);
      expect(find.textContaining('platform share failed'), findsNothing);
    });
  });

  // At 200 % text on a phone, every settings row still lays out, signed in,
  // where the rows carry the most trailing text (SPEC 0121).
  testWidgets('settings_scales_to_200_percent', (tester) async {
    useLargeTextOnAPhone(tester);

    await tester.pumpWidget(
      _app(
        const AuthAccount(email: 'agro@example.com', displayName: 'Agro Nomo'),
      ),
    );
    await tester.pumpAndSettle();
    await scrollToTheEnd(tester);

    expect(tester.takeException(), isNull);
  });

  // The version tile's spinner is the shared indicator at its own size, so it
  // does not widen the tile's trailing slot (SPEC 0123).
  testWidgets('spinners_keep_their_size: the version tile', (tester) async {
    await tester.pumpWidget(
      _app(null, packageInfo: Completer<PackageInfo>().future),
    );
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Versão').hitTestable(), 200);
    expect(tester.getSize(find.byType(LoadingIndicator)), const Size(16, 16));
  });

  // The two irreversible actions are the app's destructive button, not a
  // settings tile in red (SPEC 0129).
  testWidgets('destructive_is_visually_distinct', (tester) async {
    await tester.pumpWidget(
      _app(
        const AuthAccount(email: 'agro@example.com', displayName: 'Agro Nomo'),
      ),
    );
    await tester.pumpAndSettle();

    final tile = find.byWidgetPredicate((widget) => widget is SettingsTile);
    await tester.scrollUntilVisible(
      find.text('Excluir conta').hitTestable(),
      200,
    );
    expect(
      tester
          .widget<VisioButton>(
            find.ancestor(
              of: find.text('Excluir conta'),
              matching: find.byType(VisioButton),
            ),
          )
          .variant,
      VisioButtonVariant.destructive,
    );
    await tester.scrollUntilVisible(
      find.text('Limpar dados do aparelho').hitTestable(),
      200,
    );
    expect(
      find.ancestor(of: find.text('Limpar dados do aparelho'), matching: tile),
      findsOneWidget,
    );
  });

  testWidgets('cancelling apagar tudo deletes nothing', (tester) async {
    final repository = FakeSoilRecordRepository();
    final report = _FakeErrorReportStore(empty: false);
    await tester.pumpWidget(
      _app(null, repository: repository, errorReport: report),
    );
    await tester.pumpAndSettle();

    // Below the fold in the test view since SPEC 0130's switch.
    await tester.scrollUntilVisible(
      find.text('Limpar dados do aparelho').hitTestable(),
      200,
    );
    await tester.tap(find.text('Limpar dados do aparelho'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.deleteAllCalls, 0);
    expect(report.clearCalls, 0);
    expect(find.text('Todos os dados foram apagados.'), findsNothing);
  });

  // Signed in, at the top and at the bottom, and signed out, settings
  // passes Flutter's four accessibility guidelines (SPEC 0133).
  for (final (name, theme) in appThemes) {
    testWidgets('screens_meet_guidelines in the $name theme', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          const AuthAccount(
            email: 'agro@example.com',
            displayName: 'Agro Nomo',
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
      await expectMeetsGuidelines(tester);

      // The test font's square glyphs make the rows beside a wide control
      // tall, so the list scrolls until the last row shows.
      await tester.scrollUntilVisible(
        find.text('Versão').hitTestable(),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Versão').hitTestable(), findsOneWidget);
      await expectMeetsGuidelines(tester);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(null, theme: theme));
      await tester.pumpAndSettle();
      expect(find.text('Conta'), findsOneWidget);
      expect(
        find.text('Não vinculada · dados só neste aparelho'),
        findsOneWidget,
      );
      await expectMeetsGuidelines(tester);
      semantics.dispose();
    });
  }

  // "Como capturar bem" opens the capture guide, which returns to Settings
  // with no camera (SPEC 0142).
  testWidgets('guide_reachable_on_demand from settings', (tester) async {
    final store = FakeCaptureGuideStore();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/capture-guide',
          builder: (_, state) =>
              CaptureGuideScreen(beforeCamera: state.extra == true),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const Scaffold(body: Text('ONBOARDING_STUB')),
        ),
      ],
    );
    await tester.pumpWidget(_app(null, captureGuide: store, router: router));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Como fotografar a amostra').hitTestable(),
      200,
    );
    await tester.tap(find.text('Como fotografar a amostra'));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureGuideScreen), findsOneWidget);
    expect(find.text('ONBOARDING_STUB'), findsNothing);
    expect(find.text('Abrir câmera'), findsNothing);

    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureGuideScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(store.markCalls, 1);
  });

  // Play expects the policy to open from inside the app (SPEC 0157, #279).
  group('privacy policy link', () {
    late UrlLauncherPlatform original;
    late _RecordingUrlLauncher launcher;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = _RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() => UrlLauncherPlatform.instance = original);

    Future<void> tapThePolicy(WidgetTester tester) async {
      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(_privacyPolicyLabel).hitTestable(),
        200,
      );
      await tester.tap(find.text(_privacyPolicyLabel));
      await tester.pumpAndSettle();
    }

    test('privacy_policy_url_is_the_published_page', () {
      expect(
        AppLinks.privacyPolicy,
        'https://lukesantossz.github.io/visiosoil-app/privacidade.html',
      );
    });

    testWidgets('settings_lists_the_privacy_policy_under_sobre', (
      tester,
    ) async {
      await tester.pumpWidget(_app(null));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(_privacyPolicyLabel).hitTestable(),
        200,
      );

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(find.text(_privacyPolicyLabel), findsOneWidget);
      expect(top('SOBRE E AJUDA'), lessThan(top(_privacyPolicyLabel)));
      expect(top(_privacyPolicyLabel), lessThan(top('Versão')));
    });

    testWidgets('tapping_the_privacy_policy_opens_it_in_the_browser', (
      tester,
    ) async {
      await tapThePolicy(tester);

      expect(launcher.launches, [
        (AppLinks.privacyPolicy, PreferredLaunchMode.externalApplication),
      ]);
      expect(find.text(_policyFailedMessage), findsNothing);
    });

    testWidgets('a_launch_that_fails_says_so: no app opens it', (tester) async {
      launcher.result = false;
      await tapThePolicy(tester);

      expect(find.text(_policyFailedMessage), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    testWidgets('a_launch_that_fails_says_so: the platform throws', (
      tester,
    ) async {
      launcher.error = PlatformException(code: 'ACTIVITY_NOT_FOUND');
      await tapThePolicy(tester);

      expect(find.text(_policyFailedMessage), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });

    // A build whose plugin did not register reaches no platform at all.
    testWidgets('a_launch_that_fails_says_so: the plugin is missing', (
      tester,
    ) async {
      launcher.error = MissingPluginException('no url_launcher');
      await tapThePolicy(tester);

      expect(find.text(_policyFailedMessage), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  // SPEC 0204: Tema is one row holding a compact control, and the section
  // labels follow PNG 23.
  testWidgets('theme_row_holds_a_compact_control', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('theme-row'));
    expect(
      find.descendant(of: row, matching: find.byIcon(LucideIcons.moon)),
      findsOneWidget,
    );
    final pill = find.descendant(
      of: row,
      matching: find.byKey(const Key('segmented-pill')),
    );
    expect(tester.getSize(pill).height, 32);
    expect(
      (tester.getCenter(pill).dy - tester.getCenter(find.text('Tema')).dy)
          .abs(),
      lessThan(4),
    );

    await tester.tap(find.text('Escuro'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
    expect(container.read(baseThemeModeProvider), ThemeMode.dark);
  });

  testWidgets('section_labels_match_the_mock', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('PREFERÊNCIAS'));
    expect(label.style?.fontSize, 12);
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(label.style?.letterSpacing, 0.6);
    expect(label.style?.color, AppPalette.light.textTertiary);
  });
}

/// Records each launch, and answers with [result] or throws [error].
class _RecordingUrlLauncher extends UrlLauncherPlatform {
  final launches = <(String, PreferredLaunchMode)>[];
  bool result = true;
  Exception? error;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launches.add((url, options.mode));
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

const _privacyPolicyLabel = 'Privacidade e dados';

/// Kept in step with the literal in `settings_screen.dart`.
const _policyFailedMessage =
    'Não foi possível abrir a política de privacidade.';

/// The pt-BR failure message the account tile surfaces on an auth error.
/// Kept in step with the literal in `settings_screen.dart`.
const _failureMessage =
    'Não foi possível concluir a operação. Tente novamente.';

/// The pt-BR message a sign-in tap shows while offline (SPEC 0114).
const _offlineMessage = 'Sem conexão. Entrar com Google precisa de internet.';
