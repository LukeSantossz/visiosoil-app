# SPEC: feat(auth): let a signed-in user delete their account from settings

## Problem

Google Play requires an app that lets users create an account to let them
delete it from inside the app (#278). VisioSoil ships Google sign-in (#273), and
Settings offers only "Sair". Signing out keeps the app's Google grant: the next
sign-in goes straight through, and the app still appears under the user's
Google account connections. Nothing in the app removes that grant.

## Design Decision

**Settings gains "Excluir conta" under CONTA while signed in. Behind the shared
destructive confirmation, it clears the stored session and revokes the app's
Google grant.**

**What the account is.** There is no VisioSoil server, so the account is
exactly two things: the session in the secure store (name and email, SPEC 0106)
and the grant Google holds for the app. Deleting the account removes both.

**The soil records stay.** The Developer chose this on 2026-10-02. While sync
is unwired, records are not tied to the account: they are written the same way
signed in or out, and nothing uploads them. "Apagar todos os dados" remains the
way to erase them, and the confirmation names it. This narrows #278's proposal,
which also erased the records.

**The service:**

- `AuthService.deleteAccount()` is new.
- `GoogleAuthService.deleteAccount()` clears the stored session and the
  in-memory account first, then calls `GoogleSignInGateway.disconnect()`. This
  is the order `signOut` uses, so a failing remote call can never leave a
  usable session on the device.
- `GoogleSignInGatewayImpl.disconnect()` calls `GoogleSignIn.disconnect()`,
  which revokes the grant through Play services' `revokeAccess` and signs the
  plugin out.
- **A failed revoke is named.** If `disconnect` throws, `deleteAccount` throws
  `AccountNotRevokedException`. A failure to clear the local session propagates
  as it is, and leaves the account in place, as `signOut` does.

**The state.** `AuthNotifier.deleteAccount()` mirrors `signOut`: loading, then
signed out, or an error.

**The screen:**

- The tile is "Excluir conta", in the error colour, below the account row. It
  shows only when signed in.
- The confirmation reads: "Sua conta Google será desconectada do VisioSoil e o
  acesso concedido ao app será revogado. Seus registros de solo continuam neste
  aparelho; para apagá-los, use \"Apagar todos os dados\"." Its button is
  "Excluir conta".
- On success, a snackbar reads "Conta excluída do VisioSoil."
- The account tile's existing error listener tells the two failures apart:
  - `AccountNotRevokedException` reads "A conta saiu deste aparelho, mas o
    Google não confirmou a revogação. Revogue o acesso em
    myaccount.google.com/connections." The account is already gone from the
    device, so "try again" would be wrong.
  - Any other error keeps the generic message, and the tile keeps the account.

**The web half of #278 is not here.** The page that explains deletion without
the app is published with the privacy policy (#276), on GitHub Pages from
`site/`, as the Developer chose on 2026-10-02. #278 stays open until that page
exists.

## Alternatives Considered

- **Also erase the records (#278's proposal).** Declined by the Developer. The
  records are not account data while sync is unwired, and erasing them is
  already one tap away under DADOS.
- **Sign out only.** Rejected. It leaves the grant in place, which is what
  deletion has to remove.
- **Revoke first, then clear locally.** Rejected, for the reason `signOut`
  already records: a revoke that fails offline would leave a session on the
  device.
- **A generic failure message for both cases.** Rejected. After a failed
  revoke the account has already left the device, so "Tente novamente" would
  send the user to a button that is no longer there.

## Scope

- Includes:
  - `lib/core/services/auth/auth_service.dart`: `deleteAccount()` and
    `AccountNotRevokedException`, beside the interface, since the screen
    recognises it and the UI imports only the interface.
  - `lib/core/services/auth/google_auth_service.dart`: `deleteAccount()`.
  - `lib/core/services/auth/google_sign_in_gateway.dart`: `disconnect()`.
  - `lib/providers/auth_provider.dart`: `AuthNotifier.deleteAccount()`.
  - `lib/core/features/settings/settings_screen.dart`: the tile, the
    confirmation, the snackbar and the revoke-failure message.
  - Tests: `test/services/google_auth_service_test.dart`,
    `test/providers/auth_provider_test.dart`,
    `test/features/settings/settings_screen_test.dart`, and the `AuthService`
    fakes that must gain the method.
- Does NOT include:
  - The web page, or the privacy policy (#276).
  - Erasing soil records, cached tips or the error report.
  - Any change to sign-in or sign-out.
  - The google_sign_in 7 migration (#119).

## Acceptance Criteria

- `delete_account_clears_the_session_then_revokes_the_grant`: after
  `deleteAccount`, the store holds no session, `currentAccount` is null, and
  the gateway's `disconnect` ran once, after the clear.
- `delete_account_names_a_failed_revoke_after_clearing_locally`: when
  `disconnect` throws, `deleteAccount` throws `AccountNotRevokedException`, and
  the session is already cleared.
- `delete_account_keeps_the_account_when_the_local_clear_fails`: when the
  store's delete throws, that error propagates, `disconnect` does not run, and
  `currentAccount` is unchanged.
- `notifier_delete_account_signs_out`: `AuthNotifier.deleteAccount` ends signed
  out on success, and in an error state on failure.
- `settings_offers_account_deletion_only_when_signed_in`: the tile shows signed
  in and is absent signed out.
- `confirming_excluir_conta_deletes_the_account`: confirming calls
  `deleteAccount`, shows the success snackbar and the sign-in tile; cancelling
  calls nothing.
- `a_failed_revoke_says_where_to_revoke`: an `AccountNotRevokedException` shows
  the revoke message, not the generic one, and the tile shows signed out.
- `flutter analyze`, the full suite and `mf check` pass.

## Reproducibility

```sh
flutter test test/services/google_auth_service_test.dart \
  test/providers/auth_provider_test.dart \
  test/features/settings/settings_screen_test.dart
flutter analyze && flutter test && mf check
```

## Risks and Assumptions

- **Assumption: `revokeAccess` finds the account after an app restart.** The
  app restores its session from the secure store without calling
  `signInSilently`, so the plugin's Dart side has no current user. Play
  services remembers the last signed-in account across restarts, and
  `revokeAccess` acts on it. This is verified on a device once sign-in works in
  a Play-signed build (#275). If it fails, the user gets the revoke message and
  the link, not a silent half-deletion.
- **Risk: the user expects their records gone.** The confirmation says they
  stay, and names "Apagar todos os dados".
- **Merge order:** 0113 merges after 0109–0112, since `main`'s contiguity check
  fails on a gap.
