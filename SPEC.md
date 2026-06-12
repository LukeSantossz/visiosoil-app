# SPEC: chore(governance): adopt my-framework standards as git submodule

## Problem

The project has no binding, versioned development-standards layer: conventions live only as a short section of `CLAUDE.md`, with no spec gate, review composition, or test-first policy an AI agent is required to follow.

## Design Decision

Add [my-framework](https://github.com/LukeSantossz/my-framework) as a git submodule at `.standards/`, pinned to a reviewed commit, and merge a "Development Standards" section into the existing project `CLAUDE.md` pointing at the submodule paths. The existing `CLAUDE.md` is preserved (merge, not overwrite), and where its project-specific conventions differ from framework defaults they win, per the precedence order in `code_conventions.md` (rule 4: the project's established pattern outranks any default). Tooling the framework references but does not ship (Superpowers, Codex, Caveman) is not configured by this change; CodeRabbit is already active on opened PRs and serves as the R3 layer. The documented fallbacks apply to the missing layers and deviations are recorded in the merged section.

## Alternatives Considered

- **Vendor the docs (copy files into the repo):** rejected. Copies drift silently from upstream, updates require manual re-copying with no record of which framework version the project follows, and the framework is in active development (first version published 2026-06-09).
- **Reference the GitHub URL only, with no local copy:** rejected. Agent sessions would depend on network access at runtime to read the standards; a clone with the submodule initialized makes them readable offline and pins the exact version reviewed.
- **git subtree instead of submodule:** rejected. Subtree merges the framework history into the project history and makes pulling upstream updates noisier; the submodule gitlink gives a single-line, auditable version pin, and the standards are read-only consumption (never edited from this repo).

## Scope

- Includes:
  - `git submodule add https://github.com/LukeSantossz/my-framework .standards` (creates `.gitmodules` and the `.standards` gitlink pinned at commit `9c291b2`).
  - Merge a "Development Standards" section into the existing `CLAUDE.md`, adapted from the framework's own `CLAUDE.md` with three corrections: paths prefixed with `.standards/`, the token-economy reference pointed at `.standards/token_economy.md` (the file lives at the framework root, not in `docs/standards/` as the adoption guide assumes), and a note that `CLAUDE.md` is not kept in caveman-compress form until the Caveman tool is configured.
  - In the same section: the R2 fallback note (no second-provider reviewer is configured, so R1 plus human PR review stand in for R2 and the absence is noted in each PR), a note that CodeRabbit reviews opened PRs as the R3 layer, an instruction to run `git submodule update --init` when `.standards/` is empty (fresh clones, CI, remote agent sessions), and a clarification that user-facing UI strings are pt-BR product copy and are not subject to the all-English rule (which covers identifiers, comments, commits, PR/issue text, and documentation).
- Does NOT include:
  - Translating the 99 Portuguese doc comments found across 23 files in `lib/` (follow-up change with its own spec).
  - Adding the missing `## License` README section or a LICENSE file (follow-up).
  - Adding `.github/PULL_REQUEST_TEMPLATE.md` / issue templates derived from `github.md` (follow-up).
  - Configuring Superpowers, Codex, or Caveman (CodeRabbit is already configured and reviews opened PRs).
  - Any CI workflow change (the build does not read the standards; `actions/checkout@v4` skips submodules by default and stays green).
  - Any Dart code change, and any of the technical-debt items already listed in `CLAUDE.md`.
  - Compressing `CLAUDE.md` with caveman-compress.

## Acceptance Criteria

- `submodule_status_lists_standards_pinned`: `git submodule status` prints one line for `.standards` at commit `9c291b2`.
- `standards_index_resolves_after_init`: after `git submodule update --init`, `.standards/docs/standards/INDEX.md` exists and lists the six standards documents.
- `claude_md_paths_resolve_to_existing_files`: every `.standards/...` path referenced in the merged `CLAUDE.md` resolves to an existing file (including `.standards/token_economy.md`).
- `claude_md_preserves_existing_project_sections`: the merged `CLAUDE.md` still contains the pre-existing Project, Commands, Architecture, Conventions, CI Pipeline, Current Limitations, and Known Technical Debt sections unchanged.
- `ci_unaffected_by_docs_only_change`: `flutter analyze` and `flutter test` produce the same results as before the change (no Dart source is touched).

## Reproducibility

```bash
git submodule add https://github.com/LukeSantossz/my-framework .standards
git submodule status                  # expect: 9c291b2... .standards
git submodule update --init           # on a fresh clone
flutter analyze && flutter test       # unchanged results
```

Versions: my-framework at `9c291b20a424a2ab1c51c88deb59197164fd2d40` ("feat: implement first version of the framework", 2026-06-09); Flutter 3.38.5 (per CI); no randomness involved.

## Risks and Assumptions

- Assumes `github.com/LukeSantossz/my-framework` remains publicly clonable; verified reachable from this environment on 2026-06-12. If it goes private, clones need credentials and the vendoring alternative should be revisited.
- Fresh clones, CI runners, and remote agent sessions receive an empty `.standards/` unless they run `git submodule update --init`; mitigated by the instruction added to `CLAUDE.md`. CI needs nothing because the build never reads the standards.
- The adoption guide and the framework repo disagree about `token_economy.md`'s location (`docs/standards/` vs repo root), and the two `INDEX.md` files disagree about whether it is listed; this spec follows the repo's actual layout. An upstream fix in my-framework would remove the discrepancy.
- The framework is three days old and in active development; the pin means upstream changes enter this project only through a deliberate `git submodule update --remote` reviewed in its own commit.
- Invalidated if the project decides to vendor the standards or to adopt a different governance framework.
