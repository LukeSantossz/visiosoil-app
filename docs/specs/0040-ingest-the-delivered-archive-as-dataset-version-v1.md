# SPEC: chore(ml): ingest the delivered archive as dataset version v1 and split it by declared sample

## Problem

The 221 delivered photographs cannot enter the pipeline as they stand: 58 % of
them are in a container neither language decodes, the readable remainder is three
capture populations that differ in resolution and compression in a way that
correlates with the class, and the training path groups images by guessing at
their filenames rather than by what the collector declared.

### What the archive actually is

Measured on 2026-08-31 over `ml/data/archive/`, 221 files, every one of them
decodable once a HEIC plugin is present.

| Group | Files | Container | Pixels | EXIF | Luminance quantization table, first eight | Capture date |
|---|---|---|---|---|---|---|
| **C** | 129 `.HEIC` | HEIF | 3024×4032 (128), 4032×3024 (1) | iPhone 11, GPS | — | 2023-10-04, 2023-10-05 |
| **A** | 44 `.JPEG` | JPEG | 1536×2048 (41), 2048×1536 (3) | iPhone 11, GPS | 2, 2, 2, 3, 4, 5, 7, 8 | 2023-11-22 |
| **B** | 48 `.jpeg` | JPEG | 899×1599 (25), 900×1600 (13), 1599×899 (6), 720×1280 (4) | **none** | **6, 6, 6, 7, 10, 15, 22, 34** | **unknown** |

Four consequences follow, and each is a defect this spec closes.

