# The dataset is the archive already photographed in Petri dishes: 194 samples with scale recoverable from the dish rim, and Siltosa is out of the first model

VisioSoil trains on 221 photographs of 194 archived soil samples that already
exist, taken top-down of soil in a Petri dish against a pale background. The
dish rim is a circle of known diameter, so millimetres per pixel is recovered
per image rather than assumed constant. Siltosa holds three samples and is
excluded from the first model, which classifies four Embrapa textural groups.

This record **replaces [ADR 0014](0014-petri-dish-capture-protocol-and-the-unresolved-scale-reference.md)**,
which is Retired in place. ADR 0014 described a collection that was going to
happen on a fixed rig; the photographs turned out to already exist, and to
differ from that description on every axis it fixed.

## Status

Accepted 2026-08-25, from an audit of the delivered image set against the
records that described it.

**Amended 2026-09-01**, while implementing
[SPEC 0040](../specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md).
The decisions this record takes — the archive is the dataset, scale comes from
the dish rim, Siltosa is out of the first model — all stand. Three of its
measurements do not, and the title's `194 samples` is the first of them. The
title and body are left as they were approved; the corrections are here.

- **The archive holds 105 sample groups, not 194.** Per class: Arenosa 26,
  Media 22, Siltosa 3, Argilosa 33, Muito Argilosa 21, over 221 photographs.
- **"The laboratory number is in the filename, so grouping needs no extra
  record" is true of 92 photographs and false of 129.** The whole HEIC session
  is named `IMG_####` — a camera counter — and carries no laboratory number and
  no label card. Counting each of those as its own sample is what produced 194
  and would have put two photographs of one dish into two different splits over
  58 % of the archive. SPEC 0040 D4 recovers the identity from the capture
  clock: photographs within 60 seconds are one sample, which yields 63 groups,
  and every such identity is marked `capture-burst` in the manifest so a derived
  group is never read as a declared one.
- **There is one camera, not "more than one".** Every population that carries
  EXIF carries an iPhone 11. The 2.6× scale spread this record measured from the
  dish rim is three export and transport paths out of one device: the native
  HEIC session at 3024×4032, a JPEG export at 1536×2048 that kept its EXIF, and
  a transported JPEG at roughly 1600×900 that lost its EXIF and was re-encoded
  with a luminance quantization table three to four times coarser in the
  high-frequency band. Their long-side ratios are 1.00 : 0.508 : 0.397, a spread
  of 2.52.

**Amended again 2026-09-01: the dataset is closed.** The project owner states
that the delivered archive is the whole of it and that the laboratory takes no
part in the project in any aspect. Three things this record leaves open are
therefore shut, and none of them is pending:

- **There is no more rig time.** This record's central relief was that producing
  the dataset had become photography rather than a collection campaign, over
  material that already existed. That material is not available, so the 105
  sample groups are a ceiling and not a starting point.
- **The samples cannot be re-photographed.** Re-spreading the soil between
  exposures would have been the strongest augmentation available to this
  project — the granulometry is unchanged while the grain arrangement is a new
  realisation, which no digital transform produces — and it requires the
  physical dishes, which are at the laboratory.
- **New soil cannot be labelled.** The class is the laboratory's own
  classification, so material collected elsewhere carries no textural group.
  Anything new can enter as unlabelled data only, which is what makes
  self-supervised pretraining worth its cost rather than an optimisation.

The decisions above are unaffected: the archive is still the dataset, the dish
rim still gives scale, Siltosa is still out. What changes is that the
alternatives this record weighed them against no longer exist.

**One consequence this record should be read against, and does not itself
resolve.** It excludes Siltosa for holding fewer than 30 samples. Under the
corrected count **three of the four remaining classes are also below 30** —
Arenosa 26, Media 22, Muito Argilosa 21 — and only Argilosa clears it at 33.
With the transported population held to training per SPEC 0040 D6, 77 sample
groups are splittable across the four classes, so a 0.15 test fraction leaves
two to three groups of each class in the test set. Whether a floor of 30 still
means what it meant here, and whether a single three-way split is the right
instrument at this size, are open and are not decided by this amendment.

## Context

ADR 0014 was written on 2026-08-11 from the project owner's answers, before any
image was available to this workstream. It described a collection to be
performed: a fixed rig, a constant millimetres-per-pixel, two conditions per
sample, roughly 150 samples per class, and photography that had not begun.

