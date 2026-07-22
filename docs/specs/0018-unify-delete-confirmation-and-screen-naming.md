# SPEC: refactor(ui): unify delete confirmation flow and align screen naming

## Problem
The confirm-then-delete destructive dialog is implemented three times with
drifting copy (`history_screen`, `details`, `settings_screen`), and two screens
(`HomePage`, `DetailsPage`) break the `*Screen` / `*_screen.dart` naming the
other six follow.

## Design Decision
Extract a single `confirmDestructiveAction` helper in `lib/core/widgets/` that
shows the shared destructive `AlertDialog` (a plain "Cancelar" and an
error-styled confirm button), parameterized by `title`, `message`, and
`confirmLabel`, and returns the user's choice as `Future<bool>` (false on
cancel/dismiss). Each of the three call sites keeps its own delete operation
(`deleteByIds` / `deleteById` / `deleteAll`) and its own post-action (history and
settings show a snackbar; details shows a snackbar and then navigates back) but
delegates the dialog to the helper. The confirm button uses
`Theme.of(context).colorScheme.error`; this theme wires `colorScheme.error` to
`AppColors.error` (`app_colors.dart`), which is exactly the constant the details
and settings sites use today, so unifying the color is visually identical across
all three. Separately,
rename `HomePage`->`HomeScreen` (`home_page.dart`->`home_screen.dart`) and
`DetailsPage`->`DetailsScreen` (`details.dart`->`details_screen.dart`) with router
and import updates.

## Alternatives Considered
1. A full-flow helper that also runs the delete and shows the snackbar. Rejected:
   the post-action varies (history/settings show a snackbar; details shows a
   snackbar and then navigates back), so a full-flow helper would have to
   parameterize the delete callback AND the post-action, re-coupling what differs;
   extracting only the truly-duplicated dialog keeps the helper small and avoids
   unrequested abstraction.
2. Leave the naming as-is and only unify the dialog. Rejected: the issue pairs
   both because they are small mechanical consistency fixes in the same files;
   the `Page`/`Screen` split is a real inconsistency for one architectural role.

## Scope
- Includes:
  - `confirmDestructiveAction` helper in `lib/core/widgets/` + a widget test
    (confirm returns true, cancel/dismiss returns false, confirm button is
    error-styled).
  - Adopt it in `details.dart` (`_confirmAndDelete`), `history_screen.dart`
    (`_showDeleteConfirmation`), and `settings_screen.dart` (`_confirmDeleteAll`),
    removing their inline `AlertDialog` code; each keeps its existing copy passed
    as arguments and its own delete + post-action.
  - Rename `HomePage`->`HomeScreen` and `DetailsPage`->`DetailsScreen`, with file
    renames and updates to `app_router.dart`, `main_screen.dart`, any tests, and
    the stale file-path references in `README.md`, `CLAUDE.md`, and
    `docs/architecture/research-agent.md` that pointed at the old files.
  - Screen-level delete-flow tests for all three call sites (a confirmed-delete
    test that asserts the delete operation ran and the post-action fired, plus a
    cancel test that asserts nothing was deleted), added in response to the R2
    review so the refactored flows are covered end to end rather than by
    inspection alone. This needs recording delete counters on the shared
    `FakeSoilRecordRepository` test double, and a minimal `GoRouter` harness for
    the details flow's `context.go('/')` post-action.
- Does NOT include:
  - Changing any dialog copy, button labels, or snackbar text (byte-preserved).
  - Changing the delete operations or the details navigate-back behaviour.
  - Renaming any other screen or touching routes' paths (only the class/file
    names change; `/` and `/details` paths stay).

## Acceptance Criteria
- `confirmDestructiveAction` exists; a widget test asserts it returns true on
  confirm, false on cancel and on barrier dismiss, and styles the confirm button
  with the error color.
- The three call sites contain no inline delete-confirmation `AlertDialog`; each
  calls the helper (verifiable: only the helper builds the destructive dialog).
- No `HomePage`/`DetailsPage` symbols and no `home_page.dart`/`details.dart` files
  remain; `HomeScreen`/`DetailsScreen` and `home_screen.dart`/`details_screen.dart`
  exist; `app_router.dart` and `main_screen.dart` reference the new names; and no
  doc still links to the old file paths.
- Each of the three delete flows has a screen-level test proving the confirmed
  path runs its delete operation and post-action, and that cancelling deletes
  nothing (verified non-tautological by mutation: breaking the confirm guard
  turns each confirmed-delete test red).
- `flutter analyze` and `flutter test` are green.

## Reproducibility
Toolchain Flutter 3.44.1 / Dart 3.12.1. `flutter analyze && flutter test`.

## Risks and Assumptions
- Assumption: the three call sites' copy differs only in title/message/confirm
  label (verified from the sources), so a title/message/confirmLabel-parameterized
  helper covers all three without losing wording.
- Risk: file renames can leave stale imports. Mitigated by `flutter analyze`
  (unresolved imports fail) and a grep for the old names.
- Confirmed at implementation time: `details.dart`'s delete path shows a snackbar
  (`'Registro excluído.'`) and then navigates back with `context.go('/')`. The
  helper change preserves that exact post-action (both the snackbar and the
  navigation); only the dialog is delegated.
