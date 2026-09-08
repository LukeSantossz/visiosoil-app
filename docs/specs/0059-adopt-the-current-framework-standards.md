# SPEC: chore(standards): adopt the current framework standards

## Problem

The `.standards` submodule is pinned 160 commits behind `my-framework`'s `origin/main`, so this repository declares itself bound by a corpus that has since gained four documents, lost one, and rewritten seven — and `mf check agents` cannot run at all, because the source it reads, `docs/agents/instructions.md`, does not exist at the pin.

## Design Decision

**Bump `.standards` to the current `origin/main`, then check each newly binding
norm against this repository and record what it finds — fixing a gap in the same
pull request when the fix is bounded, and filing it otherwise.**

The bump is not the work. A submodule pin is a claim about which rules govern
this repository, and moving it silently would leave `CLAUDE.md` asserting a
corpus nobody read. [Issue #136](https://github.com/LukeSantossz/visiosoil-app/issues/136)
set that precedent for the previous bump and is closed; this spec follows its
shape for the gap that has opened since, which is a different and larger one.

**What becomes binding.** Thirteen documents under `docs/standards/` and
`docs/agents/` change by 1339 insertions against 196 deletions. Four are new and
three of them place obligations this repository has never been measured against:

| Document | What it obliges |
|---|---|
| `r2_gate.md` (new, 452 lines) | the operational R2 chain — how a backend reports itself unavailable, and how the cross-provider requirement resolves to `verified`, `declared` or `unknown` |
| `design.md` (new, 234 lines) | colour roles for surfaces the framework renders, enforced by `mf check design` — which passes today only because the document is absent |
| `status_line.md` (new, 168 lines) | five facts a coding agent's status line must show, and their order |
| `agents/instructions.md` (new, 110 lines) | the source `mf agents sync` generates `CLAUDE.md` and `AGENTS.md` from, and `mf check agents` compares them against |
| `codex_review.md` (removed) | superseded by `r2_gate.md`; `.framework.toml` still declares a `codex` backend |
| `spec_method.md` (+113) | durable numbering enforced by `mf check records`, with a fixed `## Status` format for a Retired or Withdrawn record |
| `token_economy.md` (+23) | the economy becomes opt-in rather than default; a repository that declines it is fully conformant |

**Two consequences are predictable and are named here rather than discovered
during implementation.** First, `mf check agents` currently cannot run; after the
bump it can, and `CLAUDE.md` and `AGENTS.md` were generated from the old source,
so they will very likely report drift and need regenerating through
`mf agents sync`. Second, `mf check design` passes today with the reason *"no
design.md here; nothing declares a surface it governs"*; after the bump the
document exists, and whether this repository declares such a surface has to be
established rather than assumed.

**A gap found is fixed here only when the fix is bounded.** Anything that turns
out to need design — a status line this repository does not have, a surface
`design.md` would govern — is filed as its own issue and named in the pull
request, because adopting a corpus and redesigning against it are two changes and
mixing them would hide the second inside the first.

## Alternatives Considered

- **Bump the pin and nothing else.** Rejected. It makes `CLAUDE.md`'s claim that
  the corpus is binding false in a new way: the rules would have changed and
  nothing would have been checked against them. #136's acceptance criteria exist
  precisely because a pin is a claim about governance.
- **Stay at the current pin.** Rejected. `mf` v0.8.0 is installed and its gates
  read documents the pin does not contain, so `mf check agents` cannot run at
  all — a gate that cannot run is the hole a fail-closed harness exists to
  prevent.
- **Bump to a tag rather than `origin/main`.** Considered and left to the
  Developer at the Gate. The submodule declares `branch = main` and `CLAUDE.md`
  documents `git submodule update --remote --merge .standards` as the deliberate
  bump, so `origin/main` is the documented target; a tag would be a change to how
  this repository tracks the framework and is out of scope here.
- **Adopt the corpus and implement every gap in one pull request.** Rejected.
  The size is unknown until the corpus is read, and a pull request whose scope is
  "whatever we find" cannot be reviewed against a spec.
- **Reopen #136.** Rejected. It is closed and its bump landed; the pin is already
  past the commit it named. Reopening a closed issue to cover a later gap would
  make its record say something it did not do.

## Scope

- Includes:
  - `.standards` — bump the gitlink to the current `origin/main`, as a commit of
    its own.
  - `CLAUDE.md`, `AGENTS.md` — regenerate through `mf agents sync` if and only if
    `mf check agents` reports drift, never by hand.
  - `.framework.toml` — only where a newly binding norm makes a declaration
    wrong, such as a backend whose standards document no longer exists.
  - `docs/agents/project.md` — the overlay, only where this repository's own
    sections must change to stay true under the new corpus.
  - A written check of each newly binding norm against this repository, recorded
    in the pull request body.
- Does NOT include:
  - Implementing any gap the check finds that needs design of its own; those are
    filed as issues and named in the pull request.
  - Adding a status line, or declaring a surface governed by `design.md`.
  - Any change under `lib/`, `ml/`, `test/` or `docs/specs/` beyond this spec.
  - The `exempt_paths` change, which is
    [SPEC 0058](0058-a-run-verdict-reaches-the-repository-after-its-spec-has-merged.md).
  - Changing how this repository tracks the framework — the branch it follows,
    or moving to a tag.

## Acceptance Criteria

- the_pin_moves_in_a_commit_of_its_own: the `.standards` gitlink change is one
  commit that touches nothing else.
- every_gate_runs_rather_than_reporting_a_missing_document: `mf check` reports a
  pass for `spec`, `commit`, `branch`, `docs`, `records`, `agents` and `design`,
  and none of them reports a file it cannot read. *Corrected after R3: this read
  "a pass or a fail", which a failing gate would have satisfied. The intent was
  always that a gate must be able to run and then pass; the original wording let
  the first half stand in for both.*
- the_agent_files_match_their_source: `mf check agents` passes, with `CLAUDE.md`
  and `AGENTS.md` regenerated through `mf agents sync` rather than edited.
- durable_numbering_holds_under_the_new_rule: `mf check records` passes, and any
  record this repository has retired carries the `## Status` section in the format
  `spec_method.md` now fixes, immediately below its title.
- the_declined_token_economy_is_still_recorded: `CLAUDE.md` still states that this
  repository declines the token-economy opt-in, which the new corpus makes a
  choice rather than a default.
- no_backend_names_a_deleted_standard: `.framework.toml` declares no backend whose
  governing document was removed by the bump without that removal being accounted
  for in the same change.
- each_new_norm_is_checked_and_recorded: the pull request body states, for
  `r2_gate.md`, `design.md`, `status_line.md` and `agents/instructions.md`,
  whether this repository already satisfies it, was changed to satisfy it, or has
  an issue filed — with the issue number.
- the_app_suites_stay_green: `flutter analyze` and `flutter test` pass, and
  `ml/` `pytest` passes, so adopting standards is shown to have changed no
  behaviour.

## Reproducibility

```sh
git submodule update --remote --merge .standards
mf agents sync
mf check
flutter analyze && flutter test
cd ml && .venv/Scripts/python.exe -m pytest tests/ -q
```

`mf` v0.8.0 or later on `PATH`.

*Corrected after R3.* This said the bump moves `.standards` from `6ad21c4`
(PR #13) to `origin/main`. Two things were wrong with that. The committed gitlink
on `main` was `0a3e625`, not `6ad21c4` — the latter was checked out in the
working tree without ever being committed — and naming `origin/main` rather than
a commit makes the instruction select a different target every time the branch
moves. **The bump this spec covers is `0a3e625` → `d8feba6`**, and a reproduction
checks that commit out by hash:

```sh
git -C .standards fetch origin
git -C .standards checkout d8feba6
git add .standards
```

## Risks and Assumptions

- **Risk: the corpus obliges more than this repository can absorb in one change.**
  Likely, and the Scope answers it: a gap needing design is filed rather than
  fixed here. The pull request names every issue it opens, so nothing is dropped
  silently.
- **Risk: regenerating `CLAUDE.md` discards project-specific content.** It should
  not — the project's own sections live in the overlay at `docs/agents/project.md`
  and `.framework.toml` declares it — but the regenerated file is diffed against
  the current one before the change is proposed, and any content that would be
  lost is treated as a finding rather than an accident.
- **Assumption: `mf` v0.8.0 reads the new corpus correctly.** It is the release
  that introduced the closed gates, so it expects these documents; the criterion
  that no gate reports a missing file is what tests the assumption.
- **What would invalidate this spec:** a decision to stop tracking `my-framework`'s
  `main`, or a framework release that changes the agent-file generation contract
  again before this lands.
