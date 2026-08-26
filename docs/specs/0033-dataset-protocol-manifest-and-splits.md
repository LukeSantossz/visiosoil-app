# SPEC (full): feat(ml): define the dataset collection protocol, its manifest, and versioned splits


> **Revised 2026-08-25**, and this is the second revision — ADR 0014 forced the
> first, and its own retirement forces this one. See
> [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md).
>
> **The premise below is false: the dataset exists.** 221 photographs of 194
> samples were delivered on 2026-08-25. What this specification describes as a
> protocol for a collector to execute is, for the current version, a description
> of photographs already taken.
>
> - **The manifest is derived, not authored.** The laboratory number is in the
>   filename — `100262,1 (1).JPEG` is photograph 1 of sample `100262,1` — so
>   `sample_id`, `texture_class` and `image` come from a scan of the directory.
>   `site`, `device` and `captured_at` are absent for most rows and are optional
>   for this version.
> - **`setting` has one value, `dish`.** The `paper` condition describes the
>   application, not the dataset. `in_situ` stays rejected.
> - **A `disc_diameter_px` column is added**, measured per row, with the
>   validator refusing a missing or non-positive value and reporting the spread
>   per version. It is what makes the archive's 2.6× scale variation a recorded
>   quantity instead of an invisible one.
> - **The pairing rule does not apply.** It requires two photographs per sample,
>   one per condition; 177 of 194 samples have exactly one.
> - **The target counts are superseded by the measured counts.** 57 / 36 / 3 /
>   59 / 39. Siltosa is below the 30-sample floor this specification sets, which
>   selects the branch it already carries: E0 runs reduced, reports the exclusion,
>   and does not authorise Lane C on that basis.
>
> **What survives unchanged**, and is the reason this record still governs: the
> immutable-version rule, the group-aware split on `sample_id`, the rejection of
> granulometry and moisture columns, the digest tying a split to the manifest it
> was built from, and the admission gate deciding what enters a version.

## Problem

The dataset does not exist. `ml/data/` holds only `splits/.gitkeep`, and
`ml/models/v1` and `v2` hold only `.gitkeep`; the 1418 images claimed in
`ml/README.md:29-35` are unverifiable. Everything downstream — the feasibility
probe E0, every experiment, every calibration — waits on images that a human has
to go and photograph.

**What waits is the photography, not the samples.** Established 2026-08-11: the
project's own laboratory archives every analysed sample, so labelled material
already exists on a shelf. The dataset is that archive photographed, at the cost
of zero new analyses. This changes what is scarce — time at the rig rather than
laboratory turnaround — and it is why the cost question that governed earlier
drafts of this spec no longer gates anything.

What comes across from the archive is the sample, its class and its origin.
**The granulometry behind the class does not**, by the project owner's decision;
what that costs is in the Design Decisions below and in the Risks.

Nothing currently defines what a valid sample is. The pipeline infers a dataset
from a directory walk: `scan_dataset` lists image files under one folder per
class, and `_extract_sample_id` recovers a grouping key from the filename with a
regex matching `"name (N)"` (`ml/src/dataset.py`). Four consequences follow.

- **A sample carries no metadata.** There is nowhere to record the laboratory
  report the label came from, the site, the device, or the moisture state. The
  study names moisture as a confound that could be what a model learns instead
  of texture (`docs/architecture/soil-classification.md` §3), and it is
  **unrecoverable after collection** — nobody can look at a photograph a year
  later and say how wet that soil was.
- **Sample identity is a filename convention nobody wrote down.** Group-aware
  splitting is the only defence against a photograph of one physical sample
  landing in train while another photograph of the same sample lands in test.
  That defence currently rests on a regex guessing at camera naming. SPEC 0032
  left open whether sample identifiers are globally unique or per-class, because
  the answer is a collection decision and not a code decision.
- **A dataset has no version.** `splits.json` records a seed and split fractions
  but nothing that identifies which images it was computed over, so an
  experiment cannot state what it trained on.
- **Nothing applies the acceptance criteria.** SPEC 0030 delivers them in both
  languages precisely so that one set governs dataset admission and capture, per
  ADR 0009. No admission step exists, so the app will soon enforce a standard
  the dataset was never held to — the same subpopulation gap, reopened from the
  other side.

## Design Decisions

### What collection actually is, and what that costs

