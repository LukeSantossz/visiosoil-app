# SPEC: feat(corpus): ask the generate prompt for what the class does not mean

## Problem

The 2026-09-11 agronomic review said a cell should be mostly **corrections of
wrong heuristics**: what the texture class does not mean, and what it changes
about reading a lab report. The generate prompt (version 5) names both in one
sentence, but it does not ask for the first. The B1' cell (#251) carries only
the lab-report kind, and the implementation map lists the fix as item 3
"Before B3".

The build cannot tell the two kinds apart either. A tip is a `text` and its
`citations`, so a cell with no correction at all looks the same as one with
three.

## Design Decision

**The prompt asks for at least one tip on what the class does not mean, and
each tip states its kind. When a grounded cell has no such tip, the build adds
one fixed limitation that says so.**

- **Prompt version 6.** The response shape gains `"kind"` on each tip, with two
  values:
  - `"nao_significa"`: a common reading of the class that the documents
    correct, for example a belief about what a clayey soil needs that the
    documents contradict.
  - `"leitura_do_laudo"`: what the class changes in reading a lab report.
  The prompt asks for at least one `"nao_significa"` tip when the documents
  support one, and keeps every other rule: abstain rather than write what the
  documents do not support.
- **The kind stays in the build.** `build_cell_payload` already rebuilds a tip
  from the fields the app's contract names, so `kind` never reaches
  `corpus.json`, and the app does not change.
- **A missing kind is a missing correction.** A tip without `kind`, or with a
  value other than the two, counts as `"leitura_do_laudo"`. The tip is not
  refused for it: grounding judges a claim, and the label is the model's own
  reading of it.
- **The limitation** is fixed, not written by the model: "Esta orientação não
  traz uma correção do que a classe de textura não significa." It is added
  after the coverage and age limitations, and only to a grounded cell. An
  abstained cell keeps `limitations: []`, as SPEC 0162 decided.
- **The run manifest records each tip's kind** beside its grounding, so a judge
  can see which tips the model presented as corrections.

## Alternatives Considered

- **Refuse a grounded cell with no correction, and retry.** Rejected: the
  sources may not hold one, and a retry bound would turn that into an
  abstention. A cell with only lab-report guidance is still worth reading, and
  the limitation tells the reader what is missing.
- **Change the prompt text only.** Rejected: nothing would show whether a cell
  carries a correction, which is what the review asked for.
- **Ship `kind` to the app.** Rejected for now: it changes the app's corpus
  contract (`test/fixtures/corpus/corpus.json`) for a distinction the app does
  not show.

## Scope

- Includes:
  - `corpus/prompts/generate.md` version 6, with `kind` and the request for a
    correction;
  - the derived limitation in `build_cell`, and each tip's kind in the run
    manifest's groundings;
  - the implementation map's "Before B3" entry.
- Does NOT include:
  - A producer for `evidenceStrength`. It is item 2 "Before B3", and out of
    scope by the Developer's decision of 2026-10-28.
  - Checking that a `"nao_significa"` tip really corrects a belief. The label
    is the model's, and judging it stays with a human reader.
  - Re-running any cell. The B3 run is its own step.

## Acceptance Criteria

- `the_generate_prompt_asks_for_what_the_class_does_not_mean`: the prompt names
  `nao_significa` and `leitura_do_laudo`, asks for at least one correction, and
  its version is `"6"`.
- `a_cell_with_a_correction_states_no_missing_correction`: a grounded cell with
  a `"nao_significa"` tip carries no correction limitation.
- `a_cell_without_a_correction_says_so`: a grounded cell whose tips are all
  `"leitura_do_laudo"`, or carry no kind, has the fixed sentence last in its
  limitations.
- `the_kind_does_not_reach_the_cell`: no tip in the cell has a `kind` key.
- `an_abstained_cell_states_no_missing_correction`: an abstained cell keeps
  `limitations: []`.
- `the_run_manifest_records_each_tips_kind`.
- Every existing corpus test passes (`python -m pytest corpus/tests -q`).

## Risks

- **The model can mislabel a tip.** A lab-report tip labelled
  `"nao_significa"` hides the limitation. The run manifest shows each label, so
  a reader can catch it, and B4's review is where it would have been caught.
- **A stricter prompt may abstain more.** Asking for a correction could push a
  7B model to write one the documents do not support, which grounding then
  rejects. The prompt says to write one only when the documents support it.
