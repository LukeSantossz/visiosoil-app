# SPEC: fix(onboarding): mark the linked account with a check

## Problem

The onboarding's linked-account row ends with a cloud carrying a check, which reads as "your data is backed up".

- **What it draws.** `_LinkedAccountRow` in `onboarding_screen.dart` ends with `LucideIcons.cloudCheck`, 20 dp, in `onSurface`, after PNG 04.
- **Why it is wrong.** No sync backend exists (see `CLAUDE.md`, Current Limitations), so nothing reaches the cloud. The icon promises a backup the app does not make. SPEC 0235 and SPEC 0236 already hide the sync status and the sync action for the same reason.
- **The same icon means "sent" elsewhere.** `StatusPill` uses `cloudCheck` for a record that reached the backend. On the onboarding it would mean something else.
- **The visual review names it.** The unslop review of 2026-10-31 found it, as a follow-up to item 1.
- **Decision.** On 2026-10-31 the Developer chose to replace it with a plain check.

## Design Decision

**The linked-account row ends with `LucideIcons.circleCheck`, 20 dp, in `onSurface`. It says the account is linked, and nothing about a backup.**

- Only the icon changes. The row's size, colours and text stay as they are.
- `StatusPill` keeps `cloudCheck` for a sent record.

## Alternatives Considered

- **Remove the icon.** Not chosen by the Developer: the check confirms the step worked.
- **Keep it.** Rejected by the Developer: it promises a backup that does not exist.

## Scope

- Includes:
  - `lib/core/features/onboarding/onboarding_screen.dart`, `_LinkedAccountRow` only;
  - `test/features/onboarding/onboarding_mock_test.dart`.
- Does NOT include:
  - `StatusPill` and Perfil, which keep `cloudCheck`;
  - the mock, PNG 04, which still draws the cloud.

## Acceptance Criteria

- `test/features/onboarding/onboarding_mock_test.dart`:
  - `linked_row_matches_the_mock`, amended: the row shows one `LucideIcons.circleCheck` of 20 dp, and no `LucideIcons.cloudCheck`.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test test/features/onboarding/onboarding_mock_test.dart`, then `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- **Departs from the mock.** PNG 04 draws the cloud. The Developer chose the review over the mock here, and the mock is not changed.
- **A backend later.** When one is wired, a separate decision may bring the cloud back here.