Answered by the project owner on 2026-08-01 and revised on 2026-08-11, when four
answers overturned premises this specification was built on. The protocol that
follows from the second round is ADR 0014. Every row constrains the rest of this
spec:

| Question | Answer | Consequence |
|---|---|---|
| Laboratory records | **The laboratory is the project's own**, and Embrapa is the classification reference rather than the source of the labels. **No granulometric data is linked into this process and the reports are not supplied to it** | The class name is the whole label. Granulometry columns are **absent**, and labels stay untraceable to the measurement behind them |
| Physical samples | **Archived** | The dataset is an archive photographed, not a collection campaign. **Zero new laboratory analyses** |
| Moisture at capture | Cannot be recorded | Would be an unmeasurable confound — except for the next row |
| Where photographs are taken | **On a bench rig at fixed distance**, on archive material (air-dried, sieved) | Moisture is near-constant by construction, and **the domain gap replaces it as the dominant risk** |
| Presentation | **90 mm Petri dish**, always the same; a second condition arranges the same soil as a disc of that size on paper, without the dish | The target is a centred circle of known diameter. See ADR 0014, and the amendment it forces on ADR 0009 |
| Field-fresh material | **Out of scope for this dataset.** In-situ deferred | The app must not treat fresh material as analysable |
| Sites | **Many, spread across Brazil**, and the origin is recoverable per sample | The site axis is populated and geographically varied, so a site-held-out evaluation is worth running rather than merely affordable |
| Sample state | **Already air-dried, sieved and classified** before this project touches them | Only the photography remains. The class is fixed before any image exists, so nothing in the labelling can be influenced by how a photograph looks |
| Capture devices | One | The device axis does not exist in the dataset and does vary in deployment |
| Sample count | ~150 per class on average, **asymmetric**; Siltosa is rare in the material itself | A uniform target is unattainable and is dropped |
| Photographs per sample | One per condition | The group is the sample; two conditions make a group of two |

Three of these change the programme rather than this spec.

**The archive removes cost as the binding constraint.** Earlier drafts, and the
study, treated collection as the expensive step that gated everything. With
labelled samples already on a shelf, the dataset is bounded by photography time.
Question 4 in
`ml-implementation-map.md` §7 — the cost of one laboratory analysis — therefore
stops blocking and becomes relevant only to future collection and to whether
active learning pays for itself.

**Bench preparation removes the moisture confound and creates a larger one.**
Air-dried, sieved soil on a bench is not what the app photographs. Sieving
removes the coarse fraction that distinguishes Arenosa; air-drying changes
colour substantially. ADR 0009 decided to close the collection-versus-deployment
gap by enforcing one capture protocol on both sides, which works when both sides
photograph the same subject with differing care. They do not. That claim is
narrowed in ADR 0009; the ROI and the criteria themselves are unaffected and
still worth having, because they still stop bad photographs entering either side.

**One device makes camera signature a learnable constant.** Any regularity in a
single camera's colour rendering and noise is present in every training image
and absent from the deployment population. Nothing in this spec can measure
that, because measuring it needs a second device. It is recorded as a known
limitation and belongs in any statement of what a resulting model has been shown
to do.

**The fixed rig makes scale a constant in the dataset and leaves it a variable
in deployment.** This is the sharpest form the skew takes, and it is new to this
revision. Textural class is a statement about particle size, and particle size in
an image means nothing without a known scale: coarse grains far away and fine
grains close produce the same pixels. A fixed rig photographing a 90 mm dish
gives every `dish` row the same millimetres per pixel. A handheld phone with no
dish and no reference object gives deployment none. The dataset is therefore at
its strongest on precisely the axis where the application is at its weakest, and
both sides look correct, which is what makes it dangerous. ADR 0014 lays out the
three candidate resolutions and deliberately settles none of them; the choice is
registered as an input in `ml-implementation-map.md` §7.

### The sample identifier is assigned by the collector and is globally unique

One physical soil sample has one Embrapa textural class. Its identifier is a
code the collector assigns, and it is **globally unique across the dataset**.

**The manifest carries no granulometry and no laboratory reference.** Decided by
the project owner on 2026-08-11, and **project-wide** rather than a schema
choice: this programme deals with textural classification and nothing else, so no
granulometric value or laboratory reference is used in any part of it. The class
name is the entire label, and the columns are not merely optional — they are
absent, so nothing collects them by halves.

