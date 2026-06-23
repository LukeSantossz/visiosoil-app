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
  _FakeAuthService(this.restored);

  final AuthAccount? restored;
  AuthAccount? _current;

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Future<AuthAccount?> restoreSession() async {
    _current = restored;
    return restored;
  }

  @override
  Future<AuthAccount?> signIn() async => restored;

  @override
  Future<void> signOut() async => _current = null;

  @override
  Future<String?> accessToken() async => null;
}

Widget _app(AuthAccount? account) {
  return ProviderScope(
    overrides: [
      authServiceProvider.overrideWithValue(_FakeAuthService(account)),
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
}
