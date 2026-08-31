# The model sees greyscale patches of a fixed physical size, and their disagreement is a capture-quality signal rather than a confidence

VisioSoil classifies a photograph by cutting it into a grid of overlapping
patches, each covering the same **physical area of soil** — about 21 mm across —
converted to greyscale, and classified independently. A 90 mm dish yields
twenty-five; the application refuses a soil region too small for nine. The mean of their distributions is
the reading. Their **disagreement is reported as an image-quality criterion**,
not as model confidence, because it measures how evenly the sample was spread
rather than how sure the model is.

## Status

Accepted 2026-08-25. Amends
[ADR 0009](0009-fixed-roi-and-heuristic-quality-gate-over-segmentation.md),
whose region of interest was a single centred square, and
[ADR 0011](0011-classification-verdict-from-margin-and-mass.md), which computes
its verdict from one distribution and now receives an aggregate. Depends on
[ADR 0017](0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md),
without which "the same physical area" has no meaning.

## Context

Two measurements from the archive audit set everything in this record.

**Resolution.** At the measured 0.100 mm/px median, the Nyquist limit is
0.20 mm. Against the fine-earth fractions — clay below 0.002 mm, silt 0.002 to
0.05 mm, sand 0.05 to 2.0 mm — individual particles are resolvable only in the
medium and coarse sand range. **Nothing separating the finer classes can come
from resolving grains**; it must come from aggregate and surface appearance.
That is a real threat to the product premise and it is what experiment E0 exists
to test.

**A single 224-pixel view of a 90 mm disc is the wrong analysis window.** It
covers the whole dish at roughly 0.4 mm per pixel, which is coarser than the
photograph itself and discards most of what was captured. A patch at the
photograph's own resolution keeps it.

## Decided

### Patches are measured in millimetres of soil, never in pixels

This is the decision that makes ADR 0017 worth having. A patch defined in pixels
covers a different amount of soil on every camera and at every distance, so the
same soil presents as two different soils and the scale reference buys nothing.
A patch defined in millimetres covers the same soil everywhere.

The arithmetic is fixed by the canonical scale and the model input:

| Model input | Patch, at canonical 0.130 mm/px |
|---|---|
| 224 px | 29.2 mm |
| **160 px** | **20.8 mm** |
| 128 px | 16.6 mm |

**The input is 160 px.** It is one of the sizes MobileNetV2 publishes ImageNet
weights at — 96, 128, 160, 192, 224 — so it costs nothing in transfer.

### The grid overlaps, at half a patch of stride

**A first version of this record put the patch count at "~15 by area" for a
90 mm disc. That was wrong, and the error is worth showing because the corrected
number is what forces the overlap.** Squares do not tile a circle to its
boundary: a square of side `s` fits entirely inside a circle of diameter `D` only
if the grid fits the *inscribed* square, of side `D/√2`. So a 90 mm disc holds a
3×3 grid — **nine** patches of 20.8 mm, not fifteen — and the count moves in
steps of a perfect square as the disc grows.

| Disc | Non-overlapping | At half-patch stride |
|---|---|---|
| 70 mm | 4 | **9** |
| 80 mm | 4 | 21 |
| 90 mm | **9** | **25** |

Non-overlapping tiling would have made "at least nine patches" mean "a disc of at
least 88 mm" — the size of the dish itself, leaving the application no slack at
all against its own training data.

**Overlapping costs nothing that was not already conceded.** The section below
establishes that patches of one photograph are *not* independent and are
therefore not an ensemble; they are repeated samples of one spatial statistic.
Overlapping samples of a statistic are still samples of it. What overlap does buy
is a count that varies smoothly with the disc instead of jumping between 1, 4 and
9, and a dispersion measure with enough points to mean something at the small end.

**The cost is inference time and this record previously understated it.** Twenty
five passes at 160 px is roughly 3,850 MFLOPs per photograph, not the ~2,100 of
seven passes at 224 px. The per-pass cost in seconds has never been measured, so
the end-to-end figure is unknown and may force the stride wider.

`ml/src/config.py:39` currently rejects any input but 224 for this architecture
and must be widened to the published set — not to arbitrary values, since the
reason the check exists is that an unpublished size loads without error and
degrades transfer silently.

