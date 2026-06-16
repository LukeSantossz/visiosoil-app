// Tests for the Riverpod auth-state layer: default signed-out, and transitions
// on sign-in / sign-out, using a fake AuthService.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/auth/auth_account.dart';
import 'package:visiosoil_app/core/services/auth/auth_service.dart';
import 'package:visiosoil_app/providers/auth_provider.dart';

class _FakeAuthService implements AuthService {
  AuthAccount? restored;
  AuthAccount? nextSignIn;
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
    _current = nextSignIn;
    return nextSignIn;
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }

  @override
  Future<String?> accessToken() async => null;
}

ProviderContainer _containerWith(_FakeAuthService fake) {
  final container = ProviderContainer(
    overrides: [authServiceProvider.overrideWithValue(fake)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('auth_state_defaults_to_signed_out', () async {
    final container = _containerWith(_FakeAuthService());

    final state = await container.read(authNotifierProvider.future);

    expect(state.isSignedIn, isFalse);
    expect(state.account, isNull);
  });

  test('sign_in_transitions_to_signed_in', () async {
    final fake = _FakeAuthService()
      ..nextSignIn = const AuthAccount(email: 'a@b.com', displayName: 'A');
    final container = _containerWith(fake);
    await container.read(authNotifierProvider.future);

    await container.read(authNotifierProvider.notifier).signIn();

    final state = container.read(authNotifierProvider).requireValue;
    expect(state.isSignedIn, isTrue);
    expect(state.account?.email, 'a@b.com');
  });

  test('sign_out_transitions_to_signed_out', () async {
    final fake = _FakeAuthService()
      ..restored = const AuthAccount(email: 'a@b.com', displayName: 'A');
    final container = _containerWith(fake);
    final initial = await container.read(authNotifierProvider.future);
    expect(initial.isSignedIn, isTrue);

    await container.read(authNotifierProvider.notifier).signOut();

    final state = container.read(authNotifierProvider).requireValue;
    expect(state.isSignedIn, isFalse);
  });
}
