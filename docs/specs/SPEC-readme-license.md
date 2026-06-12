# SPEC: docs(license): add mit license and readme section

## Problem

The repository is public but declares no license, so default all-rights-reserved copyright applies, and the README is missing the License section that the framework's README Model marks as the mandatory final section.

## Design Decision

Add the standard MIT license text as `LICENSE` at the repository root with the copyright line "Copyright (c) 2026 LukeSantossz", and append the canonical `## License` section to the end of `README.md`, stating MIT and linking the file. MIT was chosen by the owner at the Spec Gate for this change (session decision, 2026-06-12). Specs for parallel changes live under `docs/specs/` so concurrent PRs do not collide on a single root `SPEC.md`; the root file remains the merged adoption spec.

## Alternatives Considered

- **Proprietary (all rights reserved, no LICENSE file):** rejected by the owner — the repository is a public portfolio project and permissive reuse is desired.
- **Apache-2.0:** rejected — the explicit patent grant adds length and ceremony with no current need; MIT is simpler and was the owner's pick.
- **GPL-3.0:** rejected — copyleft would constrain reuse of the code by others, which is not desired here.

## Scope

- Includes:
  - `LICENSE` file at the repository root with the unmodified MIT text.
  - `## License` section appended after Contributing as the final README section, per the README Model's canonical order.
- Does NOT include:
  - License headers in source files.
  - `pubspec.yaml` metadata changes.
  - Any README restructuring beyond the new section.
  - A `CONTRIBUTING.md` file.

## Acceptance Criteria

- `license_file_contains_mit_text`: `LICENSE` exists at the root, starts with "MIT License", and contains the 2026 copyright line.
- `readme_ends_with_license_section`: `## License` is the final section of `README.md`, states MIT, and links to `LICENSE`.
- `readme_section_order_unchanged`: all pre-existing README sections remain in their current order; only the final section is added.

## Reproducibility

```bash
head -3 LICENSE                      # expect: MIT License + copyright line
grep -n '^## ' README.md | tail -3   # expect: ... Contributing, License (last)
```

No randomness involved; plain-text change.

## Risks and Assumptions

- The copyright holder is rendered as the GitHub handle "LukeSantossz" because no legal name is on file; the owner can amend the single line in review.
- Assumes MIT is intended to cover the whole repository, including the `ml/` pipeline and placeholder model assets.
- Invalidated if the owner later opts for a different license; the change is a two-file revert.
