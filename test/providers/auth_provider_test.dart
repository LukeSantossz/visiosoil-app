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

  /// When set, [restoreSession] throws it, standing in for a storage-level
  /// failure the store itself cannot absorb.
  Object? restoreError;

  /// When set, [signIn] throws it, standing in for an OAuth/network failure.
  Object? signInError;

  /// When set, [signOut] throws it, standing in for a sign-out failure.
  Object? signOutError;

  @override
  AuthAccount? get currentAccount => _current;

  @override
  Future<AuthAccount?> restoreSession() async {
    final error = restoreError;
    if (error != null) throw error;
    _current = restored;
    return restored;
  }

  @override
  Future<AuthAccount?> signIn() async {
    final error = signInError;
    if (error != null) throw error;
    _current = nextSignIn;
    return nextSignIn;
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

  test('auth_notifier_build_resolves_to_signed_out_when_restore_throws',
      () async {
    final fake = _FakeAuthService()..restoreError = const FormatException('bad');
    final container = _containerWith(fake);

    // Read the resolved AsyncValue rather than awaiting `.future`: an unguarded
    // throw in build() leaves the provider stuck in loading, so awaiting the
    // future would hang for the full test timeout instead of failing on the
    // assertion.
    container.read(authNotifierProvider);
    await pumpEventQueue();
    final async = container.read(authNotifierProvider);

    // The provider doc promises a failed restore resolves to signed-out rather
    // than to AsyncError.
    expect(async.hasError, isFalse);
    expect(async.value?.isSignedIn, isFalse);
  });

  test('sign_in_failure_is_captured_as_error_state', () async {
    final fake = _FakeAuthService()..signInError = Exception('oauth failed');
    final container = _containerWith(fake);
    await container.read(authNotifierProvider.future);

    await container.read(authNotifierProvider.notifier).signIn();

    // A thrown sign-in must land in an observed error state, not vanish.
    expect(container.read(authNotifierProvider).hasError, isTrue);
  });

  test('sign_out_failure_is_captured_as_error_state_not_thrown', () async {
    final fake = _FakeAuthService()
      ..restored = const AuthAccount(email: 'a@b.com', displayName: 'A')
      ..signOutError = Exception('revoke failed');
    final container = _containerWith(fake);
    await container.read(authNotifierProvider.future);

    // signOut must not rethrow uncaught; the failure is captured in state.
    await container.read(authNotifierProvider.notifier).signOut();

    expect(container.read(authNotifierProvider).hasError, isTrue);
  });
}
