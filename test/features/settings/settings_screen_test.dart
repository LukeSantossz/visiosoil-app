// Widget tests for the Settings account tile: shows a sign-in affordance when
// signed out and the account identity + sign-out when signed in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:visiosoil_app/core/features/settings/settings_screen.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  _FakeAuthService(this.restored, {this.signInError, this.signOutError});

  final AuthAccount? restored;

  /// When set, [signIn] throws it, standing in for an OAuth/network failure.
  final Object? signInError;

  /// When set, [signOut] throws it, standing in for a remote revoke failure.
  final Object? signOutError;

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
    if (error != null) throw error;
    _current = null;
  }

  @override
  Future<String?> accessToken() async => null;
}

Widget _app(
  AuthAccount? account, {
  Object? signInError,
  Object? signOutError,
}) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(
        _FakeAuthService(
          account,
          signInError: signInError,
          signOutError: signOutError,
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
    ],
    child: const MaterialApp(home: SettingsScreen()),
  );
}

void main() {
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
}

/// The pt-BR failure message the account tile surfaces on an auth error.
/// Kept in step with the literal in `settings_screen.dart`.
const _failureMessage = 'Não foi possível concluir a operação. Tente novamente.';
