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

### The sample identifier is the laboratory report reference

One physical soil sample has one granulometry report and one Embrapa textural
class. Its identifier is that report's reference, recorded by the collector, and
it is **globally unique across the dataset**.

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

| Column | Meaning |
|---|---|
| `sample_id` | The laboratory report reference. Globally unique |
| `texture_class` | One of the five Embrapa groups, exactly as `config.yaml` spells it |
| `image` | Path relative to the dataset version root |
| `site` | Collection site identifier |
| `device` | Capture device, make and model |
| `captured_at` | ISO 8601 date |
| `moisture` | One of `dry`, `moist`, `wet`, recorded at capture |
| `lab_report` | Reference to the granulometry result backing the class |

`moisture` is a three-value judgement rather than a measurement because a field
collector cannot measure water content, and a coarse honest value beats a
precise invented one. What matters is that the axis exists at all.

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

**Keep the coin, and place it outside the analysed square.** Its value is not
that it helps today — nothing measures it — but that collection is irreversible.
A coin present in every image leaves the door open to a future detector deriving
real millimetres per pixel, which is the only way to remove the distance
confound: the same soil at 15 cm and at 25 cm shows different apparent grain
size, and apparent grain size is the signal. A dataset collected without a coin
closes that door permanently for every image in it. The cost of keeping it is a
coin in the frame.

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
- manifest_rejects_an_unknown_moisture_value: anything outside
  `dry`, `moist`, `wet` is rejected.
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

- Assumption: laboratory report references exist and are available to the
  collector. This is question 2 in `ml-implementation-map.md` §7 and is
  unanswered. If they are not available, `sample_id` falls back to a collector-
  assigned identifier and the uniqueness rule still holds, but the link back to
  the granulometry that produced the label is lost, which weakens every later
  claim about label quality.
- Assumption: moisture can be recorded at collection time. If it cannot, the
  confound stays and no later work can remove it. Recorded here because the cost
  of skipping it is paid much later, by someone who cannot fix it.
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
