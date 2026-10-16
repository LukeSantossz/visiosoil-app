# SPEC: docs: sync the readme and the agent overlay with what has shipped

## Problem

The README and the agent overlay (`docs/agents/project.md`, from which `CLAUDE.md` is generated) describe a `main` several weeks old. They say schema v4, eight routes, MobileNetV2 training and management tips that are "always unavailable". They also miss the privacy pages, the dependency majors and the corpus state that shipped on 2026-10-14 and 15. And #251 asks for its B1' verdict to be recorded in the research-agent implementation map.

## Scope

- Includes:
  - `README.md`, checked against `main` at `37ba409`:
    - What It Does, Tech Stack, the database schema section, Project Structure, Project Status and Known Issues;
    - the test counts measured on 2026-10-15.
  - `docs/agents/project.md` and the regenerated `CLAUDE.md` (`mf agents sync`):
    - the theme, constants and widgets layout;
    - the `pages.yml` workflow;
    - the corpus calibration state;
    - the Tink keep rule as technical debt.
  - `docs/architecture/research-agent-implementation-map.md`: the B1' verdict of 2026-10-15 and the follow-ups before B3.
- Does NOT include:
  - Any code, test, workflow or asset.
  - The ADRs and the Engineering Decisions table, which no shipped change affects.
  - `docs/design/` and `docs/ml/`. The motion catalogue's drift is the visual-alignment work's to fix.
  - `AGENTS.md`, which `mf agents sync` reports as already current.

## Acceptance Criteria

- `readme_states_the_current_schema_and_routes`: the README says schema v9 and 9 routes, and no longer says v4 or 8 routes.
- `readme_describes_the_shipped_classifier_and_tips`: the README names the descriptor probe as the released model, and the corpus path, not the proxy, as how tips compose.
- `readme_links_the_published_privacy_pages`: the README links both `site/` pages at their live URLs.
- `the_overlay_and_claude_md_agree`: `mf check agents` passes.
- `the_b1_verdict_is_recorded`: the implementation map's B1 section records the 2026-10-15 verdict and the three follow-ups.
- `mf check` passes.
