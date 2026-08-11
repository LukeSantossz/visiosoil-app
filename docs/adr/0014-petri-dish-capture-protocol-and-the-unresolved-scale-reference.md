# Collection photographs a 90 mm Petri dish on a fixed rig; the deployment scale reference is left unresolved and named as the dominant skew

VisioSoil's dataset is built by photographing the soil laboratory's existing
sample archive, not by collecting new samples. Every photograph shows air-dried,
sieved soil presented as a centred disc, on a bench rig at a fixed camera
distance, in two background conditions. Field-fresh material is out of scope for
this dataset.

The same decision leaves one thing deliberately unresolved and records it as the
programme's dominant risk rather than closing it prematurely: the dataset will
have a near-constant millimetres-per-pixel scale and the application will not,
on a task whose signal is particle size.

## Status

Accepted for the collection protocol. **The deployment scale reference is open**
and is registered as an input in `docs/architecture/ml-implementation-map.md` §7.

Recorded 2026-08-11 from the project owner's answers to the §7 inputs. Supersedes
the coin decision in SPEC 0033 for the collection side only — see *Consequences*,
where the coin survives for a reason that has moved.

## Context

Four answers, given 2026-08-11, changed premises that the study, ADR 0009 and
SPEC 0033 were all written on top of.

**The laboratory is the project's own, and it keeps the analysed samples with
their reports linked.** The study assumed granulometry spreadsheets existed but
were unusable, and concluded that labels were untraceable to the measurements
that produced them. That is now false. Sand, silt and clay percentages are
available per sample, the Embrapa grouping is a reading applied to those numbers
rather than the origin of the labels, and the physical samples are on a shelf.

The consequence is that the dataset costs **no new laboratory analysis at all**.
It is bounded by photography time over an archive that already exists. Every
schedule and cost argument in the study that treated collection as the expensive
step was reasoning from the opposite premise.

**The samples come from many origins**, because the laboratory serves many
clients. The site axis, which SPEC 0033 recorded but declined to enforce a split
along because nobody knew whether more than one site existed, is populated.

**The presentation is a 90 mm Petri dish on a fixed rig.** The target is
therefore a circle of known diameter, centred, at a known distance. ADR 0009
chose a fixed centred-square ROI and rejected segmentation arguing that
separating foreground from background needs a model and per-scene tuning. That
argument assumed a target of unknown shape. It no longer holds, and the
consequence is worked through in *Decided* below.

**The second condition is the same soil arranged as a circle on paper, without
the dish, and the application will not use a dish at all.** This is the answer
that creates the problem this record exists to name.

## Decided

### The dataset is the archive, photographed; it is not a collection campaign

Samples are drawn from the laboratory archive, where each carries a linked
report with its granulometry. `sand_pct`, `silt_pct` and `clay_pct` stop being
optional manifest columns and become required, because they are now available for
every row and they are what makes three things possible that were previously
written off:

- **Label verification.** The Embrapa class is a reading of those percentages on
  the textural triangle. A declared class that contradicts its own numbers is a
  labelling error that can now be found mechanically, so label noise stops being
  an unbounded ceiling on measured accuracy.
- **Boundary samples become identifiable.** A sample at 34 % clay and one at
  36 %, either side of a 35 % line, are visually indistinguishable and their
  class difference is a convention. Marking them means an `ambiguous` verdict on
  such a sample is correct behaviour being measured as correct, instead of being
  counted as an error the model was never able to avoid.
- **Coverage is a map rather than a tally.** Per-class counts say Siltosa is
  thin. The triangle coordinates say *which region* is empty, which is what
  directs any future collection.

### Two conditions, both dry and sieved; field-fresh material is out of scope

| Condition | Presentation | Background |
|---|---|---|
| `dish` | Soil in a 90 mm Petri dish | Bench surface |
| `paper` | The same soil arranged as a disc of the same size, no dish | White paper sheet |

Both are air-dried, sieved archive material. The `paper` condition varies the
background and the container edge; it does **not** vary the physical state of the
soil.

This is worth stating flatly because the opposite reading is available and
wrong: photographing archive material on paper does **not** cover the field mode
the product was described as supporting, where an agronomist takes a sample from
10 cm depth and spreads it on a sheet. That soil is moist and unsieved, it holds
aggregates, and moisture displaces its colour. Nothing in this dataset
represents it.

**Binding consequence.** No accuracy figure from this dataset describes fresh
material, and the application must not treat a photograph of fresh material as
analysable. The limitation is declared in `spec.json` and carried in the
classification contract the UI terminal consumes. In-situ capture is deferred,
not cancelled: it is a separate decision with its own cost, and unlike the two
conditions above it cannot reuse the archive, because a sample cannot be
photographed undisturbed after it has been dried and sieved.

### Sample counts are asymmetric by class, and that is a property of soil

The target is roughly 150 samples per class, one photograph per sample per
condition, with the sample as the split group. Siltosa is the exception and will
not reach it. Silty soils are genuinely uncommon across much of the Brazilian
soil population, so the shortfall is a property of the material rather than of
collection effort, and no amount of photography fixes it.

A uniform target is therefore dropped in favour of a declared asymmetric one,
with class weighting and a per-class rejection threshold for Siltosa. The
alternative — presenting a five-way model whose fifth class rests on a fraction
of the evidence of the others — is the failure SPEC 0033's reduced-class E0 rule
was already written to prevent, arriving through a different door.

