# SPEC: fix(tips): recompose cached tips when the corpus changes

## Problem

Cached management tips are never compared with the corpus the app holds, so a record keeps the tips or the abstention an earlier corpus release gave until someone taps "Atualizar dicas".

## Design Decision

**The section checks cached tips against the held corpus once, and recomposes them when another release answered.** The check is the one schema v5 prepared for: `CachedManagementTips.isStaleAgainst`, which compares the row's `corpus_version` with the held corpus's version by exact inequality.

The parts:

- `ManagementTipsController` gains `isStale(record)`. It reads the cached row with `getCached` and the held corpus from a `CorpusStore`, and answers `isStaleAgainst(corpus?.corpusVersion)`. A record with no uuid or no cached row is not stale, because there is nothing to refresh, and the empty cache already generates on its own. The controller takes the store from `corpusStoreProvider`, the same store `researchServiceProvider` composes from, so the version it compares is the version a recompose would write.
- `ManagementTipsSection`, on showing a cached result, asks `isStale` once for the record. If the answer is yes, it runs the same `_generate` that "Atualizar dicas" runs.
- While the recompose runs, the cached tips stay on screen and "Atualizar dicas" shows its loading state, as it does for a tap. When it succeeds, the cache is re-read and the new tips replace the old.
- **A failed automatic recompose is silent.** The cached tips stay, and no snackbar shows, because the user did not ask for anything. "Atualizar dicas" keeps its snackbar on failure.
- **Once per record.** A flag set before the check stops a rebuild from asking again, and it resets when the section is given another record, as the empty-cache flag does. A recompose that fails is therefore not retried until the record is opened again.
- **A store that throws counts as not stale.** `AssetCorpusStore` throws on a malformed asset. The check then leaves the cached tips in place, and the error reaches the user the way it does today, through a tap on "Atualizar dicas".

How the rule meets each case, by `isStaleAgainst`'s own definition:

- A row cached by another release is stale. This is the case the audit saw: an abstention cached on 29/10 that the current corpus `2026.10.31.3` answers with tips.
- A row cached before schema v5 has a null version, and it is stale against any held corpus.
- With no corpus held, a null version is not stale, so nothing recomposes in a loop. The controller never caches the `corpus:none` placeholder anyway.

The UX audit of 2026-11-10 (finding UX-03) found the defect on the emulator. The Developer approved the fix on 2026-11-10.

## Alternatives Considered

- **Check in `ManagementTipsController.generate` and in no other place.** Rejected. `generate` runs only when the cache is empty or the user taps. The stale row is the case where neither happens.
- **Have the repository recompose on read.** Rejected. `CachedManagementTips` records that the repository reports staleness and does not act on it: a read that performs a write is the shape the v5 split exists to avoid.
- **Recompose every cached row when the app starts.** Rejected. It composes for records nobody opens, and it would need a place to run outside the provider graph. The section is where a record's tips are shown, so the check runs where it pays off.
- **Show a banner "Novas dicas disponíveis" and let the user tap.** Rejected. Composing is on the device and takes no network, so asking first adds a tap and keeps the stale answer on screen.

## Scope

- Includes:
  - `ManagementTipsController.isStale` and the `CorpusStore` it reads;
  - `managementTipsControllerProvider` passing `corpusStoreProvider`;
  - the section's once-per-record check and silent recompose;
  - tests for the controller and the section.
- Does NOT include:
  - recomposing records that are not on screen;
  - the corpus refresh endpoint, which does not exist (CLAUDE.md, Current Limitations);
  - the layout of the sources list (its own spec);
  - a recompose after the agronomist records a true class, which does not change the classification the tips use;
  - schema, sync or routes.

## Acceptance Criteria

- `stale_when_another_release_answered`: with a row cached at version `v1` and a held corpus at `v2`, `isStale` is true.
- `fresh_when_the_same_release_answered`: with a row and a held corpus both at `v2`, `isStale` is false.
- `not_stale_without_a_cached_row`: with an empty cache, `isStale` is false.
- `not_stale_without_a_held_corpus`: with a row whose version is null and no held corpus, `isStale` is false.
- `stale_tips_recompose_on_their_own`: the section shows a record whose cached tips are at `v1` while the held corpus is at `v2`. Without a tap, the service is called once and the new tips replace the old ones on screen.
- `stale_tips_stay_on_screen_while_recomposing`: while that recompose has not answered, the old tips stay on screen and "Carregando dicas" does not show.
- `fresh_tips_do_not_recompose`: cached tips at the held version are shown, and the service is not called.
- `a_failed_automatic_recompose_stays_silent`: with stale cached tips and a failing service, the cached tips stay on screen and no `SnackBar` shows.
- `the_stale_check_runs_once`: after a failed automatic recompose, three rebuilds of the section leave the service call count at one.
- The existing test "a failed refresh keeps the cached tips and shows a snackbar" passes unchanged.
- `flutter analyze` reports nothing new, `flutter test` has no failures beyond those this machine has on `main`, and `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI. Run `flutter test test/providers/management_tips_controller_test.dart test/features/details/management_tips_section_test.dart`, then `flutter analyze`, `flutter test` and `mf check`.

## Risks and Assumptions

- **Opening a stale record composes once.** Accepted. Composition reads the in-memory corpus and resolves the site from a bundled grid, which the empty-cache path already does on first open.
- **A corpus release can turn tips into an abstention.** Accepted. That is the current corpus's answer for that record, and showing the old tips would present guidance the release no longer stands behind.
- **Assumption:** every successful composition carries the version of the corpus that composed it. `CorpusComposer` sets `corpusVersion` from the corpus it read, and the controller caches nothing else.