The scope has a consequence past the schema: **no evaluation artefact may be
specified that needs the percentages.** The cost-weighted confusion matrix is not
deferred to a later spec; it is not buildable, and proposing one later would mean
reopening this decision rather than filling a gap.

This is recorded with its cost rather than as a neutral choice, because the cost
is real and lands on evaluation rather than on training:

- **Label noise cannot be bounded.** The Embrapa class is a reading of the
  percentages on the textural triangle. Without them a declared class cannot be
  checked against the measurement that produced it, so a mistyped or misread
  label is undetectable and stays in the training set. Whatever its rate, it is
  an unmeasurable ceiling on every accuracy figure this dataset produces.
- **Boundary samples are indistinguishable from model failures.** A sample at
  34 % clay and one at 36 %, either side of a 35 % line, look identical and carry
  different labels. Those samples will concentrate the error. Without the numbers
  nothing separates "the model was right to be uncertain here" from "the model
  was wrong", so a correct `ambiguous` verdict is counted as a failure.
- **Every error weighs the same.** A cost-weighted confusion matrix needs to know
  that Arenosa versus Muito Argilosa is a different mistake from Argilosa versus
  Muito Argilosa. Without the granulometry there is no basis for the weighting,
  so evaluation treats all confusions as equivalent, which is known to be false.
- **Coverage is a tally, not a map.** Per-class counts can say Siltosa is thin.
  Nothing can say which region of the textural triangle is empty, so any future
  collection is directed by class count alone.

None of these blocks the programme. All four belong in any statement of what a
resulting model has been shown to do.

This settles what SPEC 0032 deferred. Two consequences:

- The manifest validator rejects one identifier appearing under two classes.
  Under a globally unique scheme that situation is a labelling error, not a
  naming coincidence, and it must fail loudly rather than split independently.
- `_group_id` keeps its `class::sample` composition. It becomes redundant once
  identifiers are unique, and redundancy is the point: if the uniqueness rule is
  ever violated by an import that bypasses the validator, the prefix still stops
  one physical sample from spanning two splits. #25 reads the prefix as a defect;
  under this protocol it is a second lock on a door the manifest already closes.

### The manifest is the dataset, and the directory is derived from it

A CSV at the root of each dataset version, authored by the collector, is the
authoritative record. `scan_dataset`'s directory walk becomes a check that the
files on disk match the manifest, not the source of truth. An image with no row
is an error, and a row with no image is an error; neither is skipped.

CSV rather than JSON because the people producing it are field agronomists
working in a spreadsheet, not developers. The validator therefore has to be
explicit about the two ways a spreadsheet betrays this: a semicolon delimiter
and a non-UTF-8 encoding are both common in a pt-BR Excel export, and both must
produce a message naming the problem rather than a parse error naming a column.

Required columns:

| Column | Required | Meaning |
|---|---|---|
| `sample_id` | yes | Collector-assigned code. Globally unique across the dataset |
| `texture_class` | yes | One of the five Embrapa groups, exactly as `config.yaml` spells it |
| `image` | yes | Path relative to the dataset version root |
| `setting` | yes | `dish` or `paper`. The axis the domain gap lives on |
| `site` | yes | Origin of the sample — the property or region it was extracted from, not where the photograph was taken |
| `device` | yes | Capture device, make and model |
| `captured_at` | yes | ISO 8601 date |
| ~~`sand_pct`, `silt_pct`, `clay_pct`, `lab_report`~~ | **absent** | Removed 2026-08-11. No granulometric data is linked into the classification process and the reports are not supplied to it. The columns are absent rather than optional, so nothing collects them by halves and no code reads a value that may or may not be there |
| `quality_flags`, and the seven metrics | written by admission | Recorded so recalibration can be recomputed without re-reading files |

**There is no `moisture` column**, and its absence is a decision rather than an
omission. It cannot be recorded, and bench preparation makes it near-constant
anyway, so a column would collect either nothing or a guess. If in-situ
photographs are later adopted, moisture returns as a live confound for those
rows specifically and the column comes back with them.

**CLOSED, 2026-08-11.** This carried an open note from 2026-08-06 warning that
`bench | in_situ` was probably too small and that no capture-mode design existed.
ADR 0014 settles it, and not in the direction the note anticipated:

| Value | Presentation | Background |
|---|---|---|
| `dish` | Soil in a 90 mm Petri dish | Bench surface |
| `paper` | The same soil arranged as a disc of that size, no dish | White paper sheet |

