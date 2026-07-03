# SPEC: chore(standards): bump framework submodule to v0.1.0 and close the activation gap

## Problem

The `.standards` submodule is pinned at `776a1b5`, an ancestor of the `v0.1.0` tag (93 commits
behind), so every framework component introduced up to `v0.1.0` is absent here: `scripts/setup.sh`,
`scripts/test/docs-consistency.sh`, the durable `docs/specs/NNNN-<slug>.md` archive model, the
spec-lite tier, `skills_guidelines.md`, and the hardened issue/PR templates and `codex-review.sh`.

## Design Decision

Move the submodule gitlink to the `v0.1.0` tag — not the submodule's `origin/main` HEAD, because a
pinned framework tracks a released tag and the post-tag commits are internal guard hardening. Create
this repository's own `docs/specs/` archive and adopt the `NNNN-<slug>.md` numbering going forward,
seeding it by migrating this very spec (the last one authored under the transient root `SPEC.md`
model) to `docs/specs/0001-bump-standards-submodule.md`. Refresh the copied framework artifacts
(`scripts/codex-review.sh`, `.githooks/`, `.github/` templates) to their `v0.1.0` versions where they
differ. Verify activation with `bash scripts/setup.sh` (non-interactive: hooks are already active and
the triage labels already exist, so it runs idempotently) and consistency with
`bash scripts/test/docs-consistency.sh`.

## Alternatives Considered

- **Pin to the submodule's `origin/main` HEAD** — rejected: `main` is ~5 commits past the tag with
  only internal guard hardening; a pinned dependency should track a released tag, not a moving branch.
- **Copy the framework files into the repo instead of bumping the submodule** — rejected: the project
  deliberately adopts via submodule (`.gitmodules`); copying would fork the standards and lose
  upstream updates and the docs-consistency guarantee.
- **Leave the pin and cherry-pick only `setup.sh`/`docs-consistency.sh`** — rejected: partial adoption
  reintroduces the drift the docs-consistency check exists to prevent and desyncs the templates and
  `codex-review.sh` from the standards they enforce.

## Scope

- Includes:
  - Update the `.standards` gitlink to the `v0.1.0` tag and commit the new pin.
  - Create `docs/specs/` and migrate this spec into it as `0001-bump-standards-submodule.md`.
  - Refresh `scripts/codex-review.sh`, `.githooks/`, and `.github/` templates to their `v0.1.0`
    versions where they differ.
  - Run `bash scripts/setup.sh` (confirm hooks/labels/toolchain active) and
    `bash scripts/test/docs-consistency.sh` (clean).
  - Update `CLAUDE.md` workflow notes that reference the old single-`SPEC.md` model to the
    `docs/specs/` model.
- Does NOT include:
  - Wiring the framework self-test `docs-consistency.test.sh` into this repository's CI (it pins the
    framework's own files and is not for adopting projects).
  - Running `setup.sh --interactive` / persisting a reviewer-model choice (maintainer-only; it mutates
    personal local git config).
  - Any application code, database schema, or dependency change.
  - Backfilling historical specs beyond seeding this one; the archive grows forward from here.

## Acceptance Criteria

- `standards_submodule_checked_out_at_v0_1_0_tag_and_pin_committed`
- `setup_sh_reports_hookspath_labels_and_toolchain_active`
- `docs_specs_exists_and_holds_this_spec_under_nnnn_slug_numbering`
- `issue_and_pr_templates_match_v0_1_0`
- `docs_consistency_sh_passes`
- `claudemd_spec_workflow_notes_reference_the_docs_specs_model`

## Reproducibility

- Config/tooling change, no unit test. The test-first step (per `spec_method.md` for config changes)
  maps to first demonstrating the gap on the current pin, then showing it resolved after the bump:
  - Before: `test -d docs/specs || echo MISSING` prints MISSING; `test -f scripts/setup.sh || echo
    MISSING` prints MISSING; `git -C .standards describe --tags` fails ("No tags can describe").
  - After: `git -C .standards describe --tags` prints `v0.1.0`; `bash scripts/setup.sh` reports active;
    `bash scripts/test/docs-consistency.sh` exits 0.
- Versions: `.standards` at tag `v0.1.0`; app toolchain Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: the `v0.1.0` `setup.sh`/`docs-consistency.sh` run under Git Bash on Windows (the
  framework CI runs them on Linux). A POSIX-portability gap surfaces as a failed check, in scope to
  note; if a check is Windows-incompatible, record it and let the human CRURA review stand in for that
  step.
- Assumption: refreshing `.githooks/`/`codex-review.sh` to `v0.1.0` does not change the pre-push
  contract in a blocking way (it is advisory/non-blocking today). If it does, note it in the PR.
- Risk: seeding `docs/specs/0001` from this spec numbers a tooling change as the first archived spec;
  accepted — the archive is a forward-growing record, mirroring how the framework's own `docs/specs/`
  was established.
- No app-level ADR: the adopted decisions (the `docs/specs/` model, tag-tracking) are the framework's
  own and are already recorded in the framework's ADRs; this change adopts them rather than
  originating a project-level trade-off.
