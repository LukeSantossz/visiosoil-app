# SPEC: feat(database): record which corpus answered and treat an older one as stale

## Problem

`management_tips` stores the composed result without recording which corpus
release produced it, so nothing can tell a row written by an older corpus from a
current one — and the rows written today, while the app holds no corpus at all,
are indistinguishable from real guidance and will keep being served after a
corpus ships.

## Design Decision

**Add one nullable `corpus_version` column, schema v4 → v5, and make the
repository report staleness rather than decide it.** The column is written from
`ManagementTipsResult.corpusVersion` on every upsert and read back as a typed
value; a new `isStaleAgainst(String? currentVersion)` answer on the repository's
read says whether the cached row was produced by a corpus other than the one the
app now holds.

**Staleness is exact string inequality, not ordering.** A corpus version is a
release label, not a number to compare: `2026.09.1` and `2026.10.1` differ, and
so do a label and the absence of one. Any difference means a different corpus
answered, which is precisely the question the cache needs answered. Ordering
would require the app to understand a versioning scheme that the corpus build
owns, and would silently do nothing the first time that scheme changed.

**A null cached version is stale against any corpus.** That is what closes the
wart SPEC 0068 left on purpose: a row written while the app held no corpus has
`corpusVersion` null, so the moment a corpus arrives the row is stale and the
surface can refresh it rather than keep showing "no coverage" for a region that
is now covered.

Nullable rather than defaulted, because a row cached before v5 genuinely has no
known version and a fabricated default would claim currency the row does not
have.

## Alternatives Considered

- **Compare versions by ordering, so only an older corpus is stale.** Rejected:
  it requires the app to parse a scheme the corpus build owns, and a rebuild that
  changed the scheme would make every comparison quietly return "not stale" — a
  failure that shows as guidance nobody refreshes.
- **Derive the version from `payload_json` instead of adding a column.** Rejected:
  it means decoding every row to answer a question about rows, which is what the
  duplicated `retrieved_at` column already exists to avoid, by the table's own
  documented reasoning.
- **Default the column to the empty string instead of null.** Rejected: an empty
  string is a value, so a pre-v5 row would claim to have been produced by a
  corpus named "". Null is the honest reading of "not recorded".
- **Evict stale rows during the migration.** Rejected: the migration would delete
  a user's offline guidance on upgrade, with nothing to replace it until they are
  online. Marking is reversible; deleting is not.
- **Have the repository refresh a stale row itself.** Rejected: the repository is
  a cache, not an orchestrator. Deciding to regenerate belongs to the controller
  and the surface, and folding it in here would make a read perform a write.
- **Decide staleness in the surface by comparing strings there.** Rejected: it
  puts the same comparison in every caller, and the surface is the UI/UX
  terminal's, which this workstream does not edit.

## Scope

- Includes:
  - `lib/core/database/tables/management_tips_table.dart` — one nullable
    `corpus_version` column.
  - `lib/core/database/app_database.dart` — `schemaVersion` 4 → 5 and a
    cumulative `if (from < 5)` step in the existing style.
  - `lib/core/database/app_database.g.dart` — regenerated.
  - `lib/core/data/repositories/management_tips_repository.dart` and its Drift
    implementation — write the column on upsert, and a read that reports the
    cached version alongside the result.
  - Tests: the migration, the round trip, and the staleness rule.
- Does NOT include:
  - `assets/corpus/`, corpus loading, fetch or version comparison against a
    served release. That is A4.
  - Acting on staleness — refreshing, evicting, or rendering a badge. The
    repository reports; deciding is A4's and the UI/UX terminal's.
  - Any change to `soil_records` or `sync_queue`.
  - `lib/core/features/details/management_tips_section.dart`.
  - Any change to `ml/`, the model, the preprocessing path, or the class list.

## Acceptance Criteria

Each becomes a test, written before its implementation.

- `schema_version_is_five`: `AppDatabase.schemaVersion` is 5.
- `v4_database_migrates_with_its_rows_intact`: a database at v4 holding tips rows
  opens at v5 with every row present and every prior column unchanged.
- `a_pre_v5_row_has_a_null_corpus_version`: the migrated rows carry null, not an
  empty string.
- `upsert_writes_the_corpus_version_from_the_result`: a result carrying
  `2026.09.1` writes that value to the column.
- `upsert_writes_null_when_the_result_has_no_version`: the absent-corpus result
  SPEC 0068 produces writes null rather than a placeholder.
- `read_reports_the_cached_version`: reading a row returns both the result and the
  version the column holds.
- `a_row_is_stale_when_the_versions_differ`: cached `2026.09.1` against current
  `2026.10.1` is stale.
- `a_row_is_fresh_when_the_versions_match`: cached `2026.09.1` against current
  `2026.09.1` is not stale.
- `a_null_cached_version_is_stale_against_any_corpus`: this is what makes an
  absent-corpus row refresh itself once a corpus ships.
- `a_null_cached_version_is_not_stale_when_no_corpus_is_held`: with nothing to
  compare against, nothing is out of date — otherwise the app would report every
  row stale forever while it holds no corpus.
- `staleness_does_not_order_versions`: a cached version that sorts *after* the
  current one is still stale, because the rule is difference rather than age.
- `payload_and_column_agree_after_a_round_trip`: the version in `payload_json`
  and the value in the column are the same string.

## Reproducibility

```bash
git submodule update --init
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter analyze
mf check
```

Toolchain as pinned in `.github/workflows/ci.yml`. Migration tests use
`AppDatabase.forTesting(NativeDatabase.memory())`, so no device and no file on
disk is involved.

## Risks and Assumptions

- **Assumption:** the generated Drift code regenerates cleanly with one added
  nullable column. It is the same shape as the v1→v2 and v2→v3 steps already in
  `AppDatabase`, so the risk is in forgetting to regenerate rather than in the
  change itself; CI's `test` job fails loudly if the generated file is stale.
- **Assumption:** a corpus version is a stable label for the life of a release.
  If the build emitted a different label for the same content, every row would
  read stale and be refreshed once — wasteful but not wrong.
- **Risk:** staleness is reported and nobody acts on it, so the column becomes
  another field with no reader. Bounded rather than open: A4 is the consumer and
  it is the next slice, and this spec's own criteria are what A4 builds against.
- **Risk:** the migration runs on a device holding rows written by SPEC 0068's
  absent-corpus path, which are empty answers. They migrate to null and are
  therefore stale the moment a corpus arrives, which is the intended outcome and
  not a special case.
- **What would invalidate this spec:** a decision that the cache should key by
  corpus version rather than record uuid — that is, keep one row per record *per
  corpus*. It would change the primary key and make staleness a lookup rather
  than a comparison. Nothing calls for it today, since only the current corpus's
  answer is ever shown.
