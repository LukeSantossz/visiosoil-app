// Widget tests for the Settings account tile: shows a sign-in affordance when
// signed out and the account identity + sign-out when signed in.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';
import 'package:visiosoil_app/core/constants/app_strings.dart';
import 'package:visiosoil_app/core/data/repositories/soil_record_repository.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/core/services/error_report_store.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';
import 'package:visiosoil_app/providers/error_report_provider.dart';
import 'package:visiosoil_app/providers/soil_record_repository_provider.dart';

import '../../support/fake_soil_record_repository.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService(
    this.restored, {
    this.signInError,
    this.signOutError,
    this.signOutClearsBeforeError = false,
  });

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

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Future<AuthAccount?> restoreSession() async {
    _current = restored;
    return restored;
  }

  @override
  Future<AuthAccount?> signIn() async {
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
  }) async =>
      'relatorio $appVersion';

  @override
  Future<void> clear() async {
    clearCalls++;
    empty = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the share sheet was handed.
class _RecordingSharePlatform extends SharePlatform {
  ShareParams? received;

  @override
  Future<ShareResult> share(ShareParams params) async {
    received = params;
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

Widget _app(
  AuthAccount? account, {
  Object? signInError,
  Object? signOutError,
  bool signOutClearsBeforeError = false,
  SoilRecordRepository? repository,
  ErrorReportStore? errorReport,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(
        _FakeAuthService(
          account,
          signInError: signInError,
          signOutError: signOutError,
          signOutClearsBeforeError: signOutClearsBeforeError,
        ),
      ),
      packageInfoProvider.overrideWith(
        (ref) async => PackageInfo(
          appName: 'VisioSoil',
          packageName: 'app.visiosoil',
          version: '2.0.0',
          buildNumber: '2',
        ),
      ),
      if (repository != null)
        soilRecordRepositoryProvider.overrideWithValue(repository),
      errorReportStoreProvider
          .overrideWithValue(errorReport ?? _FakeErrorReportStore()),
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
  late _RecordingSharePlatform sharePlatform;

  setUpAll(() {
    // `SharePlus.instance` memoizes `SharePlatform.instance` on first use, so
    // one fake is installed and cleared per test.
    sharePlatform = _RecordingSharePlatform();
    SharePlatform.instance = sharePlatform;
  });

  setUp(() => sharePlatform.received = null);

  testWidgets('settings_shows_sign_in_when_signed_out', (tester) async {
    await tester.pumpWidget(_app(null));
    await tester.pumpAndSettle();

    expect(find.text('Entrar com Google'), findsOneWidget);
  });

  testWidgets('settings_shows_account_when_signed_in', (tester) async {
    await tester.pumpWidget(
      _app(const AuthAccount(email: 'agro@example.com', displayName: 'Agro Nomo')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agro Nomo'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('settings_shows_failure_snackbar_when_sign_in_throws',
      (tester) async {
    await tester.pumpWidget(_app(null, signInError: Exception('oauth failed')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Entrar com Google'));
    await tester.pump(); // start sign-in (loading)
    await tester.pump(); // async throws -> error state -> listener fires
    await tester.pump(); // build the SnackBar

    expect(find.text(_failureMessage), findsOneWidget);
    // The tile stays on the sign-in affordance, so the user can retry.
    expect(find.text('Entrar com Google'), findsOneWidget);
  });

  testWidgets('settings_shows_failure_snackbar_when_sign_out_throws',
      (tester) async {
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
    expect(find.text('Agro'), findsOneWidget);
    expect(find.text('Sair'), findsOneWidget);
    expect(find.text('Entrar com Google'), findsNothing);
  });

  testWidgets('settings_shows_signed_out_when_sign_out_clears_then_remote_fails',
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
    expect(find.text('Entrar com Google'), findsOneWidget);
    expect(find.text('Sair'), findsNothing);
  });

  testWidgets('settings_no_failure_snackbar_on_successful_sign_out',
      (tester) async {
    await tester.pumpWidget(
      _app(const AuthAccount(email: 'agro@example.com', displayName: 'Agro')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sair'));
    await tester.pump();
    await tester.pump();

    expect(find.text(_failureMessage), findsNothing);
    expect(find.text('Entrar com Google'), findsOneWidget);
  });

  testWidgets('confirming apagar tudo deletes all records and shows a snackbar',
      (tester) async {
    final repository = FakeSoilRecordRepository();
    await tester.pumpWidget(_app(null, repository: repository));
    await tester.pumpAndSettle();

    // Open the shared destructive dialog from the delete-all tile.
    await tester.tap(find.text('Apagar todos os dados'));
    await tester.pumpAndSettle();

    // Confirm; the delete-all runs and its own snackbar is shown.
    await tester.tap(find.text('Apagar tudo'));
    await tester.pumpAndSettle();

    expect(repository.deleteAllCalls, 1);
    expect(find.text('Todos os dados foram apagados.'), findsOneWidget);
  });

  testWidgets('erasing_all_data_clears_the_error_report', (tester) async {
    // SPEC 0110: the report is data the app keeps, so erasing everything
    // erases it too, and the row then has nothing to send.
    final report = _FakeErrorReportStore(empty: false);
    await tester.pumpWidget(_app(
      null,
      repository: FakeSoilRecordRepository(),
      errorReport: report,
    ));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.errorReportNothingToSend), findsNothing);

    await tester.tap(find.text('Apagar todos os dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar tudo'));
    await tester.pumpAndSettle();

    expect(report.clearCalls, 1);
    expect(find.text(AppStrings.errorReportNothingToSend), findsOneWidget);
  });

  group('settings_shares_the_error_report', () {
    // SPEC 0110: the row shares the report as a text file when it holds an
    // entry, and is disabled, saying so, when it holds none.
    testWidgets('with entries, the row shares the report as a file',
        (tester) async {
      await tester.pumpWidget(
        _app(null, errorReport: _FakeErrorReportStore(empty: false)),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.errorReportPrivacy), findsOneWidget);
      await tester.ensureVisible(find.text(AppStrings.errorReportTitle));
      await tester.tap(find.text(AppStrings.errorReportTitle));
      await tester.pumpAndSettle();

      final params = sharePlatform.received;
      expect(params, isNotNull, reason: 'nothing reached the share sheet');
      expect(params!.text, AppStrings.errorReportShareCaption);
      expect(params.fileNameOverrides, [errorReportFileName]);
      final file = params.files!.single;
      expect(file.mimeType, 'text/plain');
      expect(utf8.decode(await file.readAsBytes()), 'relatorio 2.0.0+2');
    });

    testWidgets('without entries, the row is disabled and says so',
        (tester) async {
      await tester.pumpWidget(
        _app(null, errorReport: _FakeErrorReportStore()),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.errorReportNothingToSend), findsOneWidget);
      await tester.ensureVisible(find.text(AppStrings.errorReportTitle));
      await tester.tap(find.text(AppStrings.errorReportTitle));
      await tester.pumpAndSettle();

      expect(sharePlatform.received, isNull);
    });
  });

  testWidgets('cancelling apagar tudo deletes nothing', (tester) async {
    final repository = FakeSoilRecordRepository();
    final report = _FakeErrorReportStore(empty: false);
    await tester.pumpWidget(
      _app(null, repository: repository, errorReport: report),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Apagar todos os dados'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(repository.deleteAllCalls, 0);
    expect(report.clearCalls, 0);
    expect(find.text('Todos os dados foram apagados.'), findsNothing);
  });
}

/// The pt-BR failure message the account tile surfaces on an auth error.
/// Kept in step with the literal in `settings_screen.dart`.
const _failureMessage = 'Não foi possível concluir a operação. Tente novamente.';