The images were delivered on 2026-08-25. Measured against the description, four
of its premises are false and one is true by a different mechanism.

**There is no fixed rig.** Scale across the 92 readable JPEGs, taking the dish
as 90 mm, spans 5.73 to 14.93 pixels per millimetre — a factor of 2.6. The
median is 10.0 px/mm, or 0.100 mm/px. A fixed rig produces one value.

**There is more than one camera.** 44 photographs carry iPhone 11 EXIF dated
2023-11. 48 carry no EXIF at all, sit at roughly 1600×900 in landscape where the
first group is 1536×2048 in portrait, and include a printed label card bearing
the sample number inside the frame. The 129 HEIC files were not inspected and
may hold a third population.

**Photography has not begun is false: it is finished**, for this set. What was
described as weeks of rig time ahead is a directory that already exists.

**The counts are far below the target and asymmetric in a way the record did not
anticipate.** ADR 0014 declared roughly 150 samples per class and named Siltosa
as the class expected to fall short. It falls short of the record's own
feasibility floor by an order of magnitude.

| Class | Samples | Images |
|---|---|---|
| Arenosa | 57 | 68 |
| Média | 36 | 42 |
| **Siltosa** | **3** | 6 |
| Argilosa | 59 | 63 |
| Muito Argilosa | 39 | 42 |
| **Total** | **194** | **221** |

The sample identifier is the laboratory number and it is carried in the
filename: `100262,1 (1).JPEG` is photograph 1 of sample `100262,1`. Grouping by
sample is therefore possible without any additional record. 177 samples have one
photograph, 11 have two, 2 have three, and 4 have four.

**What is true, by a different mechanism: the material is dry and sieved bench
material.** The photographs show it. So ADR 0014's central limitation — no
accuracy figure from this dataset describes field-fresh soil — survives its own
record intact.

## Decided

### The dataset is what exists, and it is the primary dataset

Not pre-training material, and not a stopgap. It is the same material ADR 0014
described, photographed, with the class name as the whole label. The programme
stops waiting for photography that already happened.

Two consequences follow immediately and are the reason this is worth deciding
rather than assuming. **Experiment E0 becomes runnable now** rather than after
weeks of collection, which moves the programme's go/no-go gate from a schedule
item to this week's work. And **the scale variation is a property of the data**,
so it has to be handled rather than declared absent —
[ADR 0017](0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)
is what handles it.

### Scale is recovered from the dish rim, not assumed

The dish is a circle of known diameter in every image. Measuring it recovers
millimetres per pixel per photograph, which is what makes a 2.6× spread a
recorded quantity instead of an invisible one. ADR 0014 already conceded the
mechanism for a different purpose — *"a circle of known diameter being
detectable without any model"* — and this is that concession applied to the
photographs that exist.

The manifest gains a measured `disc_diameter_px` per row. Its spread is reported
per dataset version, so a change in the capture arrangement is visible in the
validator rather than invisible in the data.

### Siltosa is out of the first model

Three samples cannot support a five-way verdict. `create_splits`
(`ml/src/dataset.py:226-238`) requires three groups per class, so three samples
is exactly the arithmetic minimum: one in train, one in validation, one in test.
A per-class figure computed on one test sample is a coin flip presented as a
measurement.

This is the third branch ADR 0014 pre-declared for exactly this outcome, and
taking it is what that record was for. The first model classifies **Arenosa,
Média, Argilosa and Muito Argilosa**.