Both are **air-dried, sieved archive material**. `paper` varies the background
and removes the container edge; it does not vary the physical state of the soil.

The note had anticipated `paper` as a third *field* condition — a sample taken
from 10 cm depth and spread on a sheet. That is not what it is, and the
distinction is load-bearing enough to state flatly: photographing archive
material on paper does **not** cover that field mode. Fresh soil is moist and
unsieved, holds aggregates, and moisture displaces its colour. The two are
different physical objects that happen to share a background.

`in_situ` is therefore **not** a value of this enum today. It is deferred with
the mode itself, and unlike the two values above it cannot reuse the archive: a
sample cannot be photographed undisturbed after it has been dried and sieved.
When in-situ capture is adopted, the value and the `moisture` column return
together, because moisture becomes a live confound for exactly those rows.

### A dataset version is an immutable directory

`ml/data/datasets/vN/`, containing `manifest.csv` and the images. Adding images
creates `vN+1`; it never mutates `vN`. Every experiment records the version it
used, and `splits.json` gains the version plus a content hash of the manifest,
so a split can be shown to belong to the data it claims.

This is the smallest thing that makes two experiments comparable. Without it,
"the model got worse" and "the dataset changed" are indistinguishable.

### Admission runs the SPEC 0030 criteria

An image whose verdict is `blocking` does not enter the dataset. `advisory`
enters and its flags are recorded in the manifest, because a marginal field
photograph is representative of field conditions and excluding it would curate
the dataset into exactly the subpopulation ADR 0009 warns about.

The thresholds are provisional, so admission records the measured metrics for
every image, not just the verdict. When the thresholds are recalibrated, the
admission decision can be recomputed from the recorded numbers without
re-reading a single file.

### Splits stay class-stratified and group-aware; the site axis is now populated

The primary split keeps today's design: grouped by sample, stratified by class.
The group is the physical sample, so both of its photographs — `dish` and
`paper` — land on the same side. Site and device are recorded, and the validator
reports how each split is composed along both axes.

**The reason for declining a site-held-out split has expired.** An earlier draft
declined it on arithmetic: holding a site out costs all of its samples from
training, and nobody knew how many sites existed. Its own words were that "with
two sites it is unaffordable; with ten it is the right default." The laboratory
serves many clients, so the archive spans many origins and the second case is
the one that holds.

This spec still does not *implement* the site-held-out split, because that is an
evaluation policy rather than a manifest concern and it belongs with C1. What
changes is the expectation: it moves from declined to the expected default, and
the inventory step reports the site distribution so the policy can be set from a
count rather than a guess. One condition has to be checked first, and it is not
guaranteed by the laboratory serving many clients: **the origin has to be
recoverable from the record per sample.** If it is not, the axis exists in the
material and not in the manifest, and nothing can split along it.

### The collection protocol, and the question the UI/UX terminal left open

`docs/design/ux-2026/14-capture-guide.md` §2 states that dropping the coin or
the 70% fill rule "requires the ML terminal's agreement, since it changes what
they collect", and offers no recommendation. This is that agreement.

**Keep the coin, and place it outside the analysed square.** The reason has
shifted now that bench capture is confirmed, and the shift is worth stating
because it changes who the rule is for.

A bench setup holds the camera at a fixed distance, so millimetres per pixel is
already near-constant across the dataset and a scale reference buys little
there. It buys a great deal everywhere else. In the app, distance varies with
whoever is holding the phone, and the same soil at 15 cm and at 25 cm shows
different apparent grain size — which is the signal. A detected coin is the only
known route to normalising that.

**Confirmed on 2026-08-11, and sharper than when written.** The project owner
settled that the application will not use a Petri dish, so deployment carries no
object of known size at all, while every `dish` row carries a 90 mm one. The
coin's value is entirely on the deployment side and essentially nil on the
dataset side. It stays in the protocol because collection is irreversible and the
cost is a coin in the frame — but it is no longer sufficient on its own, and ADR
0014 records the scale question as open rather than pretending the coin closes
it.

Placing it **outside** the centred square is a correction this spec makes rather
than an inherited rule, and it matters for a reason neither document names: a
coin inside the ROI is a smooth metal disc, so it lowers Laplacian variance and
raises the specular fraction, which are two of the criteria SPEC 0030 blocks and
warns on. A protocol that mandated a coin inside the analysed region would have
the criteria penalising compliance with the protocol. A 4:3 frame leaves margin
on both sides of the largest centred square; the coin goes there.

