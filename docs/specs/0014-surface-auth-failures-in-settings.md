# SPEC: fix(auth): surface sign-in and sign-out failures in settings account tile

## Problem
When Google sign-in or sign-out fails, the user gets no feedback and a failing
sign-out can leave OAuth credentials in secure storage while the UI shows the
user as signed out.

## Design Decision
Route both `signIn` and `signOut` through `AsyncValue.guard` so failures land in
an observed `AsyncError` state instead of being swallowed or thrown uncaught,
and surface them with a `ref.listen` `SnackBar` in the account tile. In
`GoogleAuthService.signOut`, clear the local credential store and the in-memory
account *before* calling the remote revoke, so a throwing revoke can never leave
credentials on disk; the remote error still propagates so the UI can report it.
On a sign-out failure the notifier re-derives the displayed state from the
service's `currentAccount`: if the local store clear itself failed the account is
still present, so the tile keeps showing the signed-in state (never a false
"signed out" while credentials remain); if only the remote revoke failed, local
credentials are already gone and the tile shows signed-out. The tile therefore
renders from the last known auth state carried on the error (`copyWithPrevious`)
rather than mapping every error to the sign-in affordance.

## Alternatives Considered
1. Put `_store.clear()` / `_currentAccount = null` in a `finally` after the
   remote revoke (revoke-first, clear-after). Rejected: clearing local *first*
   is strictly safer if the process is killed between the remote call and the
   local clear — the device never retains credentials past the sign-out intent.
   Both guarantee cleanup on a normal throw; clear-first also wins the
   kill-mid-way case.
2. Swallow the remote-revoke error inside `GoogleAuthService.signOut`
   (log-and-return). Rejected: the UI could then never tell the user the remote
   session may still be live; propagating lets the notifier surface a `SnackBar`
   while local storage is already clean.
3. Per-operation failure messages (distinct copy for sign-in vs sign-out).
   Rejected: requires tracking the last operation as extra notifier state for a
   marginal benefit; one generic "tente novamente" message fully resolves the
   "failure is invisible" defect. Revisit if product wants tailored copy.
4. Inline error text on the tile instead of a `SnackBar`. Rejected: the tile has
   no persistent error slot; an inline message would need a new stateful surface,
   whereas a `SnackBar` is the app's existing feedback pattern (already used by
   "Apagar todos os dados") and needs no new widget.
5. Map every auth error to the sign-in affordance (the naive tile behavior).
   Rejected: a failed `_store.clear()` leaves credentials on disk, and showing
   the sign-in tile then reports "signed out" while `accessToken()` can still
   return a usable token — the exact defect this issue targets. The tile instead
   renders from the last known state carried on the error.

## Scope
- Includes:
  - Reorder `GoogleAuthService.signOut` to clear the local store and in-memory
    account before the remote revoke; the remote error still propagates.
  - Wrap `AuthNotifier.signOut` in `AsyncValue.loading()` + `AsyncValue.guard`
    (mirrors `signIn`).
  - Add a `ref.listen(authNotifierProvider, ...)` in `_AccountTile` that shows a
    failure `SnackBar` on an auth `AsyncError`, guarded to fire only on a
    loading -> error transition.
  - Failure-path tests at the service, provider, and widget layers.
- Does NOT include:
  - `google_sign_in` 7.x migration (#119) — stays on 6.x.
  - Any change to the sign-in success flow, `restoreSession`, or
    `accessToken`/refresh.
  - Retry buttons, per-operation messages, or inline error surfaces on the tile.
  - R8 keep rules or the release-mode smoke test (#69).
  - Centralizing pt-BR strings into `AppStrings`.

## Acceptance Criteria
Service — `test/services/google_auth_service_test.dart`:
- `sign_out_clears_local_credentials_even_when_remote_revoke_throws`: with the
  gateway's `signOut` throwing, `service.signOut()` propagates the error, and
  afterwards `store.read()` is null and `currentAccount` is null.

Provider — `test/providers/auth_provider_test.dart`:
- `sign_out_failure_is_captured_as_error_state_not_thrown`: with the
  `AuthService.signOut` throwing, `notifier.signOut()` completes with no uncaught
  error and `read(authNotifierProvider).hasError` is true.
- `sign_in_failure_is_captured_as_error_state`: with `AuthService.signIn`
  throwing, after `notifier.signIn()`, `read(authNotifierProvider).hasError` is
  true. (Locks the existing `guard` behavior.)
- `sign_out_local_clear_failure_keeps_signed_in_state`: `signOut` throws with
  `currentAccount` still set (a store-clear failure); the resolved state has an
  error AND is still signed in.
- `sign_out_remote_revoke_failure_resolves_to_signed_out`: `signOut` throws
  after `currentAccount` was cleared (only the remote revoke failed); the
  resolved state has an error AND is signed out.

Widget — `test/features/settings/settings_screen_test.dart`:
- `settings_shows_failure_snackbar_when_sign_in_throws`: fake `signIn` throws;
  tapping "Entrar com Google" shows a `SnackBar` with the failure message and the
  tile still shows "Entrar com Google".
- `settings_shows_failure_snackbar_when_sign_out_throws`: signed in; fake
  `signOut` throws before clearing local (credentials remain); tapping "Sair"
  shows the failure `SnackBar` and the tile keeps showing the account, not
  "Entrar com Google".
- `settings_no_failure_snackbar_on_successful_sign_out`: signed in; tapping
  "Sair" leaves the tile showing "Entrar com Google" and shows no failure
  `SnackBar`.

## Reproducibility
Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned to CI).
```
flutter analyze
flutter test test/services/google_auth_service_test.dart \
             test/providers/auth_provider_test.dart \
             test/features/settings/settings_screen_test.dart
flutter test
```
No randomness; no seed needed.

## Risks and Assumptions
- Assumption: mapping an `AsyncError` to the sign-in tile is the correct visual
  after a sign-out failure, because the local store is now cleared, so the user
  is genuinely signed out locally. Invalidated if product wants the signed-in
  view preserved on a remote-revoke failure (rejected here — credential hygiene
  wins).
- Assumption: one generic pt-BR failure message is acceptable UX. Invalidated if
  product wants per-operation copy (Alternative 3).
- Assumption: `ScaffoldMessenger.of(context)` from `_AccountTile` resolves the
  `MaterialApp` messenger in both the app and widget tests (the tile sits under a
  `Scaffold` inside `MaterialApp`).
- Risk: a `ref.listen` that shows a `SnackBar` must fire only on a
  loading -> error transition, or an unrelated rebuild could re-toast a stale
  error. Guarded by checking the previous value was loading.
- Note for the Gate: the clear-before-revoke ordering is a credential-hygiene
  decision that is surprising without context but easily reversible (a 3-line
  reorder). Flagging it for the Developer to decide whether it warrants an ADR;
  the default proposal is to record it in the spec archive only, not a new ADR.
- Residual limitation: if `_store.clear()` itself throws, the on-disk session
  genuinely survives (a secure-storage delete cannot be forced), so the honest
  outcome is to keep the signed-in view plus the failure `SnackBar`, not to claim
  signed-out. `restoreSession` on the next launch will read the surviving session
  and sign the user back in, which is correct given the credentials still exist.