### The ROI shape becomes an experiment, and ADR 0009's premise is amended

A circle inscribed in a square fills π/4 ≈ 78.5 % of it, so **21.5 % of every
current ROI is guaranteed not to be soil** — dish rim, bench, or paper. It is
also precisely the region that differs between the two conditions.

Three designs follow, all purely geometric, all deterministic, none requiring a
model or per-scene tuning, so all remain within what ADR 0009 permits:

| Design | Soil in the tensor | Note |
|---|---|---|
| Centred square (current) | ~78.5 % | The `paper` condition carries the whole burden of teaching background invariance |
| Circular mask, corners filled | 78.5 % useful, remainder constant | Background disappears; makes the `paper` condition nearly redundant |
| Square inscribed in the circle | **100 %** | Loses ~36 % of the disc's area, gains resolution per unit of soil |

For a texture task the third is the most promising, because the signal is
statistical and spatially homogeneous, so a smaller all-soil region plausibly
beats a larger region that is one fifth background. **That is a mechanism, not
evidence.** All three are preprocessing variants over one dataset, so they cost
almost nothing to compare and the choice is made by measurement as arms of E1.

What is decided here is narrower and does not wait for E1: **ADR 0009's stated
premise of an unknown target shape no longer holds**, and any future argument
that cites it must cite this amendment too.

## The unresolved part: scale

This is the reason this record exists, and it is stated as a problem rather than
a solution because no answer available today is free.

Textural class is a statement about **particle size**. Particle size in an image
is meaningful only if the scale is known: coarse grains photographed far away and
fine grains photographed close produce the same pixels. Scale is not a nuisance
variable on this task, it is a precondition for the signal to exist.

| Rows | Scale |
|---|---|
| `dish` | Constant by construction — fixed rig, 90 mm dish of known diameter |
| `paper` | Near-constant if the disc is sized to match; **uncontrolled if arranged by eye** |
| Application | **Unknown and variable** — handheld, no dish, no reference object |

So the dataset is excellent on exactly the axis where deployment is worst, which
is the shape a train/serve skew takes when it is invisible: every image looks
correct on both sides.

Three ways out, none of them cost-free, and this record deliberately does not
choose among them:

1. **A scale reference in the application frame.** SPEC 0033 kept the coin and
   argued its value had moved to the deployment side. That argument is now
   confirmed rather than superseded — the coin is unnecessary in the `dish` rows,
   whose scale is already known, and it is the only identified route to
   recovering millimetres per pixel from a single handheld photograph. The cost
   is a physical object the user must carry and place.
2. **Scale-invariant training.** Heavy scale augmentation, accepting that
   absolute particle size is deliberately destroyed. Honest, and it discards part
   of the signal the task is built on.
3. **Enforced framing.** A capture guide fixing the apparent disc size in the
   frame. It constrains distance without measuring it, and it depends on user
   compliance that nothing verifies.

The `paper` rows admit a cheap partial fix that is worth taking whichever way
the above resolves: **arrange the disc against a 90 mm template**, so both
conditions share one scale and the dataset does not acquire unrecorded scale
variation of its own. Uncontrolled and unmeasured variation is worse than either
a constant or a measurement.

## Alternatives Considered

- **Photograph the dish in the `paper` condition too** — would have made the
  90 mm rim present in every image and scale recoverable from the image itself by
  pure geometry, a circle of known diameter being detectable without any model.
  Not chosen: the project owner's design places bare soil on paper. Recorded
  because it is the option that would have dissolved the scale problem, and
  because if the scale question is later reopened this is the cheapest lever.
- **Require the dish in the application** — rejected by the project owner. It
  would align training and inference on one presentation at the cost of a
  physical item in the product.
- **Treat `paper` as covering the field mode** — rejected on mechanism. The
  physical state of the soil differs, and background is not the variable that
  separates them.
- **Photograph each sample several times per condition** — declined. It would
  give real rather than synthetic variation in framing and lighting at the cost
  of photography time only, with no effect on statistical power since the group
  is the sample. Declined by the project owner; recorded because it stays
  available and cheap if augmentation later proves insufficient.
- **Keep a uniform 150-per-class target** — rejected. It cannot be met for
  Siltosa at any effort, and a target that cannot be met stops being a target and
  becomes a misreport.
- **Decide the ROI shape here by argument** — rejected. The mechanism favouring
  the inscribed square is plausible and untested, and testing it costs one extra
  arm in an experiment that is already planned.

## Consequences

- SPEC 0033 is revised, not merely amended: its laboratory row, its optional
  granulometry columns, its `setting` enum, its untraceable-labels limitation,
  its container-edge framing rule and its target counts are all affected.
- The framing rule in SPEC 0033 — *"no background, hand, tool, or container edge
  inside the square"* — is directly contradicted by a protocol built on a Petri
  dish, whose rim is the target boundary. It is restated in that revision.
- A site-held-out split becomes affordable and moves from declined to the
  expected default, since the site count is no longer unknown.
- The `setting` enum's open note in SPEC 0033 is closed: the values are `dish`
  and `paper`, with in-situ deferred.
- The coin survives in the protocol, for the deployment-side reason SPEC 0033
  already gave, pending the §7 decision above.
- ADR 0009's unknown-target premise is amended; its choice of a fixed ROI over
  segmentation stands, because all three candidate shapes are fixed geometric
  conventions rather than segmentation.
