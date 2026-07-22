# SPEC: refactor(repository): remove unused getLatest/count/getDistinctTextureClasses

## Problem
Three `SoilRecordRepository` read methods — `getLatest`, `count`,
`getDistinctTextureClasses` — have no production callers (superseded by
stream-derived providers), so they are dead surface that must still be maintained
and tested and has already been mistaken for the canonical read path.

## Design Decision
Remove the three methods from the `SoilRecordRepository` interface and its
`DriftSoilRecordRepository` implementation, and delete their now-orphaned unit
tests. The abstract interface stays the seam for a future remote/sync backend
(#55-57); that backend can re-add exactly the reads it needs when it exists,
rather than carrying speculative surface now (YAGNI, and the project convention
against unrequested/dead abstraction).

## Alternatives Considered
1. Document the three methods as deliberate forward-looking surface for the sync
   backend (the issue's option b). Rejected: keeping unused, separately-tested
   code alive to serve a backend that does not exist yet is the speculative
   generality the conventions warn against; the methods have already drifted from
   the canonical stream path, and a doc comment does not stop that. When #55-57
   land they will define their own exact read needs.
2. Keep `getAll`/`watchAll` only and inline the three behaviours at any future
   call site. Not applicable today (no call sites); noted so the removal is not
   read as losing capability — `getAll`/`watchAll` already expose the full list
   the providers derive from.

## Scope
- Includes:
  - Remove `getLatest`, `count`, `getDistinctTextureClasses` from
    `lib/core/data/repositories/soil_record_repository.dart` and
    `lib/core/data/repositories/drift_soil_record_repository.dart`.
  - Remove their orphaned dedicated tests in
    `test/repositories/drift_soil_record_repository_test.dart` (the `getLatest`,
    `count`, and `getDistinctTextureClasses` test cases).
  - Remove the three overrides from the `FakeSoilRecordRepository` test double
    (`test/support/fake_soil_record_repository.dart`), which implements the
    interface and would otherwise fail to compile.
  - Rewrite the few remaining assertions that used `count()`/`getLatest()` only
    as verification tools (not as the subject under test) to use the retained
    `getAll()`: four `count()` assertions inside unrelated create/delete tests in
    `drift_soil_record_repository_test.dart`, and the `count()`/`getLatest()`
    lines in `sync_metadata_repository_test.dart`'s
    `tombstoned_records_are_excluded_from_reads` (already redundant with its
    `getAll()` assertion). Behaviour asserted is byte-for-byte preserved.
- Does NOT include:
  - Any change to the retained methods (`create`, `getById`, `watchAll`,
    `getAll`, `deleteById`, `deleteByIds`, `deleteAll`, `watchFiltered`).
  - Any change to the stream-derived providers that superseded them.
  - Touching the sync layer or adding new repository methods.

## Acceptance Criteria
- The three methods are absent from both the interface and the Drift impl, and
  from the `FakeSoilRecordRepository` double (verifiable: a grep for
  `getLatest`/`getDistinctTextureClasses`/`count(` across `lib/` and `test/` finds
  nothing — the internal Drift aggregate `_db.soilRecords.id.count()` existed only
  inside the removed `count()`, so it is gone too).
- Their dedicated unit tests are removed and the tool-only assertions are
  rewritten to `getAll()`; no test references the deleted symbols.
- `flutter analyze` is clean and `flutter test` is green (no dangling references).

## Reproducibility
Toolchain Flutter 3.44.1 / Dart 3.12.1. `flutter analyze && flutter test`.

## Risks and Assumptions
- Assumption (verified): the three methods have no production callers on current
  `main` — grep of `lib/` shows only their definitions plus the internal Drift
  `id.count()` aggregate, no consumers in `lib/providers` or `lib/core/features`.
  Invalidated if a caller is added on another open branch before merge; re-grep
  at implementation time.
- Note: a pure removal has no natural red-first test (you delete code and its
  tests). Verification is `analyze`/`test` green plus the absence grep, per the
  code-inspection precedent for changes not unit-testable by construction. If the
  Developer prefers option 1 (document), that is likewise a non-TDD doc change.
