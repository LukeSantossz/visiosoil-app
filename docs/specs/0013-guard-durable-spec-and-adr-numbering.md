# SPEC: test(standards): guard durable spec and ADR numbering against gaps, duplicates, and deletions

## Problem

The durable-numbering rule became binding here when #136 bumped `.standards`, but nothing in this
repository enforces it, so a duplicated number, an abandoned gap, or a deleted record reaches `main`
unnoticed.

## Design Decision

Add `test/standards/durable_numbering_test.dart`, so CI enforces the rule through the `flutter test`
job it already runs and developers see a violation on every local test run rather than only on push.
Track each number's **history of events**, not a final set of numbers. Comparing sets cannot tell a
rename from a deletion followed by reassignment — in both, the number is present before and after —
and reassignment is the incident the rule exists for. So replay `git log --name-status
--find-renames` and decide reuse by **record identity**: a rename links two slugs into one record,
and a number held by more than one record identity was reassigned. Identity is order-independent,
which matters because a replacement staged as add-then-delete never leaves the number empty, and
that is the order git emits whenever the new slug sorts first. Re-adding a slug the number already
carried is a restoration, not reuse. A rename is continuity only when the record stays in the
governed directory and keeps its number; moving it out removes it as surely as deleting it.
Duplicates, deletions, and reuse fail everywhere; contiguity fails only on `main`,
because on a feature branch a missing number is normally one legitimately reserved by a concurrent
pull request. Detect that by the checked-out branch name rather than a CI variable, which also makes
the local run behave the same way.

## Alternatives Considered

- **A shell script under `scripts/test/`** — rejected: CI runs nothing from that directory today, so
  it would need a new job, and it would not run during `flutter test` locally. The existing
  `codex-review.test.sh` demonstrates the failure mode: 14 tests that only run when someone
  remembers to invoke them by hand.
- **Fail on a gap everywhere, matching the standard's wording literally** — rejected: it would have
  failed PR #139, which contained no defect. Spec `0012` was correct precisely because `0011` was
  taken by the open #138. Under this rule two specs can never be in flight at once.
- **Drop contiguity and guard only duplicates and deletions** — rejected, though it is the closest
  call. The rule's stated purpose is that a reference never resolves ambiguously, and a number
  abandoned before any record used it makes nothing ambiguous. But that reasoning also silently
  narrows a norm this repository declares it follows, and it would hide a gap left by a branch
  abandoned mid-flight. Enforcing on `main` keeps the norm whole at the only place it is unambiguous.
- **Compare the set of numbers ever committed against the set present today** — rejected after it was
  implemented and reviewed. It is immune to renames, which is why it was chosen, but immunity to
  renames turned out to be indistinguishable from blindness to reuse: delete `0009-old.md`, add an
  unrelated `0009-new.md`, and `0009` sits in both sets, so the difference is empty and the guard
  passes. That is the exact shape of the incident recorded in the framework's ADR 0004 under
  "Numbering history". A set difference cannot express an ordering rule; replaying events can.
- **Compare deletions by file path via `git log --diff-filter=D` alone** — rejected: without rename
  detection, correcting a slug surfaces as a deletion and fails falsely.
- **Gate on the GitHub event type or `GITHUB_REF`** — rejected: it makes the test behave differently
  in CI than locally, so a developer cannot reproduce a CI failure. `git rev-parse --abbrev-ref HEAD`
  answers the same question in both places, and returns `HEAD` on the detached merge commit a
  `pull_request` run checks out, which is exactly the case contiguity should skip.

## Scope

- Includes:
  - `test/standards/durable_numbering_test.dart` with the three checks.
  - A retirement allowlist keyed by number, requiring a stated reason; empty on arrival.
  - `fetch-depth: 0` on the `test` job's checkout in `.github/workflows/ci.yml`, without which the
    history check cannot see past the shallow clone.
