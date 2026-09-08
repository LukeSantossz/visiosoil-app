# SPEC: chore(standards): let a run verdict reach the repository after its spec has merged

## Problem

The Spec Gate refuses a branch that carries only `docs/ml/transported-population-sensitivity.md`, because the gate requires a branch touching a non-exempt path to **add** a spec and this document's spec — [SPEC 0057](0057-measure-whether-the-transported-population-changes-the-answer.md) — merged 47 hours before the run that produces the document could finish.

## Design Decision

**Add `docs/ml/*` to `checks.exempt_paths` in `.framework.toml`, and nothing else.**

**The trailing `*` is required and is not decoration.** `mf check spec` matches an
exempt pattern in two steps: `path.Match`, which cannot cross a `/`, and then a
prefix branch that fires only when the pattern ends in `*`, taking the pattern
minus that `*` as the prefix. `docs/ml/` therefore matches nothing, and
`docs/ml/**` leaves the literal prefix `docs/ml/*`, which no path begins with.
Neither wrong form reports an error — the gate simply keeps failing — so the form
is fixed here and the acceptance criteria below run the gate rather than trusting
the value.

The gate's model is one branch, one spec, and that model is right for code. It
breaks for exactly one class of artifact: a **run verdict**, whose content cannot
exist until after the spec that mandates it has merged and its code has run. The
precedent shows the seam. SPEC 0055's verdict rode in PR #228 beside its own spec
and code, because that probe took two hours and finished before the merge. SPEC
0057's could not: the pair took 46.5 hours of training, so PR #232 merged the
spec and the code, and the verdict had nowhere to land.

`docs/ml/` is the directory this repository already uses for exactly that class —
`capture-population-probe.md` and `transported-population-sensitivity.md` are both
verdicts of an approved spec, written from a committed machine-readable artifact
under `models/<version>/`. Nothing else lives there.

**The exemption is narrow on purpose.** It covers a directory, not a pattern, and
that directory holds only documents whose authority comes from a spec that has
already passed the Gate. A verdict is not unspecified work reaching `main` behind
the gate's back: it is the recorded output of work the Gate already approved, and
the spec that approved it names the file by path in its own Scope.

**What the exemption costs, stated rather than discovered.** A future document
placed under `docs/ml/` reaches `main` without a spec of its own. The mitigation
is that the directory's contents are verdicts, each traceable to the spec that
required it, and that `.framework.toml`'s own comment makes widening this list
visible in review — which is the design, not a side effect.

## Alternatives Considered

- **Write a spec whose only deliverable is the verdict document.** Rejected. It
  would be a spec that says "record what SPEC 0057 already said to record", and
  the Gate's three criteria would be satisfied by restating another spec's
  Acceptance Criteria. That is paperwork produced to satisfy a check rather than
  to design anything, which is the behaviour a gate people route around produces.
- **Hold the verdict out of the repository and keep it as a local artifact.**
  Rejected, and it contradicts an approved spec: SPEC 0057's Scope names
  `docs/ml/transported-population-sensitivity.md` as committed, and its
  acceptance criterion `the_verdict_is_committed_whichever_way_it_returns`
  requires it. A gate that forces a repository to break an approved spec is
  misconfigured for this case.
- **Exempt `docs/` wholesale.** Rejected. That would let a specification, an ADR,
  an architecture map or a standards document reach `main` with no spec, which is
  most of what the gate exists to catch here.
- **Add the verdict to the branch that carries a future spec.** Rejected. It ties
  an already-final number to whatever unrelated work happens to come next, and it
  delays a committed result for no reason connected to the result.
- **Amend SPEC 0057's branch and re-merge.** Rejected. PR #232 is merged; a
  merged spec is not reopened to carry an artifact that did not exist when it
  merged.

## Scope

- Includes:
  - `.framework.toml` — add `docs/ml/*` to `checks.exempt_paths`, with a comment
    naming why this directory and no other, and why the trailing `*` is required.
- Does NOT include:
  - Any other entry in `exempt_paths`.
  - Any change to the Spec Gate's rule, to `mf`, or to `.standards`.
  - The submodule bump, which is
    [SPEC 0059](0059-adopt-the-current-framework-standards.md).
  - Any change under `ml/` or `lib/`.
  - Re-opening or amending SPEC 0057.

## Acceptance Criteria

- the_gate_accepts_a_branch_carrying_only_a_run_verdict: `mf check spec` passes on
  a branch whose only change is a file under `docs/ml/`.
- the_gate_still_refuses_an_unspecified_change_elsewhere: `mf check spec` still
  fails on a branch that changes a non-exempt path outside `docs/ml/` and adds no
  spec — asserted by running it, so the exemption is shown to be narrow rather
  than assumed to be.
- the_exemption_names_its_reason_in_place: `.framework.toml` carries a comment
  saying that `docs/ml/` holds run verdicts whose spec has necessarily already
  merged, so a later reader need not reconstruct it.
- the_committed_verdict_is_reachable: the branch carrying
  `docs/ml/transported-population-sensitivity.md` passes `mf check` and can be
  pushed without `--no-verify`.

## Reproducibility

```sh
mf check spec
mf check
```

Run from the repository root with `mf` v0.8.0 or later on `PATH`.

## Risks and Assumptions

- **Risk: the exemption is read as a general licence for `docs/`.** It is not,
  and the criterion above proves the narrowness by running the gate against a
  non-exempt path rather than asserting it in prose.
- **Assumption: `docs/ml/` continues to hold only run verdicts.** It holds two
  today, both verdicts. A future document of another kind placed there would
  inherit an exemption it did not earn; the reviewer of that change is the
  control, and this spec records that as the residual risk rather than closing it.
- **What would invalidate this spec:** a change to how `mf check spec` reads
  `exempt_paths`, or a decision to keep run verdicts outside the repository.