**1. Group C is invisible to both pipelines.** `IMAGE_SUFFIXES` in
`ml/src/manifest.py:78` admits `.jpg .jpeg .png .bmp .webp`. `.heic` is not
there, `tf.io.decode_image` does not decode it, and neither does the Dart `image`
package. Every downstream step therefore operates on the 42 % that happens to be
readable, and the format mix differs sharply by class, so the silent subset is
also a reshaped class balance (#196).

**2. Group B is a second generation at reduced resolution.** All 48 files share
one luminance quantization table whose high-frequency entries are three to four
times coarser than group A's — 15, 22, 34 against 5, 7, 8 — their EXIF is
stripped entirely, and they carry roughly 2.2 times fewer pixels across four
different frame sizes. One re-encoder, one transport. The coefficients quantized
away are the high-frequency band, which on this task is not detail but **the
signal**: textural class is carried by grain and aggregate structure.

**3. The three groups are one camera, not three.** Their long-side ratios are
1.00 : 0.508 : 0.397, a spread of 2.52, which is the 2.6× scale spread
[ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
measured from the dish rim and attributed to "at least two cameras". Every group
that carries EXIF carries the same one, an iPhone 11. The spread is three export
and transport paths out of one device, not three devices, and ADR 0016 is amended
by this change rather than left to be read as it stands.

**4. Group B's population is confounded with the label.** Seventeen of its 25
sample groups are Argilosa: `P(Argilosa | group B) = 0.68` against a base rate of
`0.25`. A model that reads compression artefacts is handed most of one class for
free, and E0's four arms as scoped in #183 do not test for it, so the gate could
pass on the confound rather than on the hypothesis.

### What the splits currently do

`ml/src/train.py:143-150` calls `scan_dataset` over the class folders and then
`create_splits` **without `sample_ids`**, so `_sample_id_of`
(`ml/src/dataset.py:150`) falls back to `_extract_sample_id`'s filename regex.
That regex happens to match this archive, which is the worst case: it works, so
nothing reports the omission, and the group that keeps one physical sample out of
two splits is a guess rather than a declaration (#178).

### The sample count in ADR 0016 does not reproduce, for a reason that matters

ADR 0016 records 194 samples and states that "the laboratory number is in the
filename, so grouping needs no extra record". **The second claim is true of 92
photographs and false of 129.** The whole HEIC session is named `IMG_8202`,
`IMG_8204`, and so on: a camera's own counter, which identifies the photograph
and says nothing about the soil. No laboratory number, and no label card in the
frame either — group B is the only population that photographed one.

Taking a sample identity from such a name makes **every shot its own sample**.
Two photographs of one dish then satisfy the group-aware split while sitting in
different splits, and the model scores on soil it was trained on. That is the
exact failure group-aware splitting exists to prevent, over 58 % of the archive,
and nothing in the pipeline would report it.

The identity is recoverable from the capture clock. Over the 129 HEIC files:

| Gap between consecutive photographs | Count |
|---|---|
| 2 to 23 seconds | 60 |
| 24 to 99 seconds | **0** |
| 100 seconds or more | 68 |

The band is empty, which is what a real threshold looks like. A cut anywhere
between 30 and 60 seconds produces the same **63 groups**, and **no group spans
two texture classes** — an independent check the grouping had no way to satisfy
by accident. D4 takes 60 seconds, in the middle of the empty band rather than at
its edge.

The corrected inventory, and it is smaller than every figure previously recorded:

| Class | Group A | Group B | Group C | Samples | Images | Identity declared | Identity derived |
|---|---|---|---|---|---|---|---|
| Arenosa | 5 | 6 | 15 | 26 | 68 | 11 | 15 |
| Media | 3 | 2 | 17 | 22 | 42 | 5 | 17 |
| Siltosa | 3 | 0 | 0 | 3 | 6 | 3 | 0 |
| Argilosa | 3 | 17 | 13 | 33 | 63 | 20 | 13 |
| Muito Argilosa | 3 | 0 | 18 | 21 | 42 | 3 | 18 |
| **Total** | **17** | **25** | **63** | **105** | **221** | **42** | **63** |

**105 sample groups, not 194 and not 171.** The intermediate 171 is what an
earlier draft of this spec carried, before the group C naming was looked at; it
counted each HEIC as its own sample and reproduced ADR 0016's per-class figures
once group B's `X` / `X (2)` pairs were also split apart.

This has a consequence outside this spec's scope and it is stated here because
it is this measurement that produces it: **ADR 0016 excluded Siltosa for holding
fewer than 30 samples, and under the corrected count three of the four remaining
classes are also below that floor** — Arenosa 26, Media 22, Muito Argilosa 21,
with only Argilosa at 33. Holding group B to training, 77 groups are splittable
across the four classes and a 0.15 test fraction leaves two to three sample
groups of each class in the test set. Whether a floor of 30 survives, and
whether a single three-way split is the right instrument at this size, are
decisions for the record that owns them. This spec ingests the archive
correctly and reports what is in it.

## Design Decisions

### D1. The archive is source material; ingestion writes the dataset version

`ml/data/archive/` holds the delivery exactly as it was handed over — original
filenames, original containers, English class folders — and nothing in the
pipeline reads it except one script. `ml/scripts/ingest_archive.py` reads it and
writes `ml/data/datasets/v1/`, which is the immutable version every experiment
names, per [SPEC 0033](0033-dataset-protocol-manifest-and-splits.md).

`data.raw_dir` is **not** pointed at the archive. It addresses the legacy
folder-scan route that D6 retires from the training path, and aiming it at a tree
whose folder names are English would make `scan_dataset` fail on a class folder
it cannot find — an error message describing the wrong problem.

### D2. HEIC converts to PNG; JPEG is copied byte for byte

HEIC is already lossy, so a JPEG re-encode would add a second generation on
exactly the band that carries the signal, and PNG preserves the decoded pixels
exactly. Groups A and B are copied unchanged rather than converted: they are
already JPEG, so rewriting them as PNG would freeze their existing artefacts
without removing any of them, while tripling the bytes.

### D3. The class comes from the folder by an explicit name map, never by its number

```
1 Sandy → Arenosa    2 Silty → Siltosa    3 Medium → Media
4 Clayey → Argilosa  5 Very Clayey → Muito Argilosa
```

The folder numbers run in granulometric order. `ml/config.yaml:5-10` lists the
classes in a different order — Arenosa, Media, Siltosa, Muito Argilosa, Argilosa
— so any mapping that pairs folder index to class index mislabels four of the
five classes and does so silently. The per-class file counts corroborate the map
independently: 68 / 6 / 42 / 63 / 42 reproduce #196's HEIC-versus-JPEG table row
for row, which no wrong pairing does.

### D4. The sample identity is read from the filename when there is one and from the capture burst when there is not, and which of the two is recorded

Ingestion resolves the sample group once, writes it into the manifest's
`sample_id`, and `train.py` passes that column into `create_splits`. The group
stops being a property of the filename at split time and becomes a property of
the record.

**A filename that declares a laboratory number is taken at its word.** Two
lab-numbered photographs seconds apart stay two samples; the clock never
overrides a declaration.

**A camera-default filename declares nothing, and the burst decides.** Files
matching `IMG_####` and its siblings are ordered by capture time and cut wherever
the gap exceeds 60 seconds, and each burst becomes one sample identified as
`burst-YYYYMMDD-HHMMSS` from its first photograph. Two faults are refusals rather
than warnings, because both would produce a grouping that looks fine and leaks:
a camera-named photograph carrying **no capture time** cannot be placed in a
burst, and a burst **spanning two texture classes** means the threshold does not
separate what it is assumed to separate.

**Which way each identity was arrived at is a manifest column**, `sample_id_source`,
with values `filename` and `capture-burst`. A derived identity is weaker evidence
than a declared one, and every figure that rests on grouping — the leakage
guarantee above all — has to be readable as resting on 63 inferences out of 105.

Where a *declared* name is ambiguous it goes the conservative way. In groups A
and C a sample appears as `X (1)` through `X (4)`; in group B it appears as `X`
plus `X (2)`, the shape a filesystem copy collision also produces. The two files
are not byte-identical, so they are two photographs; whether they are two
photographs of one sample or of two is not recoverable. Treating them as one
cannot leak and treating them as two can, so they are one.

The lab number alone is **not** the group. Lab `116520` appears as `116520_1`
under Media and `116520_2` under Argilosa, so the number identifies a batch and
the suffix identifies the soil; grouping by the number would merge different
textures into one unit and collapse the archive to 29 groups.

### D5. Columns the archive cannot supply are declared unknown, never guessed

Three required columns have no honest source, and each gets a stated value rather
than a plausible one.

- **`site` is `unknown` for every row.** Groups A and C carry GPS, and all of it
  falls inside a fifty-metre circle at (−22.11, −50.197): one location, which is
  the bench where the photographs were taken, not where any soil was sampled.
  Writing it into `site` would assert that 173 samples share an origin they do
  not share. The archive also spans only 24 lab batch numbers, so site diversity
  is low regardless, and that is a limitation to report rather than to disguise.
- **`device` is `iphone-11` for groups A and C**, read from EXIF, and `unknown`
  for group B, whose EXIF was stripped.
- **`captured_at` is `2023-10-04`, `2023-10-05` or `2023-11-22`** from EXIF for
  groups A and C, and `unknown` for group B. Group B cannot inherit a date: no
  lab batch number appears in more than one group, so B is disjoint material
  rather than a re-transport of a dated session, and its filesystem timestamps
  are a single bulk-copy instant in 2024. `manifest.py` currently requires a
  strict ISO date in this column, so it gains one permitted literal, `unknown`,
  and nothing else relaxes.

### D6. Provenance is recorded as data, and group B is kept out of validation and test

Four new manifest columns make the confound visible: `source_format`
(`heic`, `jpeg`), `source_group` (`A`, `B`, `C`), `source_width`,
`source_height`. They are recorded the way `device` and `site` are — carried
along so evaluation can report against them — and not held out.

Group B additionally carries a split restriction: **it may appear in train, and
never in validation or test.** Its degradation is not representative of
deployment, because the application captures directly from the camera and never
receives a transported copy, and leaving it in the test set would let a model
that reads compression artefacts inflate the very score E0 exists to judge.
Excluding it entirely was rejected for the reason in the Alternatives; keeping it
where it can only help the model learn, and never where it can flatter the
measurement, is the position that costs nothing real.

### D7. A `.heic` file offered to admission is refused by name

`.heic` stays out of `IMAGE_SUFFIXES`, and `admit_images.py` gains an explicit
refusal naming the conversion step. A future drop of HEIC files then stops with
an instruction instead of skipping 58 % of itself in silence, which is the
failure this whole spec exists to close.

## Alternatives Considered

- **Exclude group B from the dataset entirely.** It removes the confound at the
  root and lets the canonical scale be set by group A rather than by the coarsest
  transported frame, which would keep roughly twice the linear resolution across
  the whole set. Rejected on arithmetic: Argilosa falls from 43 sample groups to
  26, below ADR 0016's floor of 30, so a second class would leave the first model
  and it would classify three ways. Paying a measurable confound is worse than
  losing a class only if the confound cannot be measured, and D6 measures it.
- **Keep group B everywhere, including validation and test, and rely on the
  canonical scale normalisation to erase the difference.** Downsampling every
  image to a common millimetres-per-pixel does attenuate high-frequency JPEG
  artefacts, so the argument is not empty. Rejected because "attenuates" is not
  "removes", and the one measurement whose integrity matters most is the gate's.
  An assumption that cheapens the gate is the assumption to refuse.
- **Convert everything, groups A and B included, to PNG for uniformity.**
  Rejected: it changes no pixel that is already lost, removes no artefact, and
  triples the storage of 92 files to make a directory listing look consistent.
- **Fabricate `captured_at` for group B from group A's session date.** Rejected:
  the groups share no lab batch number, so there is no evidence they were shot on
  the same day, and a fabricated date is indistinguishable from a measured one
  once it is in the column.
- **Point `data.raw_dir` at the archive and keep the folder-scan route.**
  Rejected: it keeps the filename-guessing group that #178 exists to remove, and
  it cannot carry provenance, `device`, or a declared `sample_id` at all, because
  the folder-scan route has nowhere to put them.
- **Group by lab batch number rather than by sample.** Rejected on evidence: lab
  `116520` spans two texture classes, so the number is a campaign and grouping by
  it would both merge distinct soils and collapse the archive to 29 groups, which
  no stratified three-way split survives.
- **Treat each camera-named photograph as its own sample.** The status quo, and
  what an earlier draft of this spec specified without noticing. Rejected: it is
  an assumption about 129 files with no evidence behind it, and when it is wrong
  the failure is silent and flattering — two shots of one dish in train and test,
  a score inflated by memorisation, and a gate that passes for the wrong reason.
- **Ask the laboratory for the `IMG_####` to sample-number mapping.** Not
  rejected, and better than what is specified here: it would be declared rather
  than inferred, and verifiable. It is not taken now because it depends on
  someone outside this workstream holding that record, and it would block E0
  indefinitely on an unknown. If the mapping ever arrives it supersedes D4's
  derived identities, and `sample_id_source` is what makes that substitution
  legible.
- **Hold group C out of validation and test as well, as D6 does for group B.**
  It makes the grouping question moot: an unsplittable population cannot leak
  across a split it never enters. Rejected on arithmetic — group A is 17 sample
  groups, so the entire evaluation would rest on three to five samples per class,
  which is a smaller and more fragile measurement than the one the burst grouping
  buys.

## Scope

- **Includes:** `ml/scripts/ingest_archive.py`; HEIC→PNG conversion of the 129
  group C files; the class name map; sample identity from the filename or the
  capture burst, with `sample_id_source` recording which; resumable ingestion
  (`--skip-existing`, verified by comparison rather than by name, because one run
  writes 1.3 GB); the manifest written
  to `ml/data/datasets/v1/manifest.csv` with the four provenance columns; the
  `unknown` literal for `captured_at` and `device` in `manifest.py`; the group B
  validation and test restriction in `create_splits`; `train.py` reading the
  manifest and passing `sample_ids`; the `.heic` refusal in admission;
  `pillow-heif` in `ml/requirements.txt`; the amendment to ADR 0016; the
  relaxation of the setting-pairing check from mandatory pairing to uniform
  coverage, without which the single-condition archive reports all 105 of its
  samples as broken; tests for each acceptance criterion below.
- **Does NOT include:** anti-aliasing the downsample paths (#180); BatchNorm
  inference mode in phase 2 (#179); running E0 (#197) or adding its provenance
  control arm (#183); the scale reader and patch grid (SPEC 0037); recomputing
  the canonical millimetres-per-pixel, which SPEC 0037 owns and which this change
  unblocks by making 100 % of the archive readable; any change to
  `inference_service.dart`; any Flutter-side change at all. It also does **not**
  revisit ADR 0016's floor of 30 samples per class, nor the choice of a single
  three-way split over cross-validation, both of which the corrected inventory
  calls into question and neither of which this record owns.

## Acceptance Criteria

1. `ingest_archive_converts_every_heic_file_to_png` — all 129 group C files land
   in the version directory as PNG, and the count is asserted, not inferred.
2. `ingest_archive_copies_jpeg_files_unchanged` — the bytes of an ingested group
   A or B file are identical to the archive's.
3. `ingest_archive_maps_folder_names_to_configured_classes` — the five English
   folder names produce exactly the class strings in `ml/config.yaml`, and a
   folder name outside the map is refused rather than skipped.
4. `ingest_archive_refuses_index_based_class_mapping` — a test asserts the map is
   by name, by checking that `4 Clayey` yields `Argilosa` and not the fourth
   entry of the configured class list, `Muito Argilosa`.
5. `manifest_declares_one_sample_group_for_a_bare_and_parenthesised_pair` —
   `X.jpeg` and `X (2).jpeg` receive one `sample_id`.
5a. `camera_named_photographs_in_one_burst_share_a_sample_id`, and a gap beyond
   the threshold starts a new one. A burst is a chain of gaps, not a window.
5b. `a_filename_that_declares_a_sample_is_never_regrouped_by_time` — two
   lab-numbered photographs one second apart stay two samples.
5c. `a_camera_named_photograph_without_a_capture_time_is_refused`, and so is
   `a_burst_spanning_two_classes`. Both are refusals, never warnings.
5d. `manifest_records_how_each_sample_id_was_arrived_at` — `filename` or
   `capture-burst` per row, and a third value is refused.
6. `manifest_records_unknown_rather_than_a_guess` — every group B row carries
   `captured_at=unknown` and `device=unknown`, and every row of every group
   carries `site=unknown`.
7. `manifest_rejects_a_date_that_is_neither_iso_nor_unknown` — the relaxation
   admits the literal `unknown` and nothing else.
8. `manifest_records_source_format_group_and_dimensions_per_row` — the four
   provenance columns are present and the per-class group mix is reported.
9. `training_decoder_opens_every_file_the_manifest_names` — run over the real
   version directory, not a fixture.
10. `create_splits_places_no_group_b_sample_in_val_or_test` — over the real
    manifest.
11. `create_splits_keeps_every_image_of_one_sample_in_one_split` — the existing
    group-aware guarantee, asserted against declared ids rather than the regex.
12. `train_passes_manifest_sample_ids_into_create_splits` — the fallback path is
    not taken, asserted by passing a manifest whose declared ids disagree with
    the filenames and observing the declared ones win.
13. `admit_images_refuses_a_heic_file_by_name` — the message names the conversion
    step and the exit code is non-zero.
14. `ingested_version_reports_105_sample_groups_and_221_images`, with the
    per-class table, so a later change in the archive is visible rather than
    absorbed. Two companion assertions cover the split of identities — 63
    derived, 42 declared, none both — and the 25 train-only groups.
15. `skip_existing_reuses_a_file_that_is_already_this_photograph`, verified by
    comparing bytes for a copy and dimensions for a conversion, and
    `skip_existing_rewrites_a_file_whose_bytes_do_not_match`.

## Reproducibility

```sh
cd ml
python -m pip install -r requirements.txt          # now includes pillow-heif
python scripts/ingest_archive.py --source data/archive --version v1
python scripts/validate_dataset.py --version v1
python -m pytest tests/
```

Ingestion is deterministic: no sampling, no randomness, and the file order is
sorted, so two runs over one archive produce byte-identical manifests. The split
seed stays `data.seed = 42` from `ml/config.yaml`. Measured with Python 3.14.3,
Pillow 12.2.0, pillow-heif 1.6.0; the CI job runs Python 3.12, and the acceptance
criteria are asserted on both.

## Risks and Assumptions

- **Assumption:** the folder a photograph sits in is its class, and there is no
  other label. Carried over from ADR 0016 and unchanged here; label noise stays
  unbounded and unverifiable.
- **Assumption, and the load-bearing one:** a burst of photographs taken within
  60 seconds of each other is one physical sample. Supported by an empty gap band
  between 24 and 99 seconds and by no burst spanning two classes, and falsifiable
  by the laboratory's own mapping if it exists. If it is wrong in the direction
  of merging two samples, 63 groups are coarser than the truth and nothing leaks;
  if it is wrong in the direction of splitting one sample across two bursts, the
  leakage it was adopted to prevent returns for those photographs.
- **Assumption:** `X` and `X (2)` in group B are one physical sample. If they are
  two, the cost is a slightly coarser grouping and 23 fewer groups than the
  archive really holds, which loses a little statistical power and leaks nothing.
- **Assumption:** group B's degradation is not representative of what the
  application will capture. It rests on the application capturing directly from
  the camera, which SPEC 0037 requires; if a gallery import were ever added, D6's
  restriction would need revisiting and ADR 0016's field-fresh limitation would
  not be the only one on that list.
- **Risk, and it is larger than it was:** with the corrected grouping and group B
  held to training, the four classes hold 20, 20, 16 and 21 splittable sample
  groups. A 0.15 test fraction is two to three groups per class, so the test set
  is about twelve samples in total and **no accuracy figure computed on it will
  have a usable interval**. ADR 0016 already recorded that no per-class figure
  was supportable at 5 to 9 per class; the real number is half that. This does
  not change what ingestion should do, and it does change what the next
  experiment can claim, which is why it is written here rather than discovered
  later.
- **Risk:** `pillow-heif` is a new native dependency in CI. It publishes wheels
  for CPython 3.12 and 3.14 on Linux, macOS and Windows, so no build toolchain is
  required; a wheel that ever stopped being published would break ingestion, not
  training, because conversion happens once and its output is what the version
  holds.
- **What would invalidate this spec:** evidence that group B is not a transported
  copy but a different camera, which would make its resolution a genuine capture
  condition rather than damage and remove the reason to keep it out of test; or a
  re-delivery of the archive in its original containers, which would make the
  whole of group B's handling moot.