- Does NOT include:
  - Wiring `scripts/test/codex-review.test.sh` into CI. It is a real gap, filed separately rather
    than folded in here.
  - Enforcing spec content, tier, or template conformance — only numbering.
  - Any change to `docs/specs/` or `docs/adr/` contents.
  - Enforcing contiguity on feature branches, per the decision above.

## Acceptance Criteria

- `spec_numbers_have_no_duplicates`
- `adr_numbers_have_no_duplicates`
- `spec_numbers_are_contiguous_from_0001_on_main`
- `adr_numbers_are_contiguous_from_0001_on_main`
- `contiguity_is_skipped_with_a_stated_reason_when_not_on_main`
- `no_number_ever_committed_is_absent_unless_allowlisted`
- `a_renamed_record_keeping_its_number_does_not_read_as_a_deletion`
- `a_number_deleted_and_later_reassigned_is_reported_as_reuse`
- `a_deleted_record_restored_under_its_own_slug_is_not_reuse`
- `no_number_was_deleted_and_reassigned_unless_allowlisted`
- `git_status_lines_are_parsed_into_ordered_events`
- `an_allowlisted_retirement_requires_a_non_empty_reason`
- `the_allowlists_state_their_reasons`
- `the_guard_passes_against_the_current_tree`

## Reproducibility

- `flutter test test/standards/durable_numbering_test.dart`, and the full `flutter test`.
- Red first: each check is demonstrated failing before it passes, using a seeded violation rather
  than a claim. Per criterion:
  - duplicate: add a second file numbered `0012`, observe the duplicate check fail, remove it.
  - gap: temporarily move `0012` aside while on `main`, observe the contiguity check fail, restore.
  - deletion: temporarily remove a committed record, observe the history check fail, restore.
  - rename: rename a record keeping its number, observe the history check still pass.
- The history check requires full history. Locally that is the normal clone; in CI it requires
  `fetch-depth: 0`, and its absence is itself observable — the check fails or sees nothing on a
  shallow clone.
- No randomness; no seed. Versions: Flutter 3.44.1 / Dart 3.12.1.
- Current tree for reference: `docs/specs/0001`–`0013`, `docs/adr/0001`–`0007`.

## Risks and Assumptions

- Assumption: `git` is on `PATH` wherever the suite runs. It is required to obtain the repository at
  all, and CI checks out with `actions/checkout`. If a sandbox ever runs tests without git, the
  history check must fail loudly rather than silently pass; the test asserts the git invocation
  succeeded before interpreting its output.
- Assumption: `git rev-parse --abbrev-ref HEAD` returns `main` on a push-to-main CI run and `HEAD`
  on a `pull_request` run's detached merge commit. This is what gates contiguity, so it is pinned by
  its own criterion rather than trusted.
- Risk: a shallow clone would make the history checks see nothing and pass vacuously — the worst
  failure mode, since it looks green. Asserting the query returned a non-empty result is *not*
  sufficient, and was the first attempt: a depth-1 clone's grafted root commit lists every tracked
  file as an addition, so the result is non-empty and the "ever committed" view equals the present
  one, making the guard fully vacuous rather than merely weak. Mitigated by asking git directly with
  `git rev-parse --is-shallow-repository` and failing when it reports `true`.
- Risk: git's rename detection is similarity-based, so renaming a record while substantially
  rewriting it is recorded as `D` plus `A` rather than `R`, and the guard reports reuse where none
  occurred. Accepted deliberately: the failure biases toward a false positive costing one allowlist
  entry with a stated reason, rather than a false negative that admits exactly what the rule exists
  to prevent. `renamedWithRewriteSpecNumbers` / `renamedWithRewriteAdrNumbers` carry those cases.
- Risk: this spec takes number `0013` while `0012` is already on `main`, so the sequence stays
  contiguous; no concurrent spec is in flight at authoring time.
- What would invalidate this spec: adopting the framework's own self-test suite, which would supply
  an equivalent guard and make this one redundant.
