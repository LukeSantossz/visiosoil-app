# SPEC: chore(standards): bump the framework submodule to the current my-framework main

## Problem

The `.standards` submodule is pinned at `31322f9` (tag `v0.1.0`) and is 67 commits behind
`my-framework`'s `origin/main`, so this repository declares it follows norms that have since
changed: durable spec/ADR numbers are never reused, the token economy became opt-in, the R2
reviewer default moved off `gpt-5.5`, and `crux_method.md` did not exist at the pin.

## Design Decision

Update the submodule for real rather than only redirecting its gitlink: fetch inside `.standards`,
check out `6ad21c4`, confirm the working tree on disk now holds the new standards, and commit the
resulting gitlink. The distinction matters because the working tree is what every session actually
reads — a gitlink moved without the checkout leaves `.standards/` serving the retired rulebook while
the repository claims the new one. Declare the tracked branch in `.gitmodules` (`branch = main`) so
later bumps are `git submodule update --remote --merge` instead of a hand-resolved commit id; the
gitlink stays committed, so clones and CI remain deterministic and `--remote` is only ever taken
deliberately. Accept that the pin no longer tracks a released tag: `v0.1.0` is still the newest tag,
so tracking tags would mean staying on a pin whose norms the framework has already replaced. Refresh
the framework files this repository
carries as copies (`scripts/codex-review.sh`, `scripts/setup.sh`, `scripts/test/docs-consistency.sh`,
`scripts/test/codex-review.test.sh`) to match, treating `codex-review.test.sh` as a **merge rather
than an overwrite** because it carries local hardening the framework never had. Record in
`CLAUDE.md` the two states the new norms make explicit choices rather than defaults — the
token-economy opt-in and the R2 reviewer model — and correct the `CLAUDE.md` claims that a
verification pass against the code found stale.

## Alternatives Considered

- **Stay on the `v0.1.0` tag until a newer tag exists** — rejected: this is what spec `0001`
  decided, and the condition it assumed no longer holds. The framework has published no tag since
  `v0.1.0` while replacing binding norms across 67 commits, so honoring the tag rule now means
  authoring every future spec and running every R2 review against a rulebook the framework has
  retired. The rule was a proxy for "track a stable rulebook"; the tag stopped being that proxy.
- **Redirect the gitlink only, without updating the checkout or declaring a tracked branch** —
  rejected: it records the intent without performing it. Every session reads `.standards/` from
  disk, so a repository whose gitlink names `6ad21c4` while its checkout still serves `31322f9`
  claims conformance to norms it is not actually running against, and the gap is invisible until
  someone diffs the two. Leaving `.gitmodules` without a tracked branch also keeps every future
  bump a hand-resolved commit id, which is how the pin fell 67 commits behind in the first place.
- **Cherry-pick only the changed `docs/standards/` files into the pin** — rejected: it forks the
  submodule from upstream and reintroduces exactly the drift the submodule exists to prevent. It
  also cannot work mechanically, since a submodule pin names a commit, not a file subset.
- **Overwrite `scripts/test/codex-review.test.sh` with the framework version** — rejected: the
  repository's copy adds a fail-closed guard on `mktemp` (commit `0e4059b`), so an empty `STUB_DIR`
  cannot silently put the real `codex` binary back on `PATH` during tests. `git log -S` over the
  framework's full history confirms that guard never existed upstream. Overwriting regresses a fix
  this repository made deliberately.
- **Bump the submodule and defer the `CLAUDE.md` reconciliation to a follow-up issue** — rejected:
  the bump is what makes the new norms binding, so shipping it while `CLAUDE.md` still names
  `gpt-5.5` and states no token-economy choice leaves the repository knowingly non-conformant for
  the length of the follow-up.

## Scope

- Includes:
  - Update the `.standards` working tree from `31322f9` to `6ad21c4` by fetching and checking out
    inside the submodule, and commit the resulting gitlink as a commit of its own.
  - Declare `branch = main` for `.standards` in `.gitmodules`.
  - Refresh `scripts/codex-review.sh` and `scripts/setup.sh` so the R2 reviewer default reads
    `gpt-5.6-terra`.
  - Refresh `scripts/test/docs-consistency.sh` (comment-only upstream change) for parity.
  - Merge the framework's `GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM` isolation and the
    `gpt-5.6-terra` expectation into `scripts/test/codex-review.test.sh` while keeping this
    repository's `mktemp` fail-closed guard.
  - Update `CLAUDE.md`: R2 reviewer model, an explicit token-economy opt-in state, a stated CRUX
    applicability, and the stale factual claims listed under Acceptance Criteria.
  - Confirm the durable-numbering rule holds for `docs/specs/` and `docs/adr/`.