**The fill rule is restated, because the Petri dish contradicts it outright.**
This spec previously replaced the unverifiable 70 % figure with an operational
rule: *the soil fills the centred square completely, with no background, hand,
tool, or container edge inside it*. Under ADR 0014 the container edge **is** the
target boundary — the dish rim is what defines the disc — so the rule as written
forbids the protocol it is supposed to describe.

The `14-capture-guide.md` constraint it was honouring is still right: any numeric
rule a user cannot verify by eye should not appear as a number. The restatement
keeps that and fits a circular target:

> *The soil disc is centred and touches the guide circle. Nothing but the disc,
> its container, and the surface beneath them appears inside the guide — no hand,
> no tool, no second sample.*

Two things follow. The rim is admitted deliberately rather than tolerated: it is
constant, it is at the disc boundary, and it is the only object of known size in
the frame. And the rule is now stated over the **circle**, not the square, which
is consistent whichever ROI shape E1 selects — a rule phrased over the square
would have had to be rewritten again once that experiment reports.

For the `paper` condition, which has no dish, the disc is arranged **against a
90 mm template**. Without one its diameter is whatever the person judges by eye,
which would inject scale variation into the dataset that is neither constant nor
recorded — worse than either. The template costs a printed circle.

So, against that document's options: neither 2 nor 3 as written. Both rules
survive in collection, one relocated and one restated twice. Option 1 remains
available to the UI/UX terminal unilaterally, and the guide copy is theirs.

### Target sample counts

The floor is set by the split, not by a learning-curve estimate nobody can make
without data. `create_splits` requires at least 3 groups per class; with 15% val
and 15% test, a test set holding at least 10 samples of a class needs roughly 67
groups of that class.

- **E0 floor: 30 samples per class.** Enough for the feasibility probe to
  separate a real model from a label-shuffled control across several seeds, and
  small enough to be collectable before committing to the full programme. E0 is
  a go/no-go, not a performance measurement.
- **Programme target: 67 samples per class**, so each class holds at least 10 in
  the test set.

Both are counts of *samples*, not photographs. Under the protocol each sample
yields two photographs — one `dish`, one `paper` — and they are one group. They
add robustness, not statistical power.

**The target is ~150 samples per class on average, and the uniform target is
dropped.** Silty soils are genuinely uncommon across much of the Brazilian soil
population, so a Siltosa shortfall would be a property of the material rather
than of effort: no amount of photography reaches a number the archive does not
contain.

**The numbers themselves wait on the C0 inventory.** Population-level rarity
says Siltosa is expected to be thin; it does not say what the archive holds,
which nobody has counted. What is fixed now is the response — a declared
per-class target, class weighting, and a per-class rejection threshold for
Siltosa if it is thin but clears the E0 floor — rather than the target. Deciding
the response in advance is what stops a thin class being run five ways anyway and
read as if it meant something. Deciding the target in advance would be inventing
a measurement. ADR 0014 sets out the three inventory outcomes and what each
triggers.

**The total is not the binding number — the smallest class is.** A run with 100
Argilosa and 8 Siltosa clears 150 and cannot support a five-way verdict, because
the class most likely to be confused is the one with almost no evidence. The
inventory step therefore reports the per-class count first, and E0's scope
follows from it:

- every class at or above 30 — run E0 as specified, five ways;
- some classes below 30 — run E0 on the classes that clear the floor and report
  which were excluded and why. A verdict on three classes is a real verdict;
  a five-class verdict resting on eight Siltosa samples is not;
- fewer than two classes clear it — E0 cannot answer its question, and the
  finding is that collection has to precede feasibility rather than the reverse.

This is stated here rather than left to judgement at the time, because the
temptation when a class is thin is to run all five anyway and read the result as
if it meant something.

**A reduced-class E0 is exploratory and does not clear the product gate.** The
product contract is five-way, so a probe that excluded a class has said nothing
about that class and nothing about the five-way model — a three-class separation
can be driven entirely by the classes that were easy. Concretely: a reduced run
may authorise more collection, and it may kill the programme if even the
well-populated classes fail to separate from the shuffled control. It may not
authorise Lane C. Lane C stays blocked until every one of the five classes
clears the floor and E0 has run five ways.

