# SPEC (full): feat(ml): define the dataset collection protocol, its manifest, and versioned splits

## Problem

The dataset does not exist. `ml/data/` holds only `splits/.gitkeep`, and
`ml/models/v1` and `v2` hold only `.gitkeep`; the 1418 images claimed in
`ml/README.md:29-35` are unverifiable. Everything downstream — the feasibility
probe E0, every experiment, every calibration — waits on images that a human has
to go and photograph.

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

Answered by the project owner on 2026-08-01. Every row constrains the rest of
this spec:

| Question | Answer | Consequence |
|---|---|---|
| Laboratory records | Granulometry spreadsheets exist per sample, but are not in a usable state | The identifier is collector-assigned; granulometry becomes optional |
| Moisture at capture | Cannot be recorded | Would be an unmeasurable confound — except for the next row |
| Where photographs are taken | **On a bench, after standard preparation** (air-dried, sieved) | Moisture becomes near-constant by construction, and **the domain gap replaces it as the dominant risk** |
| Paired in-situ photograph | Cost not yet evaluated | Optional column now; **a blocking decision before the first collection**, since it is irreversible per sample |
| Capture devices | One | The device axis does not exist in the dataset and does vary in deployment |
| Sample count | 150 or more, imbalanced | E0 is runnable; its floor is the smallest class, not the total |

Two of these change the programme rather than this spec.

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

### The sample identifier is assigned by the collector and is globally unique

One physical soil sample has one Embrapa textural class. Its identifier is a
code the collector assigns, and it is **globally unique across the dataset**.

The laboratory report reference would have been the better identifier, because
it makes every label traceable to the granulometry that produced it. Those
spreadsheets are not in a usable state, so this spec does not depend on them.
It keeps the door open instead: sand, silt and clay percentages are **optional
manifest columns**, filled when at hand and empty otherwise.

They are worth the empty columns for two reasons that need no spreadsheet
cleanup first. A label suspected of being wrong can only be checked against the
measurement that produced it — the Embrapa class *is* a reading of those
percentages on the textural triangle, not an independent judgement. And a sample
sitting near a boundary between two classes is genuinely ambiguous; those
samples will dominate the error, and separating "confused two adjacent classes
at a boundary" from "confused Arenosa with Muito Argilosa" is what makes a
cost-weighted evaluation possible. Neither is blocking. Neither is available
later if the columns do not exist.

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
| `setting` | yes | `bench` or `in_situ`. The axis the domain gap lives on |
| `site` | yes | Where the sample was taken, whatever the photograph's setting |
| `device` | yes | Capture device, make and model |
| `captured_at` | yes | ISO 8601 date |
| `sand_pct`, `silt_pct`, `clay_pct` | no | Granulometry backing the class, when available |
| `lab_report` | no | Reference into the laboratory spreadsheet, when one exists |
| `quality_flags`, and the seven metrics | written by admission | Recorded so recalibration can be recomputed without re-reading files |

**There is no `moisture` column**, and its absence is a decision rather than an
omission. It cannot be recorded, and bench preparation makes it near-constant
anyway, so a column would collect either nothing or a guess. If in-situ
photographs are later adopted, moisture returns as a live confound for those
rows specifically and the column comes back with them.

> **OPEN, 2026-08-06 — `setting`'s value set is not settled, and neither is the
> premise behind it.** This specification was written assuming two fixed worlds:
> a bench-prepared collection and an in-situ deployment. The project owner has
> since stated that the product is meant to support **both, switchable per case**,
> and that field use itself has more than one form — one candidate being a sample
> taken from 10 cm depth, spread over a sheet of paper.
>
> That is a third visual condition, not a variant of the other two: soil spread
> on white paper sits closer to the bench than to raw ground. So a two-value
> `bench | in_situ` enum is very likely too small. **No decision has been taken**
> and none is taken here. What is recorded is that the enum below, the capture
> protocol in this specification, and risk R7 in
> `docs/architecture/soil-classification.md` are all **contingent** on a capture-
> mode design that does not exist yet. The question is registered as an input in
> `docs/architecture/ml-implementation-map.md` §7 with what it would change.
>
> Reading the two values below as final is the error this note exists to prevent.

`setting` is required even though every row says `bench` today. It costs one
constant column now and it is the axis every later question about the domain gap
is asked along; adding it retroactively would mean editing history rather than
recording it.

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

### Splits stay class-stratified and group-aware; site and device are recorded, not yet enforced

