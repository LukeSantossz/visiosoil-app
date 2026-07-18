# SPEC: fix(auth): guard persisted-session decode so a corrupt blob degrades to signed-out

## Problem

`SecureCredentialStore.read()` decodes the persisted session with an unguarded `jsonDecode` +
`AuthSession.fromJson`, so a malformed, partial, or schema-mismatched blob throws out of the single
point every auth path reads through, and `accessToken()` throws on every call instead of degrading
to signed-out.

## Design Decision

Guard the decode at `SecureCredentialStore.read()`, the one place the blob is parsed, so both
`restoreSession()` and `accessToken()` inherit the fix and any future caller does too. On a decode
failure, delete the bad blob, log through `developer.log` (the pattern already used across
`lib/core/services/`), and return `null` — the store's existing "no session" result. Catch narrowly:
`FormatException` and `TypeError` together cover all three documented throws (malformed JSON, a
non-map top-level value, and a null or mistyped field inside `fromJson`), satisfying the
narrowest-catch rule in `code_conventions.md:51`. Separately, guard `AuthNotifier.build()` with
`try`/`catch` so a storage-level failure resolves to signed-out as its doc comment already promises.

## Alternatives Considered

- **Catch-all `catch (e)` in `read()`** — rejected: `code_conventions.md:51` requires the narrowest
  error type the language allows and reserves catch-alls for boundaries. `FormatException` plus
  `TypeError` is both narrow and complete against the three throws the code can actually produce, so
  the broad catch buys nothing except hiding an unanticipated failure.
- **Return `null` but leave the bad blob in place** — rejected: every later `read()` would repeat the
  same failed decode and re-log, and the store would stay wedged until the user happened to sign in
  or out. Deleting makes the failure self-heal at the point it is detected.
- **Guard in `restoreSession()` and `accessToken()` instead** — rejected: it duplicates the same
  recovery in two callers, leaves `read()` itself throwing for anyone who calls it later, and splits
  one invariant across three files.
- **Make `AuthSession.fromJson` tolerant (nullable fields, `DateTime.tryParse`)** — rejected: it
  pushes validation into the model and makes a half-valid `AuthSession` representable, so a session
  with an empty `accessToken` would flow into the sync layer as if it were usable. Failing the parse
  and treating the result as "no session" keeps the invalid state unrepresentable.
- **Use `AsyncValue.guard` in `AuthNotifier.build()`, as the issue suggests** — rejected on API
  grounds: `AsyncValue.guard` returns `Future<AsyncValue<T>>` while `build()` must return
  `Future<AuthState>`. `try`/`catch` is the equivalent that fits the signature; `guard` stays correct
  where it is already used, in `signIn()`.

## Scope

- Includes:
  - `SecureCredentialStore.read()`: narrow guard, delete the bad blob, log, return `null`.
  - `AuthNotifier.build()`: `try`/`catch` around `restoreSession()`, resolving to signed-out.
  - Regression tests that a corrupt blob makes `read()`, `restoreSession()`, and `accessToken()`
    resolve to `null` rather than throw, and that the bad blob is cleared.
- Does NOT include:
  - Any change to `AuthSession`'s shape, fields, or `fromJson`/`toJson` contract.
  - Surfacing the corruption in the UI. `settings_screen.dart:155` already renders the sign-in tile
    on `error:`, and after this change the state resolves to signed-out rather than error anyway.
  - Sign-in/sign-out failure messaging (#67) or R8 keep rules (#69), the other two issues in this
    milestone.
  - Versioning or migrating the persisted blob against future `AuthSession` schema changes.

## Acceptance Criteria

- `secure_credential_store_returns_null_when_blob_is_malformed_json`
- `secure_credential_store_returns_null_when_blob_is_not_a_json_object`
- `secure_credential_store_returns_null_when_a_required_field_is_missing_or_mistyped`
- `secure_credential_store_returns_null_when_expires_at_is_unparseable`
- `secure_credential_store_deletes_the_bad_blob_so_the_next_read_is_empty`
- `secure_credential_store_still_roundtrips_a_valid_session`
- `google_auth_service_restore_session_returns_null_on_a_corrupt_blob`
- `google_auth_service_access_token_returns_null_on_a_corrupt_blob`
- `auth_notifier_build_resolves_to_signed_out_when_restore_throws`

## Reproducibility

- `flutter test test/services/secure_credential_store_test.dart` and the auth provider/service tests.
- Red first: each criterion is written as a failing test against the current unguarded code before
  the implementation lands, per the Testing section of `code_conventions.md`. The corrupt-blob cases
  fail today by throwing `FormatException` or `TypeError` out of `read()`.
- No randomness; no seed. Versions: Flutter 3.44.1 / Dart 3.12.1.
- The existing `_InMemorySecureStorage` fake in `test/services/secure_credential_store_test.dart:11`
  is the vehicle: it writes an arbitrary `String`, which is exactly what a corrupt blob is.

## Risks and Assumptions

- Assumption: deleting the bad blob on a failed decode is safe because an `AuthSession` that cannot
  be parsed cannot be used, and the refresh token lives with the platform plugin rather than in this
  blob (`auth_session.dart:1-6`), so nothing recoverable is destroyed.
- Assumption: `FormatException` and `TypeError` are exhaustive for the decode path. If a future
  `AuthSession` field introduces a different throw, the guard misses it — mitigated because the
  criteria pin one test per throw shape, so an added field without an added test is visible.
- Risk: the issue's stated impact is overstated in two places, which could inflate this change's
  scope if taken at face value. There is no `requireValue` anywhere in `lib/`, and
  `settings_screen.dart:155` already handles `error:`, so item 3 is a contract inconsistency rather
  than a user-visible defect; and `signIn()`/`signOut()` do overwrite or clear the blob, so it is not
  true that the state never self-heals. This spec fixes the real defect and records the correction
  rather than widening scope to match the issue's framing.
- What would invalidate this spec: `AuthSession` gaining a schema version, which would replace
  "delete on failed decode" with a migration path.