The asymmetry is deliberate. A negative result on a subset is informative,
because failure on the easy classes bounds the whole; a positive result on a
subset is not, because success on the easy classes bounds nothing.

## Alternatives Considered

- **Keep the directory walk as the source of truth and add a sidecar metadata
  file** — rejected. Two sources that can disagree, with nothing forcing them to
  agree, is the arrangement that produced the six divergent label lists this
  project already has.
- **JSON or YAML manifest** — rejected for authoring. The collector is an
  agronomist with a spreadsheet. A generated JSON view of the manifest is fine
  and is not needed yet.
- **Derive `sample_id` from the filename, as today** — rejected. It makes the
  grouping key a property of how a camera happened to name a file. The regex
  already only handles `"name (N)"`, and #25 notes that other camera and
  duplicate-rename patterns bypass grouping entirely, which is silent leakage.
- **Record moisture as a measured percentage** — rejected. No field instrument
  is assumed, so the number would be invented. Three honest buckets are worth
  more than a fabricated decimal.
- **Exclude `advisory` images from the dataset** — rejected. It would curate the
  training distribution to be cleaner than the deployment distribution, which is
  the failure mode the whole acceptance-criteria strategy exists to prevent.
- **Mutable dataset directories with a changelog** — rejected. A changelog
  records intent; a hash records fact. The manifest hash in `splits.json` is what
  makes an experiment's claim about its data checkable.
- **Enforce a site-held-out split now** — rejected on the arithmetic above,
  pending the site count. **Revisited 2026-08-11**: the count is no longer
  unknown, so it moves from declined to the expected default, conditional on the
  origin being recoverable per sample from the laboratory record. Implementing it
  still belongs to C1, not here.
- **Drop the coin from collection** — rejected. Irreversible, and it forecloses
  the only known route to removing the distance confound. Reinforced 2026-08-11:
  the application will not carry a Petri dish, so it carries no object of known
  size at all.
- **Carry granulometry as optional columns** — rejected, and the reason changed
  twice. An earlier draft kept them optional against unusable spreadsheets, then
  made them required when the laboratory turned out to be the project's own. Both
  are superseded: the project owner decided on 2026-08-11 that no granulometric
  data is linked into this process. Optional would be the worst of the three
  anyway — it collects the data by halves, and a verification that runs on some
  rows verifies nothing about the dataset.
- **Photograph each sample several times per condition** — declined by the
  project owner. It would give real rather than synthetic variation in framing
  and lighting for the cost of rig time alone, with no effect on statistical
  power since the group is the sample. Recorded because it stays available if
  augmentation proves insufficient in E1.
- **A uniform 150-per-class target** — rejected. Siltosa cannot reach it at any
  effort, and a target that cannot be met stops being a target and becomes a
  misreport.

## Scope

- Includes:
  - `ml/src/manifest.py` — the schema, the loader, and the validator.
  - `ml/src/dataset.py` — build class images from the manifest; verify the
    directory matches it; record the dataset version and manifest hash in
    `splits.json`.
  - `ml/scripts/validate_dataset.py` — a CLI reporting every problem at once,
    plus the per-split composition by class, site, and device.
  - `ml/scripts/admit_images.py` — run the SPEC 0030 criteria over candidate
    images and write their metrics and verdicts into the manifest.
  - `ml/config.yaml` — the dataset version key.
  - `docs/ml/collection-protocol.md` — the field protocol a collector executes.
  - `ml/tests/` — tests for each criterion below.
- Does NOT include:
  - Collecting any images.
  - The in-app capture guide copy, its screen, or its behaviour — the UI/UX
    terminal owns those (`14-capture-guide.md`, their roadmap item 6).
  - Any change under `lib/`.
  - A site-held-out split implementation.
  - Recomputing admission when thresholds are recalibrated; this spec only makes
    it possible by recording the metrics.
  - Training, evaluation, export, or E0 itself.

## Acceptance Criteria

- manifest_requires_every_column: a manifest missing any required column is
  rejected, naming the missing columns.
- manifest_rejects_a_duplicate_sample_id_across_classes: the same `sample_id`
  under two `texture_class` values is rejected as a labelling error, naming the
  identifier and both classes.
- manifest_accepts_repeated_sample_id_within_one_class: several photographs of
  one sample share an identifier and form one group.
