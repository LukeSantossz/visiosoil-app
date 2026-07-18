# SPEC: test(standards): guard durable spec and ADR numbering against gaps, duplicates, and deletions

## Problem

The durable-numbering rule became binding here when #136 bumped `.standards`, but nothing in this
repository enforces it, so a duplicated number, an abandoned gap, or a deleted record reaches `main`
unnoticed.

## Design Decision

Add `test/standards/durable_numbering_test.dart`, so CI enforces the rule through the `flutter test`
job it already runs and developers see a violation on every local test run rather than only on push.
Track **numbers, not file paths**: the rule protects the number a reference resolves to, so renaming
`0009-old-slug.md` to `0009-new-slug.md` must not read as a deletion, while removing the only file
bearing `0009` must. Duplicates and deletions fail everywhere; contiguity fails only on `main`,
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
- **Compare deletions by file path via `git log --diff-filter=D`** — rejected: rename detection is
  not reliably on, so correcting a slug would surface as a deletion and a false failure. Comparing
  the set of numbers ever committed against the numbers present today is immune to renames and
  matches what the rule actually protects.
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
- `an_allowlisted_retirement_requires_a_non_empty_reason`
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
- Risk: a shallow clone would make the history check see no deletions and pass vacuously — the worst
  failure mode, since it looks green. Mitigated by asserting the history query returned a non-empty
  commit set, so an unexpectedly shallow clone fails instead of passing.
- Risk: this spec takes number `0013` while `0012` is already on `main`, so the sequence stays
  contiguous; no concurrent spec is in flight at authoring time.
- What would invalidate this spec: adopting the framework's own self-test suite, which would supply
  an equivalent guard and make this one redundant.