**The product still names five classes and the model produces four**, and the
gap between those two facts is the cost. A silty sample photographed by a user
will be assigned one of the four with whatever confidence the aggregate
produces. **The out-of-distribution score that detects it is built for the first
release** (#194), decided 2026-08-25 on exactly this reasoning: an excluded class
with no detector is a silent wrong answer, and it is the one guard available. The
exclusion is also declared in the application, not merely in this record.

### The remaining classes are close to balanced, and that is a simplification

At 57 / 36 / 59 / 39 the largest-to-smallest ratio is 1.6. The pathology that
class weighting exists to prevent is a batch-composition effect that appears at
ratios two orders of magnitude larger. Weighting stays configured because it
costs nothing at this ratio; comparing it against focal loss stops being a
priority experiment.

### Labels are the folder, and are not verified against the laboratory

The project owner decided on 2026-08-25 not to obtain the sample-number-to-class
list that would allow the folder assignment to be checked. Granulometry was
already excluded by ADR 0014 and that exclusion stands; this is narrower and
separate, and it is recorded because the two are easy to conflate.

The cost: label noise is not merely unbounded, as ADR 0014 recorded, but
**unverifiable even in principle**. No artefact in this project can distinguish
a misfiled photograph from a model error, and every accuracy figure carries that
without any way to size it.

### The cost-weighted confusion matrix is buildable, and ADR 0014 was wrong that it is not

ADR 0014 recorded that excluding granulometry makes the cost-weighted confusion
matrix **not buildable**, so every confusion must weigh the same in evaluation.
That does not follow, and the error is worth naming because it removed a metric
from the plan on a reason that never held.

A cost ordering says which mistakes are worse. Calling a sandy soil very clayey
inverts the management recommendation; confusing the two clayey groups shifts it
slightly. **That ordering follows from what the classes mean, not from the
percentages behind them.** It needs an agronomist, not a laboratory report.

Supplied by the project owner and approved 2026-08-25, over the four classes the
first model carries:

| Confusion | Weight |
|---|---|
| Arenosa ↔ Muito Argilosa | most serious — opposite ends |
| Arenosa ↔ Argilosa | serious |
| Média ↔ Muito Argilosa | serious |
| Arenosa ↔ Média | moderate |
| Média ↔ Argilosa | moderate |
| Argilosa ↔ Muito Argilosa | mild — adjacent |

**Symmetric**, taken as the default: over-reading clay and under-reading it carry
the same weight. Nobody asked for an asymmetry and inventing one would encode a
claim about management cost that has not been made. Making it asymmetric later is
a change to one table.

This reverses ADR 0014's claim and settles the contradiction #189 records, where
the matrix is listed as a reported metric in two places and as unbuildable in two
others. It is reported, and #188 is where it is computed.

## Considered Options

- **Treat the delivered images as pre-training only and wait for a rig
  collection** — rejected. It was the position held before the images were
  inspected, and it rested on the scale being unrecoverable. The dish rim
  recovers it, the material is the same archive, and the protocol is the same
  family. Waiting would defer the go/no-go gate by weeks for no measured reason.
- **Re-photograph all 194 samples on a fixed rig before doing anything** —
  rejected for now, and deliberately left available. If E0 fails, re-photography
  would not have helped; if E0 passes, its numbers say what re-photography would
  buy. Deciding before the measurement would be spending rig time against a
  premise nobody has tested.
- **Run all five classes anyway and report Siltosa with its one test sample** —
  rejected. It is the outcome ADR 0014 pre-emptively forbade, and the reason
  stands: the number would read as a measurement and would be luck.
- **Merge Siltosa into Média to keep four classes without an exclusion** —
  rejected. The laboratory reports five groups, so the application would
  disagree with the report the user already has. An absent class the app admits
  to is more honest than a merged one it does not.
- **Discard the 25 % of photographs whose scale is coarsest, to allow a finer
  canonical scale** — rejected. It buys a larger patch count out of a dataset
  where one class already holds three samples. See ADR 0018 for the arithmetic
  it would have improved.

## Consequences

- **ADR 0014 is Retired in place**, keeping its number and file per the
  durable-numbering rule. Its granulometry exclusion, its bench-to-field
  limitation and its Siltosa policy are carried forward here; its rig,
  conditions, counts and scale-constancy claims are withdrawn.
- **SPEC 0033 is revised**: the manifest is built from filenames rather than
  authored by a collector, `dish` is the condition that exists, `paper` describes
  the application rather than the dataset, and `disc_diameter_px` is added.
- **`ml/README.md`'s target-image table is superseded** by the measured counts
  above.
- **129 of 221 files are HEIC**, which neither `tf.io.decode_image` nor the Dart
  `image` package can read. 58 % of the dataset is unreadable by both sides of
  the pipeline until converted. This is implementation work, not a decision, and
  it precedes everything else.
- **E0 runs on four classes, 191 samples**: roughly 134 train, 28 validation, 29
  test, which is 5 to 9 samples per class in test. **No per-class claim is
  supportable at this size**, and E0's design — a distribution compared against a
  label-shuffled control across several seeds — is the only form of evidence the
  set can carry. #183 is the record of that arithmetic.
- The bench-to-field gap, the excluded granulometry, the unverifiable labels and
  the absent class are four limitations that travel with every number this
  dataset produces. They belong in any statement of what the model has been shown
  to do.
