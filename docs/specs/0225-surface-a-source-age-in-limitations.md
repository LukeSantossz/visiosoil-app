# SPEC: feat(corpus): surface a source's age in a cell's limitations

## Problem

`research-agent.md` §8.3 says a source older than ten years may still carry a
claim when it is tier 1–3 and nothing newer contradicts it, and that "the age
is surfaced in `limitations`". Nothing in the build does that. The B1' cell
(#251) cites from three Embrapa sources, and one of them, Circular Técnica 32,
dates from 2005. Its age shows nowhere. §12.3 item 8 ("the limitations are the
real ones") failed for that reason, and the implementation map lists the fix as
the first item "Before B3".

The build cannot surface an age it does not know. A manifest source carries a
title, a publisher, a tier and pages, but no date. CT 32's year appears only
inside its `publisher` string ("2nd ed., 2005"), which is prose.

## Design Decision

**Each manifest source states the year it was published. When a cell keeps a
source more than ten years older than the build, the cell carries one fixed
sentence for that source, in the same derived-limitation path SPEC 0162 built.**

- **The manifest gains `year`**, an integer, required on every source. The year
  is the publication year of the edition the passage is read from, so CT 32's is
  2005. `SourceManifest.load` refuses an entry without one, or with one that is
  not an integer (a `bool` included), at load and before anything is fetched,
  as it refuses a malformed `pages`. The three entries take 2016, 2015 and
  2005, and `FetchedSource` carries the year through.
- **Age is measured against the build year**, the year of `accessed_at`, the
  instant the build already stamps on every source. A source is old when
  `build_year - year > 10`. Measuring against the build rather than the
  device's clock keeps a cell's text fixed for the snapshot it ships in.
- **The sentence** is fixed, not written by the model: "Uma das fontes
  consultadas é de {year}, há mais de dez anos." One sentence per old kept
  source, after the coverage limitations, in source order.
  - An old kept source gets its sentence even when a newer source covers the
    same topic, since what is surfaced is the age, not a gap.
  - The sentence states only the age. It does not say that nothing newer
    contradicts the source, because the build does not check that.
- **Only a grounded cell carries it.** An abstained cell keeps
  `limitations: []`, as SPEC 0162 decided.
- **The run manifest writes each source's `year`**, so a judge can see why the
  sentence was stated.
- **The app does not change.** `limitations` is already a list of strings, and
  the app renders it as written.

## Alternatives Considered

- **Parse the year out of `publisher`.** Rejected: it is prose, the format
  differs per source, and a parse that silently misses would drop the
  limitation it exists to state.
- **Put the year in the cell's `sources[]` and let the app phrase it.**
  Rejected for now: it changes the app's corpus contract
  (`test/fixtures/corpus/corpus.json`) for one sentence the build can state.
  It stays open if the app later shows dates beside citations.
- **Drop sources older than ten years.** Rejected: §8.3 makes recency a grading
  input, not a filter, and CT 32 is the cell's source for water and the
  subsoil's acidity.

## Scope

- Includes:
  - the manifest's `year`, and its validation in `src.sources`;
  - the derived age sentence in `build_cell`;
  - `year` in the run manifest;
  - the implementation map's "Before B3" entry, and the Developer's decision
    of 2026-10-28 to go on without the agronomist's judgement of #251's cell.
- Does NOT include:
  - The two other items "Before B3": a producer for `evidenceStrength`, and a
    generate prompt that asks for "what the class does not mean". Each needs
    its own spec.
  - Re-running the B1' probe. That run is #251's.
  - Detecting that something newer *contradicts* an old source. The sentence
    reports age, and contradiction stays with the human review of B4.

## Acceptance Criteria

- `a_manifest_source_without_a_year_is_refused`: `SourceManifest.load` raises
  on an entry with no `year`, or with one that is not an integer, `true`
  included.
- `the_manifest_states_each_sources_year`: the three entries carry 2016, 2015
  and 2005.
- `an_old_kept_source_is_surfaced_in_limitations`: a grounded cell built at
  2026 that keeps a 2005 source carries the age sentence naming 2005, after its
  coverage limitations.
- `a_recent_source_is_not_surfaced`: a source exactly ten years old, and a
  newer one, add no sentence.
- `an_unkept_old_source_is_not_surfaced`: an old source no topic found relevant
  adds no sentence.
- `an_abstained_cell_states_no_age`: an abstained cell keeps `limitations: []`.
- `the_run_manifest_writes_each_sources_year`.
- Every existing corpus test passes (`python -m pytest corpus/tests -q`).

## Risks

- **The ten-year line moves with the build year.** A 2016 source becomes "old"
  in a 2027 build. That is §8.3's rule, and the cell text changes only when the
  corpus is rebuilt.
- **The edition year is a judgement.** A reprint or second edition can differ
  from the year of its content. The manifest records the edition the passage is
  read from, and adding a source stays a reviewed act.
