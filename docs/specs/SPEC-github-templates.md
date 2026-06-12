# SPEC: chore(github): add pr and issue templates

## Problem

PR and issue bodies follow the framework's `github.md` models only by convention — GitHub pre-fills nothing, so every author must reconstruct the required sections by hand, which invites drift.

## Design Decision

Add `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE.md` mirroring the PR Model and Issue Model from `.standards/docs/standards/github.md`: same section headings in the same order, with placeholder guidance as HTML comments to be replaced with real content (per `ai_guidelines.md`, templates are filled, not left as placeholders). The templates carry no parallel rules or type vocabulary — they reference `github.md` as the single source. Specs for parallel changes live under `docs/specs/`; the root `SPEC.md` remains the merged adoption spec.

## Alternatives Considered

- **GitHub issue forms (`.github/ISSUE_TEMPLATE/*.yml`):** rejected — typed YAML forms are heavier to maintain, render differently from the markdown Issue Model, and the project has a single issue shape today.
- **No templates (status quo):** rejected — manual reconstruction of sections drifts over time; the project's previous internal framework shipped templates and their removal left this gap.

## Scope

- Includes:
  - `.github/PULL_REQUEST_TEMPLATE.md` mirroring the PR Model (Context, What Was Done, How to Test, Evidence, Self-Review Checklist with the review-layers item), plus a reminder of the project's type + complexity label rule.
  - `.github/ISSUE_TEMPLATE.md` mirroring the Issue Model (Description, Context, Current Usage, Recommended Alternative, Acceptance Criteria).
- Does NOT include:
  - CODEOWNERS, CONTRIBUTING.md, or workflow changes.
  - Multiple per-type issue templates or YAML issue forms.
  - CI enforcement of template completion.

## Acceptance Criteria

- `pr_template_mirrors_pr_model_sections`: the PR template contains the five PR Model sections in order, including the review-layers checklist item.
- `issue_template_mirrors_issue_model_sections`: the issue template contains the five Issue Model sections in order.
- `templates_define_no_parallel_vocabulary`: neither template enumerates commit types; both point to `.standards/docs/standards/github.md`.

## Reproducibility

```bash
grep -n '^## ' .github/PULL_REQUEST_TEMPLATE.md   # five PR Model sections in order
grep -n '^## ' .github/ISSUE_TEMPLATE.md          # five Issue Model sections in order
```

No randomness involved; plain-text change.

## Risks and Assumptions

- GitHub applies `ISSUE_TEMPLATE.md` to every new issue (blank-issue fallback remains available via the UI).
- HTML comments act as placeholders and are expected to be deleted when filling the template; an unfilled template submitted as-is is a process violation, not a template defect.
- Invalidated if the team later adopts typed issue forms; the markdown files are then superseded.
