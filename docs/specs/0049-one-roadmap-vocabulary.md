# SPEC: docs(ml): make the implementation map's identifiers the only roadmap vocabulary

## Problem

Two identifier schemes name the same work — the implementation map's `A1`–`A5`, `B1`–`B3`, `C0`–`C4`, and the 2026-09-01 method study's `A0`, `A0b`, `A1`, `A4`, `A8`, `A9`, `A11` — and `A1` and `A4` mean different things in each, so an issue naming one cannot be resolved without knowing which document it came from.

## Design Decision

**`docs/architecture/ml-implementation-map.md` is the single roadmap vocabulary**, at the Developer's direction on 2026-09-02: it is the plan the project continues from. The method study's parallel names are retired, and the map gains a resolution table so a reader meeting `A8` or `A11` in an older issue or commit can find where that work now lives.

The reconciliation adds **as few identifiers as possible**, because a second vocabulary is what this spec exists to remove and a pile of new ones would be the same mistake in a new spelling. Two items are genuinely new; the rest fold into items that already own them:

| Study name | Work | Where it lives now |
|---|---|---|
| A8 | four-class list alignment | **Done** — SPEC 0046, #211 |
| A0 | recompute the canonical millimetres per pixel | **B2**, which owns the dataset version |
| A0b | capture-population predictability probe | **C0**, its inventory half |
| A1 | Python 3.12 environment with the pinned TensorFlow | **B1**, which owns how a training runs |
| A4 | scale-normalised greyscale patch pipeline (SPEC 0037) | **A6** — new; the map already said an item sat here |
| A9 | on-device patch-batch latency per encoder | **A7** — new |
| A11 | `spec.json` as the runtime contract | **A4**, which is that item |
| E0 | four-arm feasibility gate (SPEC 0044) | **C0**, its gate half |

**The map is corrected where it carries the order**, and only there. Its `## 1` section still describes five classes and a centred-square region of interest; its `## 6` execution order routes through weeks of collection that ADR 0016 and SPEC 0041 closed; and its 2026-08-25 banner names issue #197 and blockers #196 and #179 that are closed, and calls the label alignment "A4", which is the collision this spec removes. Each is corrected in place; the item bodies and their acceptance criteria are not touched, because they still hold.

**Three records SPEC 0048 missed are corrected here**, and the reason is worth recording rather than quietly fixing: that spec's criterion `no_live_record_states_five_model_classes` was verified by a grep, and the grep did not cover the phrasing "the five Embrapa textural groups". It passed while three live records still said it. Two are corrected — the map's `## 1` and `soil-classification.md`'s result contract. The third, `docs/ml/collection-protocol.md`, is **Withdrawn** and kept only because rules cited from elsewhere outlived it; its body is not edited, and its existing notice gains one line, which is the pattern that document already carries.

**Issue titles drop the study identifiers and get shorter.** The `type(scope): subject` form `github.md` mandates stays; what goes is the redundant detail a title does not need, and any embedded work-item name. The map item an issue belongs to is named once in its Context, where a reader who needs it will look.

## Alternatives Considered

- **Keep both schemes and add a glossary.** Rejected. A glossary makes two vocabularies readable; it does not make them one, and every future issue would still have to choose. The Developer's direction was that the map is where the project continues from.
- **Adopt the study's scheme and renumber the map.** Rejected on the same direction, and independently: the map's identifiers are cited from issue bodies, commit messages and ADRs going back months, and the study's exist in one artifact and six issues.
- **Renumber everything into a fresh scheme.** Rejected. It would invalidate every existing citation to buy tidiness, which is the trade the durable-number rule exists to refuse.
- **Give each folded item its own new identifier — B4, B5, C5.** Rejected. Four new names for work that three existing items already own is the complexity this spec is removing, differently spelled.
- **Put the work-item identifier in each issue title, as `[B2] chore(ml): …`.** Rejected. It is a second vocabulary in the one place every reader passes, it is not the `github.md` format, and it rots the moment an item is re-scoped.
- **Rewrite the map instead of correcting it in place.** Rejected. Its banners are how this document has recorded change since 2026-08-25, and a rewrite loses the record of what the plan was when each decision was taken.