### The model sees greyscale, and the reason is not the one first given

Hue in soil tracks iron oxide content and organic matter — **mineralogy, not
particle size**. It is therefore a shortcut available to the model that is
correlated with the label through the region a sample came from rather than
through the property being classified. Discarding it forces the model onto
texture.

**The reason first recorded for this decision was wrong and is withdrawn here
rather than quietly dropped.** Greyscale was justified as closing the dry-to-wet
gap between the archive and field use. It does not: wet soil is *darker*, and
darkness survives the conversion. Greyscale removes the hue shift and leaves the
luminance shift untouched. The dry-to-wet gap is mitigated by brightness
variation in augmentation, and remains open beyond that.

Three implementation consequences:

- **One definition of luma, already shared.** `ml/src/image_quality.py` and its
  Dart counterpart both use ITU-R BT.601 at 0.299 / 0.587 / 0.114, implemented in
  both languages and pinned by a committed golden file. The model path reuses it
  rather than introducing a second definition.
- **The tensor keeps three channels**, with the grey value replicated, so
  ImageNet weights load unchanged.
- **The colour-cast criterion loses its justification.** SPEC 0030 argues that
  criterion matters because soil colour is signal. It is no longer input to the
  model, so the criterion is a capture-quality signal only and its threshold
  stops being load-bearing.

### The patches are not an ensemble, and this changes what the mean means

The requirements for an effective ensemble are diversity, independence and
quality: the members must err in different ways and their errors must not be
correlated. **Patches of one photograph violate independence by construction** —
one camera, one instant, one lighting, one sample, one set of weights. The
wisdom-of-the-crowd argument that justifies averaging an ensemble does not apply.

What this is instead: texture is a **statistic of a surface**, and the patches
are repeated samples of that statistic. That reading fixes both halves of the
aggregation:

- **The mean of the distributions estimates the statistic.** It is the right
  estimator for repeated samples of one quantity, and it uses everything each
  patch reported rather than only the class each one picked.
- **The spread across patches measures spatial heterogeneity of the presented
  sample** — soil piled unevenly, a stone, a root, a thin edge. It does not
  measure whether the model is out of its depth.

### Disagreement is the eighth quality criterion, not a confidence

The spread is computed as Shannon entropy over the class distribution of the
patch predictions, **divided by its maximum for that patch count** so a variable
count stays comparable, joins the seven criteria of SPEC 0030, and produces a message
in the same shape as the others: *the regions of this sample disagree; spread it
more evenly and retake*.

The distinction is the whole point. **A sample the user can fix and a model
outside its training territory have different remedies**, and one number cannot
carry both. Presenting patch disagreement as low confidence would tell a user to
consult a specialist when the actual fix is ten seconds with a spatula.

