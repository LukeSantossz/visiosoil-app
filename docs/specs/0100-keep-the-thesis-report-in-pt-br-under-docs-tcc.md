# SPEC: docs(tcc): keep the thesis report's review material in pt-BR under docs/tcc

## Problem

The Developer and a co-author are writing an undergraduate thesis article (TCC) about VisioSoil in Brazilian Portuguese, on the institution's template for an original article, and the repository has no place for the material that reviews that draft against the app it describes: every document here must be in English, and the facts the article needs are scattered across 92 specs, 26 ADRs, five run verdicts and the git history.

## Design Decision

**The material lives under `docs/tcc/`, and that directory is exempt from the all-output-in-English rule.** It joins user-facing UI strings as this project's second language departure, recorded in `docs/agents/project.md` under "Where this project departs from the standards" so an agent that reads the generated instruction files does not translate it back. The exemption is bounded by path: a spec, an ADR, a commit, a pull request or an issue about the article stays in English, which is why this spec is.

**The article itself stays where its authors edit it**, a Google Doc with tabs in their Drive, on the institution's template. The repository holds no copy: the text is the authors', its direction is theirs, and a copy here would be a second version that drifts from the one being written.

**Two artifacts, with the draft as the reference.**

- `docs/tcc/revisao-do-rascunho.md` reviews the 2026-10-01 draft against the template and the advisor's notes: structure, introduction, materials and methods, citations and references, and what the results, abstract and conclusion still need. It does not change the draft's direction, at the Developer's instruction. Where the draft describes the app in a way the code no longer confirms — TensorFlow Lite as the runtime, MobileNetV2 as the model, CI training the model, management recommendations with content behind them — it states what the code shows, cites the record, and leaves the decision to the authors.
- `docs/tcc/revisao-do-projeto.md` surveys what was built, organised by the template's sections, and cites the spec, ADR or verdict each statement comes from. It is reference material the draft can draw on, not a structure the draft must follow.

**Both state only what their sources record**, and mark what they do not know. Bibliographic references, the institution's identifiers and anything about the laboratory beyond what the records say are left as named gaps rather than filled in, because a thesis is assessed on its sources and an invented one is worse than an absent one.

## Alternatives Considered

- **Write the material in English to keep the rule unbroken.** Rejected. The article, its examining board and its template are in Portuguese, and a review that quotes the draft and proposes wording for it has to be in the draft's language to be usable.
- **Keep the material outside the repository.** Rejected at the Developer's direction: the branch carries it so that the review is written beside the records it checks the draft against, and pinned to the commit it describes.
- **Copy the draft into the repository, or rewrite it as Markdown here.** Rejected. The authors edit it in Google Docs on the institution's template; a second copy would drift, and rewriting it would take its direction away from its authors, which the Developer ruled out.
- **Rewrite the draft around what the code does.** Rejected at the Developer's direction on 2026-10-01: the focus is what the authors wrote. The code is used only to check the draft's claims about the app, and each divergence is theirs to resolve.
- **Exempt `docs/` wholesale, or exempt by a per-file marker.** Rejected. A directory-wide exemption would let an architecture note drift into Portuguese, and a marker is a rule nothing checks. One named directory is the narrowest boundary that holds the material.

## Scope

- Includes:
  - `docs/tcc/README.md` — what the directory holds, the language exemption, and where the article itself lives.
  - `docs/tcc/revisao-do-rascunho.md` — the review of the 2026-10-01 draft.
  - `docs/tcc/revisao-do-projeto.md` — the survey of what was built, every claim citing its record.
  - `docs/agents/project.md` — one bullet under "Where this project departs from the standards", and the regenerated `CLAUDE.md` and `AGENTS.md` that `mf agents sync` writes from it.
- Does NOT include:
  - The article, its prose or its template — they stay in the authors' Drive.
  - Rewriting the draft, or changing its direction.
  - Bibliographic references from outside the repository.
  - Any code, test, asset or CI change.
  - Correcting a record the survey finds stale. A disagreement between records is reported in the survey, not fixed here.

## Acceptance Criteria

- every_survey_claim_cites_its_record: each factual paragraph and table in `revisao-do-projeto.md` names the spec, ADR, verdict or file it comes from.
- every_divergence_cites_the_code_and_leaves_the_choice: each row in the review's divergence table names the record or file that shows the app's behaviour, and the review proposes no change to the draft's objective or direction.
- the_material_marks_what_it_does_not_know: institution data, bibliography and any figure the records do not hold appear as explicit gaps, not as values.
- the_survey_separates_measured_implemented_and_planned: no planned or in-flight work (open pull requests included) is described as done, and every result names where it was measured.
- the_exemption_is_bounded_by_path: `docs/agents/project.md` exempts `docs/tcc/` only, and this spec, its commits and its pull request are in English.
- the_generated_instruction_files_match_their_source: `mf check agents` passes after `mf agents sync`.
- no_code_changes: the branch changes nothing outside `docs/` and the two generated instruction files.

## Reproducibility

```sh
git diff --name-only main... | grep -v '^docs/\|^CLAUDE.md$\|^AGENTS.md$'   # prints nothing
mf agents sync && mf check
```

No test and no seed: every criterion is over prose. The survey and the review describe `main` at `64a3333` (2026-10-01) and the draft as it stood that day; a statement in them is true of those and is not re-verified when either moves.

## Risks and Assumptions

- **Assumption: the institution accepts an article written with an AI assistant's help in reviewing it.** Whether that help must be declared is the authors' to check against the institution's rules; nothing here can.
- **Risk: the material goes stale.** The draft is edited daily, seven pull requests were open when this was written, and the records the survey cites keep moving. Both artifacts name what they describe so a reader can tell, and both are working material, not records the repository maintains.
- **Risk: the branch gate fails.** The branch this work was assigned to, `claude/hopeful-feynman-46ghac`, has a type that is not in `github.md`'s Type Table, so `mf check branch` fails on it. Renaming it to `docs/tcc-report` before a pull request is opened clears it.
- **Risk: this spec reaches `main` before the numbers below it.** 0093 to 0099 were reserved by the seven open pull requests when this was written, so 0100 is the next free number. `durable_numbering_test.dart` enforces contiguity on `main`, so this branch merges after those seven, or takes the next free number at the time it merges if one of them is closed instead.
- **What would invalidate this spec:** the institution requiring the article in English, or the authors deciding the review material does not belong in the repository.
