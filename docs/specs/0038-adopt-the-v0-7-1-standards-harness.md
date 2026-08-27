# SPEC: chore(standards): adopt the v0.7.1 harness

## Problem

This repository vendors the development standards as a `.standards` submodule
and is pinned to `v0.1.0-67-g6ad21c4` — a commit from before the framework had a
binary at all. Everything downstream of that pin is stale or dead:

- `core.hooksPath` is unset, and the only hook, `.githooks/pre-push`, is the
  pre-v0.5.0 shape: it ends its failure paths with `exit 0`, so a missing runner
  reads as a passing gate. There is no `commit-msg` hook, so nothing checks a
  commit subject against the Conventional Commits vocabulary.
- The R2 review runs through `scripts/codex-review.sh`, a shell reimplementation
  the framework replaced with `mf` and no longer ships.
- There is no `.framework.toml`, so no role has a chain and nothing records
  which provider authored a change. R2's cross-provider requirement can only
  resolve to `unknown`.
- `scripts/test/docs-consistency.sh` reads `docs/standards`, which does not
  exist here — the corpus is in the submodule — so the check it performs has
  been vacuous since adoption.
- `scripts/setup.sh` writes `codexreview.model` and `codexreview.effort`, which
  nothing has read since the framework's key space changed.
- `CLAUDE.md` and `AGENTS.md` are hand-written, so the framework text in them is
  frozen at whatever day it was pasted, and the two disagree about which
  standards are current.

## Design Decision

Adopt `v0.7.1` and let the harness own what it owns.

Two things in that release are why this migration waited for it. The 130 lines
of project-specific instructions in `CLAUDE.md` are the first: until
`paths.agents_overlay` landed in `v0.7.0`, a repository vendoring the corpus
generated the framework's text and nothing else, and adopting meant deleting
them or failing the agents gate. They now live in `docs/agents/project.md`, marked with the same
role markers, and `mf agents sync` appends them to each generated file after the
framework's sections. Nothing is lost and nothing is hand-maintained twice.

The second is the numbering gate. PR #198 holds spec `0037`, so this branch must
claim `0038` and its archive has a gap it did not make. Until `v0.7.1` the
records gate read that as a deleted record and refused the push, and both hooks
fail closed, so there was no way to adopt the harness and open this pull request
at the same time.

`scripts/setup.sh` keeps only what is this repository's: the triage labels, which
live in its tracker. Wiring the hooks and reporting what resolves are `mf hooks
install` and `mf doctor`, called rather than reimplemented — a second
implementation of activation is a second thing that can be wrong about it.

The CI test job now checks out the submodule. That is one line and it is the
same reasoning as the `fetch-depth: 0` above it: a guard that reads an empty
directory passes vacuously, which is the failure this repository already wrote a
comment about once. It was found by the guard failing in CI, not by reading.

`test/standards/harness_wiring_test.dart` is new, and it is the lesson from the
two repositories that adopted before this one: both staged their hooks `100644`,
because `core.fileMode` is false on the Windows checkout that wrote them, and
git skips a non-executable hook silently. It asserts index state and executes
each hook against an unusable runner, because a gate that cannot run has not
passed.

R3 is declared as `coderabbit`, which reviews every pull request here. Greptile
also does and is deliberately not declared: it is not configured through this
file, and naming it would claim a route that does not exist.

## Alternatives Considered

- **Pin `v0.6.2` and keep the project instructions out of `CLAUDE.md`.**
  Rejected: the only places left are `CONTEXT.md`, whose own skill says it is a
  domain glossary and to proceed silently when absent, and `README.md`, which no
  agent is instructed to read first. The toolchain pin and the ADR 0011 retry
  prohibition would have moved somewhere nothing loads.
- **Keep `scripts/codex-review.sh` alongside `mf`.** Rejected: two runners for
  one gate, and the shell one is the version whose failure paths pass.
- **Assert `core.hooksPath` in the guard.** Rejected: it is local git config a
  fresh clone never has, so the test would fail in CI for the one reason that is
  not a defect. This exact assertion was written and removed in the previous
  consumer's migration.
- **Take spec number 0037.** Rejected: PR #198 holds it, and a durable number is
  never reused — two records with the same number would make every reference to
  it ambiguous.
- **Stack this branch on PR #198 so the archive is contiguous.** Tried and
  rejected: it made an infrastructure migration wait on an ML spec that has not
  passed its Gate, and it put that spec's own gate failures — a `# SPEC (full):`
  header and a Scope with no "Does NOT include" list — inside this change to
  answer.

## Scope

- Includes: the submodule pin at `v0.7.1`; `.framework.toml` and
  `.framework.lock`; both hooks written and staged executable;
  `docs/agents/project.md` and the regenerated `CLAUDE.md` and `AGENTS.md`;
  `scripts/setup.sh` rewritten to delegate; deletion of
  `scripts/codex-review.sh`, `scripts/test/codex-review.test.sh` and
  `scripts/test/docs-consistency.sh`; `test/standards/harness_wiring_test.dart`;
  the README's Installation and Contributing sections; `submodules: recursive`
  on the CI test job's checkout.
- Does NOT include: any change to application code, the ML pipeline, or any ADR;
  any other change to the CI workflow; the work on the open PR #198, which is a different
  change on a different branch; `CONTEXT.md`, which stays the domain glossary it
  is; pinning reviewer models with `mf models pin`, which is a machine decision.

## Acceptance Criteria

- `both_hooks_are_versioned_in_this_repository`
- `the_index_records_both_hooks_as_executable`
- `a_hook_that_cannot_reach_its_runner_refuses_the_push`
- `no_second_standards_corpus_exists_beside_the_submodule`
- `the_paths_name_the_submodule`
- `the_r2_chain_names_a_reviewer_that_is_defined`
- `this_repository_owns_the_overlay_the_generated_files_carry`
- `the_generated_files_say_they_are_generated`
- `mf check` passes all seven gates.
- Every instruction the old `CLAUDE.md` carried is still in the generated one.

## Reproducibility

```sh
git submodule status .standards          # v0.7.1
git ls-files --stage .githooks/          # 100755 for both
mf doctor                                # every role names a defined backend
mf check                                 # 7/7
flutter test test/standards/
```

Versions: `mf` v0.7.1, Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Risk: a contributor's existing clone has neither `mf` on `PATH` nor
  `core.hooksPath` set, and both hooks fail closed, so their next commit is
  refused. That is the intended behaviour of a gate and the reason the README's
  Installation section now names `scripts/setup.sh`, but it is a break in the
  moment it happens.
- Risk: the backend definitions in `.framework.toml` are copied from the
  framework's own file rather than referenced, because a backend is declared per
  repository and there is no mechanism for sharing one. They will drift; the
  comment above them says to keep them in step by hand.
- Assumption: `codex` and `agy` are on the Developer's machine. Both are on this
  one, and the chain is first-available fallback, so an absent one advances the
  chain rather than failing the push.