The primary split keeps today's design: grouped by sample, stratified by class.
Site and device are recorded in the manifest so that a site-held-out evaluation
becomes possible, and the validator reports how each split is composed along
both axes.

Forcing a site-held-out split now is declined, and the reason is arithmetic. The
honest measurement of a field deployment is performance at a site the model has
never seen, but holding a site out costs all of its samples from training, and
nobody yet knows how many sites exist — question 1 in
`ml-implementation-map.md` §7. With two sites it is unaffordable; with ten it is
the right default. Recording the axis is irreversible if skipped and cheap if
kept; enforcing a policy over an unknown count would be guessing.

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
known route to normalising that. And if the paired in-situ photograph is
adopted, those images are field images with field distance variation, where the
coin matters exactly as much as it does in the app.

So the coin's value is now mostly on the deployment side and on the in-situ
rows, and only marginally on the bench rows. It stays in the protocol anyway,
because the cost is a coin in the frame and collection is irreversible: a bench
image taken without one can never be used to calibrate against a field image
taken with one.

Placing it **outside** the centred square is a correction this spec makes rather
than an inherited rule, and it matters for a reason neither document names: a
coin inside the ROI is a smooth metal disc, so it lowers Laplacian variance and
raises the specular fraction, which are two of the criteria SPEC 0030 blocks and
warns on. A protocol that mandated a coin inside the analysed region would have
the criteria penalising compliance with the protocol. A 4:3 frame leaves margin
on both sides of the largest centred square; the coin goes there.

**Replace the 70% fill with a rule a person can actually check.** The
`14-capture-guide.md` constraint that "any numeric rule the user cannot verify by
eye should not appear as a number" is right, and the fix is not to drop the rule
but to state it operationally: *the soil fills the centred square completely,
with no background, hand, tool, or container edge inside it*. That is verifiable
by looking, it is what the 70% figure was reaching for, and it is stricter where
it counts — inside the measured region — while silent about the margins, which
are not measured.

So, against that document's options: neither 2 nor 3 as written. Both rules
survive in collection, one relocated and one restated. Option 1 remains
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

Both are counts of *samples*, not photographs. Several photographs of one sample
are one group and add robustness, not statistical power.

**The available set is 150 or more but imbalanced, so the total is not the
binding number — the smallest class is.** A run with 100 Argilosa and 8 Siltosa
clears 150 and cannot support a five-way verdict, because the class most likely
to be confused is the one with almost no evidence. The inventory step therefore
reports the per-class count first, and E0's scope follows from it:

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
- **Enforce a site-held-out split now** — rejected on the arithmetic above, and
  revisited once the site count is known.
- **Drop the coin from collection** — rejected. Irreversible, and it forecloses
  the only known route to removing the distance confound.

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
- manifest_rejects_an_unknown_class: a `texture_class` not in `config.yaml` is
  rejected, naming the value and the accepted set.
- manifest_rejects_an_unknown_setting_value: anything outside `bench` and
  `in_situ` is rejected. `setting` replaces the moisture criterion an earlier
  draft of this specification carried: with collection on a bench after
  standard preparation, moisture cannot be recorded and there is no `moisture`
  column to validate, so a criterion rejecting `dry`, `moist` and `wet` tested a
  column the schema does not define. `setting` is the axis that actually carries
  the risk moisture used to stand for.
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
- protocol_document_states_the_fill_rule_operationally: it states the
  fill-the-square rule without a percentage.
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

- **Blocking, and irreversible per sample: the paired in-situ photograph.** Its
  cost is being evaluated. Until it is decided, every sample collected is a
  sample whose field appearance is permanently unrecorded. This spec can be
  implemented without the answer — the column is optional and the validator does
  not care — but **collection must not begin before it is answered**, because
  that is the only moment the option exists.
- Known limitation, not a risk to mitigate: **labels are not traceable to their
  granulometry** while the spreadsheets stay unusable. A wrong label is
  undetectable, so label noise cannot be bounded and cannot be ruled out as a
  ceiling on measured accuracy.
- Known limitation: **one capture device**. Any camera-specific regularity is a
  constant in training and a variable in deployment. Unmeasurable within this
  dataset by construction.
- Known limitation: **the domain gap between bench and field is unmeasured**,
  and unmeasurable without the paired in-situ photograph. Every accuracy figure
  this dataset produces describes prepared samples on a bench. Reporting one as
  field accuracy would be wrong, and the wording of any such report is part of
  the deliverable rather than an afterthought.
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
