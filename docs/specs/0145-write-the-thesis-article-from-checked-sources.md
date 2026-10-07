# SPEC: docs(tcc): write the thesis article from checked sources, in pt-BR under docs/tcc

## Problem

The Developer and a co-author are writing an undergraduate thesis article (TCC) about VisioSoil in Brazilian Portuguese, on the institution's template for an original article. Its sources sit in the authors' Drive and change daily, the app it describes changes faster still, and the repository has neither a place for the working material nor a rule that stops an agent from writing about the article from memory or from a stale survey.

## Design Decision

**The material lives under `docs/tcc/`, and that directory is exempt from the all-output-in-English rule.** It joins user-facing UI strings as this project's second language departure, recorded in `docs/agents/project.md` under "Where this project departs from the standards" so an agent that reads the generated instruction files does not translate it back. The exemption is bounded by path: a spec, an ADR, a commit, a pull request or an issue about the article stays in English, which is why this spec is.

**The article itself stays where its authors edit it**, a Google Doc with tabs, whose "TCC" tab is the working copy. The repository holds no copy: the text is the authors', its direction is theirs, and a copy here would be a second version that drifts from the one being written.

**A dedicated section governs every session on the article, and it opens with a check.** `docs/agents/project.md` gains a "Writing the thesis article" section for the Author role, and `docs/tcc/guia-de-redacao.md` holds the procedure in pt-BR. Before any work on the article (writing, reviewing, or answering a question about it), the agent:

1. lists the authors' Drive folder and compares each file's modified time with the last recorded check;
2. reads the working copy, its other tabs and its open comment threads;
3. checks the article's statements about the app against `main` as it stands that day;
4. appends what it read and what diverged to `docs/tcc/conferencias.md`.

A divergence is reported with its source and left to the authors.

**The Google Doc is found by its title, and its identifier stays out of the repository.** The repository is public, and the document's sharing is the authors' to manage, so a link to it does not belong in a file anyone can read. The folder's identifier is recorded, because the folder is shared only with the two authors.

**Three artifacts are dated and one is kept current.** These are snapshots and are not re-verified:

- `revisao-do-rascunho.md` reviews the 2026-10-01 draft against the template and the advisors' notes.
- `revisao-do-projeto.md` surveys what was built up to `64a3333`, each statement citing its record.
- Each entry in `conferencias.md` describes the day it was written.

`guia-de-redacao.md` is the one kept current: its source inventory and its rules change when the authors' folder or decisions do.

**Everything states only what its sources record**, and marks what it does not know. A bibliographic detail, an institution identifier or anything about the laboratory beyond what the records say is left as a named gap rather than filled in, because a thesis is assessed on its sources and an invented one is worse than an absent one.

## Alternatives Considered

- **Write the material in English to keep the rule unbroken.** Rejected. The article, its examining board and its template are in Portuguese, and a review that quotes the draft and proposes wording for it has to be in the draft's language to be usable.
- **Keep the material outside the repository.** Rejected at the Developer's direction: the branch carries it so that the review is written beside the records it checks the draft against.
- **Copy the draft into the repository, or rewrite it as Markdown here.** Rejected. A second copy would drift, and rewriting it would take its direction away from its authors.
- **Rewrite the draft around what the code does.** Rejected at the Developer's direction on 2026-10-01: the focus is what the authors wrote, as an overview of the app's construction rather than a treatise on the model.
- **Rely on the dated survey for the app's facts.** Rejected. Between `64a3333` and `834a9ab` the app changed when it asks for permissions, what a tap in history opens, its schema version and its test counts, and the sheet reader met its first real photographs. A survey pinned to a commit cannot keep up with a draft that cites the app's current behaviour.
- **Put the check in a skill invoked on demand.** Rejected. The Developer made the check mandatory for every session, and a skill runs only when someone remembers to call it; the generated instruction files are read at the start of every session.
- **Record the Google Doc's link with the other sources.** Rejected for a public repository, for the reason above.

## Scope

- Includes:
  - `docs/tcc/README.md`: what the directory holds, the language exemption, and where the article lives.
  - `docs/tcc/guia-de-redacao.md`: the source inventory, the mandatory check, the writing rules and where each statement about the app is checked.
  - `docs/tcc/conferencias.md`: the log of checks, opened with the 2026-10-07 check.
  - `docs/tcc/revisao-do-rascunho.md` and `docs/tcc/revisao-do-projeto.md`: the dated review and survey.
  - `docs/agents/project.md`: the departure bullet and the "Writing the thesis article" section, and the regenerated `CLAUDE.md` and `AGENTS.md` that `mf agents sync` writes from it.
- Does NOT include:
  - The article, its prose or its template, which stay in the authors' Drive.
  - Editing the article to resolve a divergence the check finds. The check reports; the authors decide.
  - Any code, test, asset or CI change.
  - Correcting a record the survey or a check finds stale. A disagreement between records is reported, not fixed here.

## Acceptance Criteria

- the_check_precedes_every_session: the "Writing the thesis article" section in `docs/agents/project.md` requires the four-step check before any work on the article, and names `docs/tcc/guia-de-redacao.md` and `docs/tcc/conferencias.md`.
- the_guide_lists_every_source_it_requires: each Drive file the check reads appears in the guide's inventory with its role, and the inventory names the date it was taken.
- the_article_link_is_not_published: no file in the repository carries the Google Doc's identifier or link.
- every_check_names_what_it_read: each entry in `conferencias.md` names the date, the files and commit it read, and each divergence with the source that shows it.
- every_divergence_leaves_the_choice: no entry or review proposes a change to the article's objective or direction.
- the_material_marks_what_it_does_not_know: institution data, bibliography and any figure the records do not hold appear as explicit gaps, not as values.
- the_survey_separates_measured_implemented_and_planned: no planned or in-flight work, open pull requests included, is described as done, and every result names where it was measured.
- the_exemption_is_bounded_by_path: `docs/agents/project.md` exempts `docs/tcc/` only, and this spec, its commits and its pull request are in English.
- the_generated_instruction_files_match_their_source: `mf check agents` passes after `mf agents sync`.
- no_code_changes: the branch changes nothing outside `docs/` and the two generated instruction files.

## Reproducibility

```sh
git diff --name-only main... | grep -v '^docs/\|^CLAUDE.md$\|^AGENTS.md$'   # prints nothing
git grep -nE 'docs\.google\.com/document/d/' -- docs CLAUDE.md AGENTS.md   # prints nothing
mf agents sync && mf check
```

No test and no seed: every criterion is over prose. The survey describes `main` at `64a3333`, the review describes the draft of 2026-10-01, and each check describes its own day.

## Risks and Assumptions

- **Assumption: the institution accepts an article written with an AI assistant's help in reviewing it.** Whether that help must be declared is the authors' to check against the institution's rules; nothing here can.
- **Risk: a check is skipped.** The rule lives in the instruction files every session reads, but nothing enforces it mechanically. A session that writes about the article without a dated entry in `conferencias.md` is the sign it was skipped.
- **Risk: the folder moves or is renamed.** The guide's inventory then fails to resolve, which the next check reports, and the inventory is updated from what the authors say.
- **Risk: this spec reaches `main` after another takes its number.** This work first carried 0100, which `main` assigned to another spec while the branch was open, so the branch was rebuilt on `main` with the next number no open pull request reserved. Open pull requests held 0142 to 0144 when this was written.
- **What would invalidate this spec:** the institution requiring the article in English, or the authors deciding the material does not belong in the repository.
