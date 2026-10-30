# SPEC: fix(tips): load the tips on open

## Problem

Classified records require a tap on "Gerar dicas" before showing management tips, and an empty no-corpus answer can remain cached after a version with a corpus is installed.

## Design Decision

When a classified record has a UUID and its cache read resolves without an entry, the section schedules generation after the frame and shows the existing loading state. A guard set before scheduling permits at most one automatic attempt per section state, including after failure or an uncached answer; manual generation, refresh and retry remain available as before.

The controller recognizes a successful answer whose model is `corpus:none`, returns a distinct `ResearchFailureKind.corpusUnavailable`, and skips the upsert. The section maps that outcome to "As dicas de manejo ainda não estão disponíveis nesta versão do app." The service retains its existing result contract, with documentation explaining that this placeholder is not cacheable.

## Alternatives Considered

- **Keep generation manual.** Rejected because the owner's product decision of 2026-10-22 requires tips to appear automatically after classification.
- **Change the service to return a failure when no corpus exists.** Rejected because the controller can protect the persistence boundary with a smaller change while retaining the service's existing composition contract.
- **Generate on every empty cache read.** Rejected because a failed or uncached answer would trigger repeated attempts without user action.

## Scope

- Includes:
  - automatic generation and its once-per-state guard in `management_tips_section.dart`;
  - the no-corpus controller outcome, its pt-BR message, and truthful service documentation;
  - widget and controller regression tests using `test/support/management_tips_fakes.dart`.
- Does NOT include:
  - corpus composition, corpus assets, cache schema changes or migration of existing cache entries;
  - changes to classification, refresh behavior, retry behavior or unrelated UI;
  - dependencies, unrelated refactoring, pushing or changing other branches.

## Acceptance Criteria

- `auto_generation_restarts_for_a_new_record` in `test/features/details/management_tips_section_test.dart`: rebuilding the same section state with a different UUID and an empty cache triggers a second generation call.
- `tips_appear_without_tapping_generate` in `test/features/details/management_tips_section_test.dart`: a classified record with no cache displays loading and then generated tips without a tap.
- `auto_generation_fires_once_after_failure` in the same file: repeated rebuilds after failure do not generate again; the existing retry still works.
- `auto_generation_fires_once_without_cached_result` in the same file: an attempt leaving the cache empty does not loop.
- `no_corpus_message_shows` in the same file: a `corpus:none` answer displays the version-specific message without caching tips or automatically retrying.
- `no_corpus_result_is_not_upserted` in `test/providers/management_tips_controller_test.dart`: a `corpus:none` success returns `corpusUnavailable` and leaves the repository untouched.
- Existing cached tips, refresh and corpus service tests continue to pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1, with Flutter at `/home/box/flutter/bin`. No randomness is involved. Run:

```sh
flutter test test/features/details/management_tips_section_test.dart test/providers/management_tips_controller_test.dart test/services/corpus_research_service_test.dart
flutter test
flutter analyze
/workspace/mf/mf check
```

## Risks and Assumptions

- **A mounted section can receive a different record.** A UUID change resets the automatic-attempt guard and the previous error so the new record can generate tips.
- **The no-corpus sentinel remains `corpus:none`.** A changed service sentinel would require updating the controller check.
- **One automatic attempt belongs to one section state.** Opening a new section state may attempt generation again; failures in the current state require manual retry.
- **Previously cached placeholders are outside scope.** This change prevents new no-corpus entries but does not migrate existing entries.
- **No ADR is needed.** The local scheduling and persistence guard are easy to reverse and introduce no architectural boundary.