- manifest_requires_exactly_one_photograph_per_setting_per_sample: a sample with
  only a `dish` row, only a `paper` row, or two rows of the same `setting`, is
  reported, naming the sample and what it holds. The protocol pairs the two
  conditions on the same physical sample, and the pairing is the whole point —
  it is what lets the background effect be measured within-sample rather than
  across two populations. Without this check a manifest of `dish` rows alone
  passes every other criterion while silently being a one-condition dataset, and
  nothing downstream would notice until the comparison it was built for turned
  out to be impossible.
- manifest_rejects_an_unknown_class: a `texture_class` not in `config.yaml` is
  rejected, naming the value and the accepted set.
- manifest_rejects_an_unknown_setting_value: anything outside `dish` and `paper`
  is rejected, **including `in_situ`**, which an earlier draft of this
  specification accepted. Rejecting it is the point: the mode is deferred and no
  row may claim it until the data exists, since a silently accepted value is how
  an uncovered condition enters a dataset that reports itself as covering it.
  `setting` also replaces the moisture criterion an even earlier draft carried:
  moisture cannot be recorded and there is no `moisture` column to validate, so a
  criterion rejecting `dry`, `moist` and `wet` tested a column the schema does not
  define. `setting` is the axis that actually carries the risk moisture stood for.
- manifest_rejects_a_granulometry_column: a manifest carrying `sand_pct`,
  `silt_pct`, `clay_pct` or `lab_report` is rejected, naming the column. The
  decision of 2026-08-11 is that no granulometric data enters this process, and a
  schema that merely ignored an extra column would let it arrive quietly and then
  be read by something later. Rejecting is what makes the decision enforceable
  rather than aspirational.

  An earlier draft of this specification required these columns and added three
  criteria over them — component bounds, a sum tolerance, and verification of the
  declared class against the grouping thresholds. All three are withdrawn. They
  are recorded here rather than deleted because the review that produced them
  found real defects in them, and because if the decision is ever revisited the
  work of specifying them is not lost: the sum check must be paired with a
  component-range check, since `-10, 50, 60` sums to exactly 100, and the class
  check needs a declared threshold table with an explicit boundary policy, since
  a sample sitting on a line is precisely the ambiguous case that matters.
- manifest_reports_every_problem_at_once: a manifest with four distinct problems
  produces one failure naming all four.
- semicolon_delimited_manifest_is_diagnosed: a semicolon-separated file fails
  with a message naming the delimiter, not with a missing-column error.
- non_utf8_manifest_is_diagnosed: a Latin-1 encoded file fails with a message
  naming the encoding.
- directory_and_manifest_must_agree: an image on disk with no row, and a row
  with no image on disk, are each reported, naming the path.
- splits_record_the_dataset_version_and_manifest_hash: `splits.json` carries
  both, and loading a split whose hash does not match the current manifest fails.
- splits_group_by_sample_id: all photographs of one sample land in one split,
  asserted against a manifest where one sample has three photographs.
- split_composition_is_reported: the validator prints per-split counts by class,
  site, and device.
- admission_blocks_on_a_blocking_verdict: an image the SPEC 0030 criteria call
  `blocking` is not admitted, and the reason is recorded.
- admission_admits_and_flags_an_advisory_verdict: an `advisory` image is
  admitted with its failing criteria recorded.
- admission_records_metrics_for_every_image: every admitted image carries all
  seven measured metrics, so a later recalibration can be recomputed without
  re-reading files.
- protocol_document_states_the_coin_placement: `docs/ml/collection-protocol.md`
  states that the coin sits outside the centred square, with the reason.
- protocol_document_states_the_fill_rule_operationally: it states the fill rule
  over the guide circle, without a percentage, and admits the dish rim rather
  than forbidding a container edge.
- protocol_document_states_the_paper_template: it requires the 90 mm template for
  the `paper` condition, with the reason — an eyeballed disc injects scale
  variation that is neither constant nor recorded.
- existing_ml_tests_pass: the tests under `ml/tests/` pass, with any change to an
  existing test recorded and justified.
- analyze_clean_tests_green: `flutter analyze` reports no issues, `flutter test`
  passes, and `python -m pytest ml/tests/ -v` passes.

## Reproducibility

- Python with the pins in `ml/requirements.txt`; TensorFlow 2.21.0 and
  Keras 3.14.0 are installed in `ml/.venv`.
