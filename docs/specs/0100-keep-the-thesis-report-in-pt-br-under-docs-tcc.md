# SPEC: docs(tcc): keep the thesis report in pt-BR under docs/tcc

## Problem

The Developer is writing an undergraduate thesis report (TCC) about VisioSoil, and the repository has no place for it: every document here must be in English, while the report is due in Brazilian Portuguese, on the institution's template, and has to describe problem, context, solution, methods and results that today are scattered across 92 specs, 26 ADRs, five run verdicts and the git history.

## Design Decision

**The report lives under `docs/tcc/`, and that directory is exempt from the all-output-in-English rule.** It joins user-facing UI strings as this project's second language departure, recorded in `docs/agents/project.md` under "Where this project departs from the standards" so an agent that reads the generated instruction files does not translate it back. The exemption is bounded by path: a spec, an ADR, a commit, a pull request or an issue about the report stays in English, which is why this spec is.

**The first artifact is a survey of what was built, not the report.** `docs/tcc/revisao-do-projeto.md` organises the repository's own records under the sections a thesis report needs — problem, context and background, the solution, methods, results, limitations — and cites the spec, ADR or verdict each statement comes from. The Developer supplies the template and the prose; the survey is the factual base both are written from, and the citations are what let a sentence in the report be checked against the record it summarises.

**The survey states only what the repository records**, and marks what it does not know. Bibliographic references, the institution's identifiers and anything about the laboratory beyond what the records say are left as named gaps rather than filled in, because a thesis is assessed on its sources and an invented one is worse than an absent one.

**The template is not chosen here.** The Developer will supply it, so `docs/tcc/README.md` says where it goes and how the survey maps onto it, and nothing commits the report to Markdown, LaTeX or Word.

## Alternatives Considered

- **Write the report in English to keep the rule unbroken.** Rejected. The audience is a Brazilian examining board and the institution's template, and an English draft would be translated by hand, which is where the citations to the record are lost.
- **Keep the report outside the repository.** Rejected at the Developer's direction: the branch carries the report so that it is written beside the records it describes and reviewed like any other change. Outside, the survey's citations would point at a moving tree with nothing pinning which commit they describe.
- **Draft the full report now, prose included.** Rejected at the Developer's direction: the Developer writes the content and supplies the template. A full draft written ahead of the template would also have to be re-cut to whatever chapter structure the institution mandates.
- **Exempt `docs/` wholesale, or exempt by a per-file marker.** Rejected. A directory-wide exemption would let an architecture note drift into Portuguese, and a marker is a rule nothing checks. One named directory is the narrowest boundary that holds the report.

## Scope

- Includes:
  - `docs/tcc/README.md` — what the directory holds, the language exemption, and where the template and its chapters go.
  - `docs/tcc/revisao-do-projeto.md` — the survey of what was built, in pt-BR, organised by report section, every claim citing its record.
  - `docs/agents/project.md` — one bullet under "Where this project departs from the standards", and the regenerated `CLAUDE.md` and `AGENTS.md` that `mf agents sync` writes from it.
- Does NOT include:
  - The report itself, its chapters or its prose — the Developer supplies them.
  - The institution's template, a build pipeline for it, or any choice of Markdown, LaTeX or Word.
  - Bibliographic references from outside the repository.
  - Any code, test, asset or CI change.
  - Correcting a record the survey finds stale. A disagreement between records is reported in the survey, not fixed here.

## Acceptance Criteria

- every_survey_claim_cites_its_record: each factual paragraph and table in `revisao-do-projeto.md` names the spec, ADR, verdict or file it comes from.
- the_survey_marks_what_it_does_not_know: institution data, bibliography and any figure the records do not hold appear as explicit gaps, not as values.
- the_survey_separates_measured_implemented_and_planned: no planned or in-flight work (open pull requests included) is described as done, and every result names where it was measured.
- the_exemption_is_bounded_by_path: `docs/agents/project.md` exempts `docs/tcc/` only, and this spec, its commits and its pull request are in English.
- the_generated_instruction_files_match_their_source: `mf check agents` passes after `mf agents sync`.
- no_code_changes: the branch changes nothing outside `docs/` and the two generated instruction files.

## Reproducibility

```sh
git diff --name-only main... | grep -v '^docs/\|^CLAUDE.md$\|^AGENTS.md$'   # prints nothing
mf agents sync && mf check
```

No test and no seed: every criterion is over prose. The survey describes `main` at `64a3333` (2026-10-01); a statement in it is true of that commit and is not re-verified when `main` moves.

## Risks and Assumptions

- **Assumption: the institution accepts a report in Portuguese written with an AI assistant's help.** Whether it requires that help to be declared is the Developer's to check against the institution's rules; nothing here can.
- **Risk: the survey goes stale.** Seven pull requests were open when it was written, and the records it cites keep moving. It names the commit it describes so a reader can tell, and it is a working base for the report, not a record the repository maintains.
- **Risk: the branch gate fails.** The branch this work was assigned to, `claude/hopeful-feynman-46ghac`, has a type that is not in `github.md`'s Type Table, so `mf check branch` fails on it. Renaming it to `docs/tcc-report` before a pull request is opened clears it.
- **Risk: this spec reaches `main` before the numbers below it.** 0093 to 0099 were reserved by the seven open pull requests when this was written, so 0100 is the next free number. `durable_numbering_test.dart` enforces contiguity on `main`, so this branch merges after those seven, or takes the next free number at the time it merges if one of them is closed instead.
- **What would invalidate this spec:** the institution requiring the report in English, or the Developer deciding the report does not belong in the repository.
