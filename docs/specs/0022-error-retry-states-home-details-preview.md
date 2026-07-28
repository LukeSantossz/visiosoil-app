# SPEC: refactor(feedback): add error and retry states to home, details, and preview

## Problem
Home fails silently when the records stream errors (stats and last-analysis just
show empty placeholders), and the Details and Preview screens map both a load
error and a genuinely-absent record to the same no-retry "not found" view, so a
transient failure gives the user no way to recover.

## Design Decision
Surface each async failure with the existing reusable `ErrorState` (message +
"Tentar novamente") wired to invalidate the failing provider:
- **Home:** keep the always-useful `HeroSection` and `PrimaryAction` (the "Nova
  análise" capture CTA) rendered, and replace only the stats + last-analysis
  region with a single inline error+retry card when the shared
  `soilRecordsStreamProvider` errors. Retry invalidates that stream. One card,
  not two, because both home providers derive from the one stream and always
  fail together.
- **Details / Preview:** split the `error:` branch from the `data == null`
  branch. `error:` renders a retryable error view whose retry invalidates
  `soilRecordByIdProvider(recordId)`; `data == null` keeps the existing
  no-retry "Registro não encontrado" view, because a genuinely absent or
  deleted record has nothing to retry.

## Alternatives Considered
- **Home — full-screen `ErrorState` replacing the whole dashboard:** rejected
  because it hides the primary "Nova análise" capture CTA and the greeting,
  which are the screen's core value and are independent of the records query.
- **Home — a separate error widget inside each of StatsGrid and
  LastAnalysisSection:** rejected as redundant; both derive from the single
  `soilRecordsStreamProvider`, so they always error together and would show two
  identical cards for one root cause.
- **Details / Preview — add a retry button to the shared not-found view
  (keep error and null conflated):** rejected because retrying a record that is
  genuinely absent (never existed or was deleted) does nothing useful and
  misleads the user; error and absence are different states and only error is
  recoverable.

## Scope
- Includes:
  - Home: an inline error+retry affordance shown when the records stream errors,
    with `HeroSection` and `PrimaryAction` still visible; retry invalidates
    `soilRecordsStreamProvider`.
  - Details: a retryable error view on the `error:` branch (retry invalidates
    `soilRecordByIdProvider(recordId)`); the `null` not-found view is unchanged.
  - Preview: a retryable dark-themed error view on the `error:` branch (retry +
    "Voltar"); the `null` not-found view is unchanged.
  - Widget tests for each new error/retry path and for the preserved not-found
    (no-retry) path.
- Does NOT include:
  - Changing Home's loading behavior (the current `-` placeholder skeleton in
    StatsGrid stays; this spec addresses the error gap only).
  - Any change to the History screen (already has `ErrorState` with retry).
  - Restructuring the provider graph or the record-by-id contract.
  - Management-tips error handling (already handled in its own section).
  - Any copy or visual change beyond the error/retry affordances.

## Acceptance Criteria
- home_shows_error_and_retry_when_records_stream_fails: with the records stream
  overridden to error, Home renders the error message and a "Tentar novamente"
  action.
- home_keeps_primary_action_on_error: on that same error, the "Nova análise"
  primary action is still present and the stats placeholder cards are not shown.
- home_retry_recovers_to_data: tapping "Tentar novamente" re-subscribes the
  stream and the stats values render.
- details_error_branch_shows_retry: with `soilRecordByIdProvider` overridden to
  error, Details shows a retry action (not the plain not-found view).
- details_not_found_has_no_retry: with the provider resolving to `null`, Details
  shows "Registro não encontrado" and no retry action.
- details_retry_recovers_to_record: tapping retry re-fetches and the record
  content renders.
- preview_error_branch_shows_retry: with the provider overridden to error,
  Preview shows a retry action.
- preview_not_found_has_no_retry: with the provider resolving to `null`, Preview
  shows the not-found view and no retry action.
- analyze_clean: `flutter analyze` reports no new issues.
- tests_green: `flutter test` passes.

## Reproducibility
- Toolchain: Flutter 3.44.1 / Dart 3.12.1 (pinned per `ci.yml`).
- Run: `flutter analyze && flutter test`.
- No randomness; no seed required.

## Risks and Assumptions
- Assumption: `homeStatsProvider` and `latestSoilRecordProvider` both propagate
  the error of `soilRecordsStreamProvider` (both use `.whenData`), so a single
  error check drives the Home error region. Invalidated by either provider
  swallowing the error independently — verified against the current provider
  code, which forwards it.
- Assumption: invalidating `soilRecordsStreamProvider` (Home) and
  `soilRecordByIdProvider(recordId)` (Details/Preview) re-runs their creators
  and clears the error. Invalidated if a provider caches a terminal error;
  Riverpod's `invalidate` disposes and recreates, so it does not.
- Assumption: a `null` record from `soilRecordByIdProvider` means genuine
  absence, not a swallowed error. Invalidated if the repository maps failures to
  `null`; `getById` surfaces exceptions, so absence and error stay distinct.