## Scope

- Includes:
  - `docs/architecture/ml-implementation-map.md` — the resolution table; two new items `A6` and `A7`; corrections to `## 1`, `## 6` and the 2026-08-25 banner; a 2026-09-02 revision notice.
  - `docs/architecture/soil-classification.md` — the result contract's class count.
  - `docs/ml/collection-protocol.md` — one line added to its existing withdrawal notice. Its body is not edited.
  - The open issues carrying study identifiers: retitled, with the map item named in Context.
- Does NOT include:
  - Any item's acceptance criteria, dependencies or body text in the map.
  - Reopening a decision. Nothing here changes what is to be built or in what order; it changes what the work is called.
  - The premise-correction banners on the older issues, which are accurate.
  - Closing, opening or re-scoping any issue.
  - Any code.

## Acceptance Criteria

- the_map_resolves_every_retired_identifier: the map carries a table mapping each of A0, A0b, A8, A9, A11 and the study's A1 and A4 to the item that owns that work now.
- no_identifier_means_two_things: no name in the map's vocabulary is used for two different items, checked across the map and the open issues.
- the_map_states_four_model_classes: `## 1` says the model classifies four groups and names the archive's five as a separate list.
- the_execution_order_routes_through_no_collection: `## 6` describes an order that does not wait on dataset collection, which ADR 0016 and SPEC 0041 closed.
- closed_work_is_not_listed_as_a_blocker: the map names no closed issue as an open blocker or as a next item.
- no_live_record_states_five_model_classes: re-verified with a pattern that covers "five Embrapa textural groups", which the SPEC 0048 sweep did not.
- issue_titles_carry_no_study_identifier: no open issue title contains A0, A0b, A8, A9 or A11.

## Reproducibility

```sh
grep -rn "five Embrapa\|five textural\|five classes\|5 soil texture" --include=*.md . \
  | grep -v "^./docs/adr/\|^./docs/specs/\|^./.standards/"
grep -rn "A0b\|\bA8\b\|\bA9\b\|A11" docs/architecture/ml-implementation-map.md
gh issue list --state open --limit 40 --json number,title
mf check
```

No test and no seed: every criterion is over prose and issue metadata. This is deliberate and is the same call SPEC 0048 records — a repository-wide prose guard is the sweep SPEC 0043's Scope excludes, and it would fire on every archived record by design. The cost of that call is on the record: SPEC 0048's grep missed a phrasing, which is why this spec re-verifies with a wider pattern rather than trusting the previous pass.

## Risks and Assumptions

- **Assumption: the map's items still describe the work.** This spec renames and reorders around them; it does not re-scope them. Where an item's body has gone stale for a reason other than the class count or the collection premise, it stays stale and this spec does not claim otherwise.
- **Assumption: A6 and A7 are the right granularity.** The patch pipeline already has a spec of its own (SPEC 0037) and the latency budget has an issue, so both are items rather than criteria of an existing item. If either turns out to be one task inside another, merging it later costs a rename in one document.
- **Risk: older issues, commits and pull requests keep naming the retired identifiers.** They do, and they are not rewritten — a merged record says what it said. The resolution table is what makes them readable, and it is the reason the table is in the map rather than in this spec.
- **Risk: the grep-verified criteria fail the same way SPEC 0048's did.** A wider pattern is not a proof. What would close it properly is a guard that knows which records are live and which are archive, and no such distinction exists in the tree today; naming that here is more honest than claiming the second pass is complete.
- **What would invalidate this spec:** a decision to run the roadmap from the issue tracker rather than from the map, which would make the map a record rather than the plan and move the vocabulary with it.
