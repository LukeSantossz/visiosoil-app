// Pins what Google sign-in asks the user for (SPEC 0106, #274). Building the
// gateway touches no platform channel, so the default configuration is read
// directly.
import 'package:flutter_test/flutter_test.dart';
import 'package:visiosoil_app/core/services/auth/google_sign_in_gateway.dart';

void main() {
  test('gateway_requests_no_scope_beyond_the_default_sign_in', () {
    // An empty list is Google's default sign-in: identity, email and profile.
    // Drive access belongs to the Drive backend, which asks when it first
    // syncs (#55), so the consent screen at sign-in names no Drive grant.
    final scopes = GoogleSignInGatewayImpl().scopes;

    expect(scopes, isEmpty);
    expect(scopes.where((scope) => scope.contains('drive')), isEmpty);
  });
}
