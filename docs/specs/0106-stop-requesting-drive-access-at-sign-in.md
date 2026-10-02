# SPEC: fix(auth): stop requesting Google Drive access at sign-in

## Problem

Signing in asks the user for access to their Google Drive files, and nothing in
the app reads or writes Drive (#274). `GoogleSignInGatewayImpl` builds
`GoogleSignIn(scopes: [drive.file])` for the future Drive backend (#55). So the
consent screen shows a grant the app cannot justify, and the access token it
yields is persisted in secure storage and never used:

- `GoogleAuthService` saves the token in every `AuthSession`.
- `AuthService.accessToken()` refreshes and returns it, and no production code
  calls it. Only tests and test fakes do.

`drive.file` is a non-sensitive scope and needs no verification. Requesting
access no feature uses still runs against Play's User Data policy and Google's
minimum-scope guidance, and #273 decided that sign-in ships in the first
release.

## Design Decision

**Sign in with Google's default scopes only, and hold no token at all until a
feature needs one.**

- **The gateway requests no extra scope.** `GoogleSignIn()` with an empty
  `scopes` list asks for Google's default sign-in: the user's identity, email
  and profile. A `@visibleForTesting` getter exposes the scopes the gateway
  requests, so a test can pin them.
- **The gateway returns the account, not a token.** `signIn()` yields an
  `AuthAccount`, or null on cancel. `account.authentication`, the token and the
  50-minute validity window go. `refresh()` goes too: its only caller was
  `accessToken()`.
- **`AuthSession` holds the account only:** email and display name.
  `accessToken`, `expiresAt` and `isExpiredAt` are removed.
- **`AuthService.accessToken()` is removed**, with its refresh path in
  `GoogleAuthService` and the `clock` parameter that existed only for expiry.
  A method that returns a token for identity scopes would hand the sync layer
  a credential useless for Drive.
- **A session saved before this change loses its token on the next read.** A
  pre-0106 blob still decodes, because the account fields are unchanged. When
  `SecureCredentialStore.read()` finds stored fields the current shape does not
  have, it saves the session again in the current shape, which drops the token
  and the expiry. The user stays signed in, and `restoreSession()` runs at
  startup, so the token leaves the device on the first launch after the update.

**The Drive backend owns its grant.** When #55 lands, it requests `drive.file`
incrementally at its first sync and decides how to hold that token: through
`requestScopes` on `google_sign_in` 6.x, or through the 7.x authorization
client if #119 has migrated by then. Nothing is added for it now.

## Alternatives Considered

- **Keep `accessToken()` and fetch a token on demand instead of persisting
  one.** Rejected. With identity scopes only, the token is useless to any
  backend this app has planned, and the method would have no caller.
- **Discard a pre-0106 session instead of rewriting it.** Rejected. It signs
  the user out to remove two fields, when saving the same account back removes
  them and keeps the user signed in. Discarding stays the path for a blob that
  cannot be decoded (SPEC 0012).
- **Revoke the old grant with `disconnect()` on the next launch.** Rejected.
  The app is not distributed yet, so the only grants are on developer devices.
  A silent revoke would also sign those users out. The Google account's own
  page removes a grant.
- **Move to `google_sign_in` 7.x first (#119).** Rejected for this issue. #119
  is scheduled with #95 so the gateway is rewritten once, and it carries a
  storage-cipher decision for the Developer. This change is the minimal fix on
  6.x, and it leaves less for #119 to migrate.

## Scope

- Includes:
  - `lib/core/services/auth/google_sign_in_gateway.dart`: default scopes,
    `signIn()` returning `AuthAccount?`, `refresh()` and the token removed,
    and a test-visible scope getter.
  - `lib/core/services/auth/auth_session.dart`: email and display name only.
  - `lib/core/services/auth/secure_credential_store.dart`: rewriting a
    pre-0106 session in the current shape.
  - `lib/core/services/auth/auth_service.dart` and `google_auth_service.dart`:
    `accessToken()`, its refresh path and the `clock` parameter removed.
  - Tests:
    - `test/services/google_auth_service_test.dart` and
      `test/services/secure_credential_store_test.dart`, rewritten to the new
      shape;
    - a new `test/services/google_sign_in_gateway_test.dart`;
    - the `accessToken()` overrides deleted from the fakes in
      `test/features/settings/settings_screen_test.dart` and
      `test/providers/auth_provider_test.dart`.
  - `docs/architecture/research-agent.md`: the sentence saying the proxy
    introspects the access token the app holds. Found during implementation:
    after this change the app holds none, so per-user proxy calls wait for the
    ID token of #95.
- Does NOT include:
  - The Drive backend, or any incremental scope request (#55).
  - `google_sign_in` 7.x or `flutter_secure_storage` 10.x (#119).
  - The OAuth client registration Play needs (#275), or account deletion
    (#278).
  - Any UI change. The settings screen shows the account, as it does today.

## Acceptance Criteria

- `gateway_requests_no_scope_beyond_the_default_sign_in`: a default-built
  `GoogleSignInGatewayImpl` requests an empty scope list, so neither
  `drive.file` nor any other Drive scope is asked for.
- `sign_in_persists_the_account_and_no_token`: after `signIn()`, the stored
  blob holds the email and the display name, and no `accessToken` or
  `expiresAt` key.
- `a_session_saved_before_0106_loses_its_token_on_read`: a stored blob with
  `accessToken` and `expiresAt` reads as the same account, and afterwards the
  stored blob has neither key.
- The existing auth tests for sign-in, sign-out, restore, a cancelled sign-in,
  a failed remote sign-out and a corrupt blob keep passing in the new shape.
- `flutter analyze` is clean, the full suite passes, and `mf check` passes.

## Reproducibility

```sh
flutter test test/services/google_sign_in_gateway_test.dart \
  test/services/google_auth_service_test.dart \
  test/services/secure_credential_store_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: an empty `scopes` list is Google's default sign-in.** On
  Android, `google_sign_in_android` 6.2.1, the implementation locked under
  `google_sign_in` 6.3.0, builds `GoogleSignInOptions.DEFAULT_SIGN_IN` with
  `requestEmail()` (`GoogleSignInPlugin.java:212`), and adds a scope only for
  each entry in the list. That covers identity, email and profile. A consent screen on a
  device is the final check, and it belongs to #275, which makes sign-in work
  in the build Play distributes.
- **Risk: a revoked grant is not noticed.** The app restores the stored
  account without asking Google, which is today's behaviour too: nothing
  called `accessToken()`, so nothing ever re-checked. A later feature that
  needs the server will check then.
- **Coordination:** the other session's dark-theme work (0107) edits the
  settings screen. This change touches only the settings test's fake, one
  method.
