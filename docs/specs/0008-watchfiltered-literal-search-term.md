# SPEC: fix(repository): trim search term and match it literally in watchFiltered

## Problem

`watchFiltered` neither trims nor escapes the search term, so a whitespace-only term silently filters everything out while a wildcard-only term silently returns every record — two opposite wrong answers to the same "the term carries no content" situation.

## Design Decision

Treat the search term as a **literal substring**, not as a pattern. Trim the term first; if the trimmed term is empty, apply no address filter (matching the documented `watchAll` behavior for `null`). Otherwise pass the term to SQL LIKE with an explicit `ESCAPE` clause — `drift 2.31.0` exposes `like(String regex, {String? escapeChar})` (`drift/lib/src/runtime/query_builder/expressions/text.dart:10`) — escaping `%`, `_` and the escape character itself so they match literally.

This replaces the current strip-the-wildcards sanitizer, which is the shared root cause of both reported bugs and additionally corrupts legitimate input: today `"a_b"` is rewritten to `"ab"`, so a record literally addressed `a_b` cannot be found while an unrelated `ab` matches instead.

## Alternatives Considered

- **Keep the strip, and treat a post-sanitization-empty term as "no matches" instead of "no filter".** Rejected: it fixes the `"%"` asymmetry but keeps the input corruption — `"a_b"` would still silently become `"ab"`, and searching for a literal underscore would still be impossible. It treats the symptom.
- **Keep the strip and only add `trim()`.** Rejected: the minimal change closes the whitespace half of #130 but leaves the `"%"` returns-everything behavior, which the issue explicitly asks to decide rather than preserve, and leaves the corruption untouched.
- **Reject terms containing `%` or `_` with a validation error surfaced in the UI.** Rejected: `%` and `_` are ordinary characters in Brazilian street addresses and lot identifiers; refusing them turns a search box into a form field and pushes SQL syntax onto the agronomist.
- **Match with `instr(lower(address), lower(term)) > 0` via a `CustomExpression`.** Rejected: it achieves the same literal semantics but hand-writes SQL, bypassing drift's typed builder for no gain over the supported `escapeChar` parameter.

## Scope

- Includes: `watchFiltered` in `lib/core/data/repositories/drift_soil_record_repository.dart` (lines 161-199); the doc comment on the interface in `lib/core/data/repositories/soil_record_repository.dart:38-46`, which today documents only the `null` case; updating the tests in `test/repositories/drift_soil_record_repository_test.dart` that currently pin the old behavior (`:410-430`).
- Does NOT include: the `filteredRecordsProvider` fast path in `lib/providers/soil_record_repository_provider.dart:113-127` beyond confirming a whitespace-only term reaches the same result as no filter; the texture-class filter, which is an exact match and is unaffected; search ranking, diacritic folding or fuzzy matching; any UI change in `history_screen.dart`.

## Acceptance Criteria

- `whitespace_only_term_returns_the_same_set_as_watch_all` — a term of `"   "` applies no address filter.
- `term_is_trimmed_before_matching` — `"  loam  "` finds the record addressed `Loam Street`.
- `wildcard_only_term_returns_no_matches_when_no_address_contains_it` — `"%"` matches only addresses containing a literal `%`, not every row.
- `percent_in_the_term_matches_a_literal_percent` — a record addressed `Lot 50% Shade` is found by the term `50%`.
- `underscore_in_the_term_matches_a_literal_underscore` — a record addressed `a_b` is found by the term `a_b`, and a record addressed `ab` is not.
- `escape_character_in_the_term_matches_literally` — a term containing the chosen escape character does not corrupt the pattern.
- `case_insensitive_match_is_preserved` — the existing lowercase-both-sides behavior still holds.
- `existing_texture_class_and_combined_filter_tests_still_pass` — no regression in the AND semantics at `:374`.

## Reproducibility

`flutter test test/repositories/drift_soil_record_repository_test.dart`. Deterministic, no randomness. drift 2.31.0, `AppDatabase.forTesting(NativeDatabase.memory())`, Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: no caller depends on the current `"%"` returns-everything behavior. Verified — the only production caller is `filteredRecordsProvider`, which passes user text straight through.
- Assumption: SQLite's `ESCAPE` clause applies to `LIKE` on the `lower()`-wrapped column the same as on a bare column. If a test disproves this, fall back to the rejected `instr` alternative.
- This spec is invalidated if search moves to FTS5, which would make LIKE-escaping moot.