- Does NOT include:
  - Adopting the framework's own self-test suite (`scripts/test/docs-consistency.test.sh`) or
    wiring any framework check into this repository's CI. It pins the framework's files, not an
    adopting project's.
  - Authoring the `explain-change` skill or producing a CRUX explainer for this change.
  - Running `setup.sh --interactive` or persisting a reviewer model in local git config.
  - Any application code, database schema, dependency, or test change under `lib/` or `test/`.
  - Fixing the substance of the issues the verification pass touches (#116 label copies, #79
    `spec.json`); only the `CLAUDE.md` description of them is corrected here.

## Acceptance Criteria

- `standards_gitlink_points_at_6ad21c4_in_a_commit_of_its_own`
- `standards_working_tree_on_disk_holds_the_new_standards_including_crux_method_md`
- `gitmodules_declares_branch_main_for_the_standards_submodule`
- `codex_review_sh_and_setup_sh_default_the_reviewer_model_to_gpt_5_6_terra`
- `codex_review_test_sh_keeps_the_mktemp_fail_closed_guard_and_gains_the_git_config_isolation`
- `codex_review_test_sh_passes`
- `claudemd_names_gpt_5_6_terra_as_the_r2_reviewer`
- `claudemd_states_the_token_economy_opt_in_as_declined_with_its_reason`
- `claudemd_states_crux_applicability_and_that_it_never_blocks_a_ship`
- `claudemd_states_six_label_copies_including_the_two_python_test_fixtures`
- `claudemd_states_that_spec_json_is_git_ignored_alongside_the_tflite_artifact`
- `docs_specs_and_docs_adr_numbers_are_contiguous_from_0001_with_no_duplicate_and_nothing_deleted`
- `flutter_analyze_reports_no_issues`
- `flutter_test_passes_all_210_tests`

## Reproducibility

Configuration and documentation change; no unit test is added. The test-first step maps to
demonstrating each gap on the current pin, then showing it closed after the bump.

- Before:
  - `git -C .standards rev-list --count HEAD..origin/main` prints `67`.
  - `grep -c 'gpt-5\.5' scripts/codex-review.sh scripts/setup.sh CLAUDE.md` reports a hit in each.
  - `git -C .standards cat-file -e origin/main:docs/standards/crux_method.md` succeeds while
    `git -C .standards cat-file -e HEAD:docs/standards/crux_method.md` fails.
- After:
  - `git -C .standards rev-list --count HEAD..origin/main` prints `0`.
  - `git -C .standards rev-parse HEAD` prints `6ad21c4...`, and `test -f .standards/docs/standards/crux_method.md`
    succeeds — the file is present on disk, not merely reachable in the submodule's object store.
  - `git submodule status` reports `.standards` clean, with no leading `+` (gitlink and checkout agree).
  - `git config -f .gitmodules submodule..standards.branch` prints `main`.
  - `grep -r 'gpt-5\.5' scripts/ CLAUDE.md` returns nothing.
  - `bash scripts/test/codex-review.test.sh` exits 0.
  - `flutter analyze` reports no issues; `flutter test` passes 210 tests.
- Versions: `.standards` at `6ad21c4`; Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: `6ad21c4` is a stable point on `my-framework`'s `main`, not mid-refactor. It is the
  merge commit of framework PR #13, so it is a merged, self-tested state rather than an arbitrary
  intermediate commit.
- Assumption: the reviewer model `gpt-5.6-terra` is reachable by the local `codex` CLI. If it is
  not, R2 fails to run on the next push and that absence is noted in the PR, per `codex_review.md`.
- Risk: pinning to an untagged `main` commit reverses the tag-tracking rationale spec `0001`
  recorded, so a future reader finds two specs giving opposite guidance. Mitigated by stating the
  reversal and its condition in Alternatives Considered above; whether this warrants a project-level
  ADR is a Spec Gate question, not a decision this spec makes on its own.
- Risk: declaring `branch = main` makes it easy to move the pin unintentionally, since a stray
  `git submodule update --remote` now resolves to whatever `main` has become and stages a new
  gitlink. Accepted: the gitlink is still a committed, reviewed change, so the move cannot reach
  `main` or CI without passing through a diff someone approves.
- Risk: the framework changed `scripts/test/codex-review.test.sh` in ways beyond the two hunks
  reviewed here, so a merge could drop an upstream fix. Mitigated by reading the full upstream diff
  for that file before merging, rather than applying only the hunks named in Scope.
- What would invalidate this spec: `my-framework` publishing a tag at or past `6ad21c4` before this
  lands, which would restore tag-tracking as the correct pin and make the central trade-off moot.