- The SPEC 0030 criteria used by admission are the Python reference
  implementation in `ml/src/image_quality.py`, held to the Dart implementation by
  `test/fixtures/image_quality/golden.json`.
- Every criterion is verified against synthetic manifests and generated images in
  temporary directories. No real dataset is required, which is the point: this
  spec has to be finishable before the data exists.
- Verify: `cd ml && python -m pytest tests/ -v`, then
  `python scripts/validate_dataset.py --version v1` against the fixture dataset.
- The manifest hash is over the file bytes, so it is stable across platforms
  provided the file is committed with consistent line endings.

## Risks and Assumptions

- **Dominant, and unresolved: scale.** The dataset has near-constant millimetres
  per pixel and the application has none, on a task whose signal is particle
  size. Both sides look correct, which is what makes it dangerous. ADR 0014 sets
  out the three candidate resolutions — a reference object in the app frame,
  scale-invariant training that deliberately discards absolute particle size, or
  enforced framing that constrains distance without measuring it — and settles
  none. Registered as an input in `ml-implementation-map.md` §7. **This does not
  block collection**, because every resolution is compatible with the archive
  being photographed under a fixed rig; it blocks any claim about deployment
  accuracy.
- **Resolved, 2026-08-11: the paired in-situ photograph.** An earlier draft
  called this blocking and irreversible per sample, on the reasoning that the
  moment to record a sample's field appearance passes once. That framing assumed
  a collection campaign. The dataset is an archive already dried and sieved, so
  the moment passed long before this spec existed and no decision now can recover
  it. In-situ is deferred as a separate mode with its own samples and its own
  cost, and the consequence is stated rather than mitigated: **no accuracy figure
  from this dataset describes fresh material.**
- **Known limitation, and it stands: labels are not traceable to their
  granulometry.** A wrong label is undetectable, so label noise cannot be bounded
  and cannot be ruled out as a ceiling on measured accuracy. This moved twice in
  one day and ended where it started: a draft resolved it when the laboratory
  turned out to be the project's own, and the project owner then decided that no
  granulometric data is linked into this process and the reports are not
  supplied. Access existing and access being used are different things, and the
  first draft conflated them.

  Three consequences travel with it, all landing on evaluation rather than
  training: boundary samples cannot be told apart from model failures, so a
  correct `ambiguous` verdict is counted as an error; a cost-weighted confusion
  matrix has no basis, so every confusion weighs the same, which is known to be
  false; and dataset coverage is a per-class tally rather than a map of the
  textural triangle.
- Known limitation: **the `paper` condition covers a background, not a field
  mode.** Anyone reading the two `setting` values as two use cases will over-read
  what the dataset supports. Both are dry, sieved archive material.
- Known limitation: **one capture device**. Any camera-specific regularity is a
  constant in training and a variable in deployment. Unmeasurable within this
  dataset by construction.
- Known limitation: **the domain gap between bench and field is unmeasured**,
  and stays unmeasured until a separate in-situ collection exists. It is
  **not** unmeasurable, which is what this bullet said before 2026-08-11 — that
  wording tied measurement to a paired photograph of the same sample, which the
  archive can never supply and which would therefore have made the deferred
  collection incapable of ever satisfying it. A separate in-situ set measures the
  gap between two populations rather than within a sample: weaker evidence, and
  available. Every accuracy figure this dataset produces describes prepared
  samples on a bench. Reporting one as field accuracy would be wrong, and the
  wording of any such report is part of the deliverable rather than an
  afterthought.
- Resolved by bench preparation: moisture. It cannot be recorded, but air-dried
  samples make it near-constant, so it stops being a confound for the bench rows.
  It returns in full for any in-situ row.
- Risk: the 30-per-class E0 floor may be too small for the probe to separate
  signal from noise, in which case E0 returns "inconclusive" rather than a
  verdict and the floor rises. That is a real possible outcome and it is cheaper
  than collecting 67 per class before knowing whether the premise holds at all.
- Risk: a protocol nobody follows is worse than no protocol, because it creates
  false confidence in the dataset's uniformity. Mitigated by admission being
  mechanical: what the criteria measure is what gets recorded, whatever the
  collector believed they did.
- Risk: this spec decides a collection rule — the coin — whose payoff depends on
  a detector that ADR 0009 defers and that may never be built. The cost of
  being wrong is a coin in the corner of every photograph. The cost of the
  opposite error is unrecoverable.
