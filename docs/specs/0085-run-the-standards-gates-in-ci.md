# SPEC: ci: run the standards gates in ci, not only in the hooks

## Problem

`mf check` runs only in the git hooks, so a pull request from a clone that never
wired `core.hooksPath`, or from a machine without `mf`, passes CI with no gate at
all and no record that none ran, although `.standards/docs/standards/INDEX.md`
requires the same `mf check` in CI (#201).

## Scope

- Includes:
  - A `gates` job in `.github/workflows/ci.yml`, modelled on the framework's own
    `.standards/.github/workflows/gate.yml`:
    - It checks out full history with the `.standards` submodule and no
      persisted credentials, under a read-only token.
    - It installs `mf` at the `framework_version` that `.framework.lock`
      records. It downloads that tag's `linux_amd64` release asset and
      `SHA256SUMS` from `LukeSantossz/my-framework`, and verifies the asset's
      checksum. It fails when the binary's `mf version` disagrees with the lock,
      and names the version it ran in the job summary.
    - On a pull request, it restores the head and base refs that
      `actions/checkout` leaves detached, then runs `mf check`.
    - On any other event (a push to `main` or `dev`, or a manual dispatch), it
      runs the four tree-level gates, `mf check docs records agents design`.
  - A test that pins the job's shape, as `test/ci_ios_build_test.dart` does for
    `build-ios`.
  - The CI job lists in `docs/agents/project.md`, with `CLAUDE.md`
    regenerated, and in the README checklist.
  - After merge, #201 is closed.
- Does NOT include:
  - `mf review --role r2`. It calls a model, needs credentials CI does not
    have, and is advisory (#201).
  - Building `mf` from source. The framework does that because it tests its own
    tree. An adopter runs the released binary the lock names.
  - Making `build` or any other job depend on `gates`, or configuring branch
    protection.
  - Any change to the hooks, `.framework.lock` or the `.standards` pin.

## Acceptance Criteria

- `the_gates_job_runs_mf_check_on_a_pull_request`: the `gates` job checks out
  full history with the submodule, restores the pull request's head and base
  refs, and runs `mf check` only on `pull_request`.
- `the_gates_job_runs_the_tree_gates_on_any_other_event`: when the event is not
  `pull_request`, the job runs `mf check docs records agents design`.
- `the_gates_job_installs_the_locked_mf_version`: the job reads
  `framework_version` from `.framework.lock`, verifies the downloaded asset
  against `SHA256SUMS`, fails when `mf version` disagrees with the lock, and
  writes the version to the job summary.
- `the_gates_job_passes_on_this_pull_request_and_on_main`: observed in CI. The
  job passes on this change's own pull request, and the tree-level run passes
  on `main` after merge.
