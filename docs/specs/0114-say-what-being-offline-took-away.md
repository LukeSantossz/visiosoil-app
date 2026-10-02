# SPEC: fix(ui): say what being offline took away in the capture preview and sign-in

## Problem

Two screens tell an offline user something misleading (#327):
- **Capture preview.** `LocationService.getAddressFromPosition` turns a failed address lookup, such as one without a network, into `AppStrings.addressUnavailable` ("Localização não disponível"). The preview's location chip shows that string, although GPS returned coordinates and the record will save them. Details (`info_section.dart`) and home (`last_analysis_section.dart`) already show the coordinates in that case.
- **Sign-in.** Settings reports every sign-in failure, offline included, as "Não foi possível concluir a operação. Tente novamente." It never says that signing in needs a connection.

## Design Decision

**The capture preview's location chip follows the rule home already uses.** The preview takes the reading's latitude and longitude next to its address and picks the label in this order:
1. An address that is present, non-empty and not `AppStrings.addressUnavailable` is shown.
2. Otherwise, coordinates that are present are shown, formatted by `Formatters.coordinates`.
3. Otherwise, the chip keeps "Sem localização".

The saved record does not change: it still stores `AppStrings.addressUnavailable` as the address, and details and home already read that as "no address".

**Sign-in checks the connection before it starts.** Tapping "Entrar com Google" first reads `ConnectivityService.current()`.
- **Offline:** the screen shows the SnackBar "Sem conexão. Entrar com Google precisa de internet." and does not start the sign-in.
- **Online:** sign-in runs as today, so a failure keeps the generic message.
- **Unreadable status** (the read throws): sign-in runs as today. An unreadable status is not evidence of being offline, and blocking on it would lock a user out on a plugin failure.

`ConnectivityPlusService` calls a device with no active interface offline. A sign-in in that state cannot reach Google, so refusing it up front loses nothing. A device whose interface is up but has no internet still reads online and still gets the generic message. That is the documented limit of `ConnectivityService`, not something this spec changes.

## Alternatives Considered

- **Check the connection after a failed sign-in and pick the message then.** Rejected: the attempt still runs, and the account picker can open only to fail. The same listener also handles sign-out, so a connection message there would need a separate check of which action failed.
- **Move the check into `AuthNotifier` with a typed offline error.** Rejected as larger than the gap: the notifier would gain a dependency and an error type that only this screen reads. PR #328 also changes `AuthNotifier`.
- **Note "endereço não buscado offline" next to the coordinates.** Rejected: the chip is one ellipsized line over the photograph, and the coordinates alone already say that the location was captured.
- **Backfill the address once the device is back online.** Out of scope, as #327 records.

## Scope

- Includes:
  - `lib/core/features/capture/widgets/capture_image_preview.dart`: the `latitude` and `longitude` parameters, and the label rule.
  - `lib/core/features/capture/capture_screen.dart`: pass `_state.latitude` and `_state.longitude` to the preview.
  - `lib/core/features/settings/settings_screen.dart`: the connection check on the sign-in tap, and its message.
  - Tests in `test/features/capture/capture_widgets_test.dart`, `test/features/capture/capture_screen_test.dart` and `test/features/settings/settings_screen_test.dart`.
- Does NOT include:
  - `LocationService`, `SoilRecord`, `AuthNotifier`, `AuthService` or `ConnectivityService`, which this spec reads and does not change.
  - Sign-out's message.
  - Backfilling the address of a record saved offline.

## Acceptance Criteria

- `the_preview_shows_coordinates_when_only_the_address_failed`: with an image, the address `AppStrings.addressUnavailable` and coordinates `-23.5, -46.6`, the preview shows `Formatters.coordinates(-23.5, -46.6)` and no "Localização não disponível".
- `the_preview_keeps_its_fallback_without_a_location`: with an image, no address and no coordinates, the preview shows "Sem localização".
- `the_preview_shows_a_resolved_address`: with an image, an address and coordinates, the preview shows the address and not the coordinates.
- `the_capture_screen_shows_coordinates_when_geocoding_failed`: a capture whose location reading has coordinates and the address `AppStrings.addressUnavailable` shows the coordinates in the chip.
- `signing_in_offline_names_the_missing_connection`: with an injected connectivity service that reads offline, tapping "Entrar com Google" shows "Sem conexão. Entrar com Google precisa de internet.", does not show the generic message, and does not call `AuthService.signIn`.
- `an_online_sign_in_failure_keeps_the_generic_message`: with connectivity reading online and `signIn` throwing, the generic message shows, as before.
- `an_unreadable_connection_still_tries_to_sign_in`: with a connectivity read that throws, tapping "Entrar com Google" calls `AuthService.signIn`.

## Reproducibility

`flutter test test/features/capture/ test/features/settings/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumes the capture state holds coordinates whenever it holds an address, because `_defaultLocate` returns both from one reading or throws. The preview does not rely on it: it checks each value.
- PR #328 (SPEC 0113) also edits `settings_screen.dart` and its test. This spec only touches the sign-in tile and the test harness's overrides, so a merge conflict, if any, stays local to those lines.
- The offline check reads interface presence, not reachability, as `ConnectivityService` documents.