Model-level uncertainty — the failure where a network predicts a wrong class
with high probability on an input unlike anything it was trained on — is a
different mechanism and is not addressed here. It is what the embedding-distance
out-of-distribution score is for (#194), which the project owner decided on
2026-08-25 to build for the first release — because with Siltosa excluded, that
score is the only thing standing between a silty sample and a confident wrong
answer.

The threshold on the entropy is **provisional**, like every other threshold in
SPEC 0030, and is calibrated against real images or not at all.

### One photograph is one sample, whatever the patch count

Patches multiply training examples: 191 samples at 25 patches each is about
4,800 training tensors rather than 221 images. Overlapping patches multiply the
tensor count without multiplying the information, which is a reason to be careful
about reading the number as a dataset size. **They multiply nothing in
evaluation.** Patches of one photograph are correlated; photographs of one
physical sample are correlated. The unit of statistical independence stays the
**sample**, splits stay grouped on it, and any per-class figure is computed over
samples.

Reading a patch count as a sample count would inflate every reported interval by
roughly a factor of four, and it would do so invisibly.

### Two consequences the patch decision has for other records

Both were missed when this record was first written and are added here rather
than left for a reader to derive.

**The dish-versus-paper background difference nearly disappears.** A patch cut
from inside the soil region is soil and nothing else — no glass rim, no bench, no
sheet. The container decides where the region is and what the scale is; it does
not appear in the tensor. The dataset being dish photographs and the application
being paper therefore stops being a domain gap, provided the grid is inset from
the region boundary so edge patches do not straddle it. SPEC 0037 carries the
inset. **#192, compositing onto real backgrounds, drops sharply in value as a
result**, and the "severe" background axis in the study's §5 gap map is wrong
under this decision.

**EXIF orientation stops being a train-serve skew.** It is recorded as risk R5
and in SPEC 0035's own risk list, on the reasoning that one side bakes the
orientation tag and the other discards it. Under a patch grid the image is
located, cropped and cut regardless of which way up it was decoded, and the
eightfold symmetry augmentation makes orientation irrelevant to what the model
learns. What survives is a cosmetic difference in how a photograph is displayed,
which is not this workstream's concern. The risk is downgraded, not closed:
anything that reintroduces a whole-frame crop reinstates it.

## Considered Options

- **One centred square over the whole disc**, as ADR 0009 specified — rejected.
  At 224 px it views a 90 mm disc at 0.4 mm per pixel, coarser than the
  photograph, discarding most of the captured detail on a task whose signal is in
  that detail.
- **A single zoomed patch at the centre** — rejected. Same resolution benefit as
  a grid, no dispersion measure, and it inherits whatever happens to be at the
  centre of that particular dish.
- **Majority vote across patches** — rejected. It discards how sure each patch
  was, so a patch at 51 % and one at 99 % count alike, and the percentage the
  screen shows cannot be reconstructed from votes.
- **The most confident patch decides** — rejected. The most confident patch is
  disproportionately the one that caught something atypical — a stone, a shadow, a
  root — so a single outlier overrides the rest.
- **Median across patches, discarding outliers** — rejected on the project
  owner's stated objection to aggregations that hide disagreement. Discarding the
  dissenting patch produces a clean, confident number by deleting the evidence
  that it should not be confident.
- **A learned aggregator over the patch outputs** — rejected on data. It is the
  most capable option and it needs far more samples than 191 to fit without
  memorising, and it would make the final answer hard to explain.
- **Requiring agreement, by combining multiplicatively** — rejected, and it is
  the closest call. It folds disagreement into the confidence automatically, with
  no second threshold to calibrate, which is genuinely attractive. It was not
  taken because it merges the two quantities this record exists to separate: the
  user would see one weak number and not know whether to spread the sample again
  or to stop trusting the reading.
- **Keeping colour and deciding by measurement** — rejected by the project
  owner, who chose greyscale on the mineralogy-shortcut argument after the
  original dry-to-wet argument was withdrawn. Recorded because E0's
  colour-histogram arm measures exactly what the choice cost, it runs in minutes,
  and until it does the decision rests on a mechanism rather than a number.

## Consequences

- **The preprocessing path is rewritten on both sides**, and it is a larger
  change than SPEC 0035 describes: read the scale reference, rectify, normalise
  to the canonical scale, convert to greyscale, cut a patch grid, batch. SPEC 0035
  covers reading the contract and the failure taxonomy, not this. A new
  specification carries it.
- **`spec.json` grows**: canonical millimetres per pixel, patch size in
  millimetres, patch count, colour mode, aggregation rule, dispersion threshold.
  All are values the model was trained under, so all are contract values, and
  SPEC 0035's schema is revised rather than extended later.
- **`ml/src/dataset.py` changes shape.** One path currently yields one tensor;
  it now yields many, so the mapping becomes a flat-map and the batching follows
  patches while the splitting stays on samples.
- **Inference cost multiplies by the patch count.** Fifteen forward passes per
  photograph on a CPU-only device. The per-pass cost has never been measured —
  the 15 s in `inference_service.dart` is a timeout, not an expectation — so the
  end-to-end figure is unknown and is the first thing the release measurement
  should report.
- **SPEC 0030's `minRoiSidePx = 512` is re-scoped to the disc**, not the patch. A
  160 px patch is far below it and every image would be refused. Re-scoped, the
  value is coincidentally right: 512 px across a 90 mm disc is 0.176 mm/px, which
  is the coarsest photograph in the archive.
- **ADR 0011's verdict is computed on the aggregate**, and its structure is
  untouched: the same two quantities over the same shape of distribution.
- The dispersion criterion arrives with no calibration data, like the other
  seven. It ships advisory.
