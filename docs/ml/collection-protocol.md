# Soil Dataset Collection Protocol

> **Withdrawn 2026-09-01.** There will be no further collection and no
> re-photography: the delivered archive is the whole dataset and the laboratory
> takes no part in the project in any aspect
> ([ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md),
> amended). This document described a collection to be performed, and the
> paragraph below already recorded that it was not performed this way; what is
> new is that it will not be performed at all. It is kept because three of its
> rules outlived it and are cited from elsewhere — the immutable-version rule,
> the manifest as the authoritative record, and the admission verdicts — and
> because a protocol deleted is a protocol whose citations stop resolving.
>
> Its counts also predate the corrected inventory: it says 194 samples where the
> archive holds **105 sample groups over 221 photographs**.

> **Superseded for the current dataset, 2026-08-25.** This document describes a
> collection to be performed. It was not performed this way: 221 photographs of
> 194 samples were delivered on 2026-08-25, already taken, and
> [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
> describes what they are. Read this document as the protocol for **any future
> re-photography**, not as a description of `v1`.
>
> **What the delivered set does not match:**
>
> | This document requires | The delivered set |
> |---|---|
> | One camera for the whole dataset | At least two, with different framing and resolution |
> | A fixed camera-to-sample distance | Scale spans a factor of 2.6 |
> | Two photographs per sample, `dish` and `paper`, pairing enforced | One condition, `dish`. 177 of 194 samples have a single photograph |
> | A coin in frame, outside the centred square | Not usable, and dropped — see ADR 0017 |
> | A paper template for the `paper` condition | No `paper` rows exist |
> | 30 samples per class as the feasibility floor | Siltosa holds three |
>
> **What still holds, and is why this file is kept:** the immutable-version rule
> (§6), the manifest as the authoritative record (§5), the admission verdicts
> (§7), the rejection of granulometry and moisture columns, and the counting unit
> being samples rather than photographs (§8).
>
> **What a future re-photography must add**, from decisions taken after this was
> written: a `disc_diameter_px` measured per row; the rig set to the **finest**
> millimetres per pixel it can achieve, because resampling only runs toward
> coarser and resolution given away at capture is never recovered; and an A4
> sheet under the dish, so both sides share one scale reference.
>
> The application-side protocol is a different document and belongs to the UI/UX
> terminal: a bare A4 sheet, soil spread as a disc of at least ~70 mm, the whole
> sheet in frame, the collection point marked before preparing the sample, and a
> declaration of whether the sample was sieved.

The procedure for building a dataset version, written so it can be executed
without the engineering terminal present. Every rule here was decided against a
stated alternative; the reasons are kept next to the rules because a rule whose
reason is lost gets dropped the first time it is inconvenient.

Specified by
[`docs/specs/0033-dataset-protocol-manifest-and-splits.md`](../specs/0033-dataset-protocol-manifest-and-splits.md).
The capture presentation and the unresolved scale question are recorded in
[ADR 0014](../adr/0014-petri-dish-capture-protocol-and-the-unresolved-scale-reference.md).

## 1. What this collection is

The laboratory's **existing sample archive, photographed**. It is not a field
campaign. The samples are already labelled by the laboratory that analysed them,
so the dataset costs rig time and **zero new laboratory analyses**.

Every sample is **air-dried and sieved** archive material. Two consequences that
must not be softened when the resulting model is described:

- **Field-fresh soil is not covered.** Fresh material is moist and unsieved,
  holds aggregates, and moisture displaces its colour. It is a different physical
  object. `in_situ` is not an accepted value in the manifest today, and a sample
  cannot be photographed undisturbed after it has been dried and sieved.
- **No accuracy figure from this dataset describes fresh material.** Every
  number it produces describes prepared samples on a bench.

## 2. What you need

| Item | Requirement |
|---|---|
| Camera | **One device** for the whole dataset. Record its make and model |
| Rig | Fixed camera-to-sample distance, top-down. Around 20 cm, the figure the existing protocol already states (`docs/design/ux-2026/14-capture-guide.md` §2). What matters is that it is fixed, not the exact number |
| Petri dish | 90 mm diameter, for the `dish` condition |
| Paper template | A printed 90 mm circle on a white sheet, for the `paper` condition |
| Coin | Any coin of a known denomination, placed as §4 states |
| Lighting | Diffuse. **No flash** |
| Spreadsheet | For `manifest.csv`, saved as UTF-8 with comma separators |

## 3. Two photographs per sample

Each physical sample is photographed **twice**, once in each condition:

| `setting` | Presentation | Background |
|---|---|---|
| `dish` | Soil in the 90 mm Petri dish | Bench surface |
| `paper` | The same soil arranged as a disc of that size, no dish | White paper sheet |

**The pairing is mandatory and the validator enforces it.** It is what lets the
background effect be measured within one physical sample rather than across two
populations. A version holding only `dish` rows would pass every other check
while silently being a one-condition dataset, and nothing downstream would notice
until the comparison it was built for turned out to be impossible.

`paper` varies the background and removes the container edge. It does **not**
vary the physical state of the soil, so it is not a field condition.

## 4. Framing

### The fill rule

> **The soil disc is centred and touches the guide circle. Nothing but the disc,
> its container, and the surface beneath them appears inside the guide — no hand,
> no tool, no second sample.**

Stated over the **circle** rather than the square, so it stays correct whichever
region-of-interest shape the ROI experiment selects. Stated without a percentage
because a proportion of a frame is not something a person estimates reliably; the
numeric criteria live in the acceptance-criteria library, where they are actually
measured.

**The dish rim is admitted deliberately, not tolerated.** It is constant, it sits
at the disc boundary, and it is the only object of known size in the frame. An
earlier phrasing of this rule forbade any container edge inside the analysed
region, which forbade the protocol it was meant to describe.

### The coin

**Place the coin outside the centred square** — a 4:3 frame leaves margin on both
sides of the largest centred square, and the coin goes there.

The reason is mechanical rather than aesthetic. A coin is a smooth metal disc: in
the analysed region it **lowers the Laplacian variance** the blur criterion
measures and **raises the specular fraction** the specular criterion measures.
Both of those are criteria the quality gate acts on, so a protocol that put the
coin inside the region of interest would have the criteria penalising compliance
with the protocol.

The coin's value is on the deployment side, where the camera distance varies with
whoever holds the phone. It buys little for this dataset, whose rig distance is
fixed. It stays in the protocol because collection is irreversible and the cost
is a coin in the corner of the frame — but it does not on its own settle the scale
question, which ADR 0014 records as open.

### The paper template

For the `paper` condition, arrange the disc against the **90 mm template**.
Without one, its diameter is whatever the person judges by eye, which injects
scale variation into the dataset that is **neither constant nor recorded** —
worse than either a fixed size or a measured one. The template costs a printed
circle.

## 5. The manifest

One `manifest.csv` at the root of the version directory
(`ml/data/datasets/vN/`). It is the authoritative record of the dataset: the
files on disk are checked against it, not the other way round.

| Column | Meaning |
|---|---|
| `sample_id` | The code you assign. **Globally unique across the dataset** |
| `texture_class` | One of the five Embrapa groups, spelled exactly as `ml/config.yaml` spells it |
| `image` | Path relative to the version root, for example `images/A-1_dish.jpg` |
| `setting` | `dish` or `paper` |
| `site` | Where the sample was extracted from — the property or region, not where the photograph was taken |
| `device` | Capture device, make and model |
| `captured_at` | ISO 8601 date, `YYYY-MM-DD` |

Rules the validator enforces:

- **One identifier, one class.** The same `sample_id` under two `texture_class`
  values is a labelling error, not a naming coincidence, and it is rejected.
- **No granulometry columns.** `sand_pct`, `silt_pct`, `clay_pct` and
  `lab_report` are rejected rather than ignored. No granulometric value enters
  this process, and a column that were merely ignored would arrive quietly and
  then be read by something later.
- **No moisture column.** It cannot be recorded, and bench preparation makes it
  near-constant, so a column would collect either nothing or a guess.
- **Save as UTF-8 with comma separators.** A semicolon-delimited or Latin-1
  export is diagnosed by name, but it still has to be fixed before anything runs.

## 6. A dataset version never changes

`ml/data/datasets/vN/` is immutable. **Adding images creates `vN+1`; it never
mutates `vN`.** Every experiment records the version it used and a digest of the
manifest it read, so a split can be shown to belong to the data it claims. This
is the smallest thing that keeps "the model got worse" and "the dataset changed"
distinguishable.

## 7. Running the checks

From the `ml/` directory. Neither tool needs TensorFlow installed.

```bash
# 1. Which candidates pass the quality criteria. Reports only by default.
python scripts/admit_images.py --version v1

# 2. Same, but rewrite manifest.csv with the admitted rows and list the
#    refusals in admission-rejected.csv.
python scripts/admit_images.py --version v1 --write

# 3. Whether the version is usable: schema, disk agreement, pairing, splits.
python scripts/validate_dataset.py --version v1
```

What admission does with each verdict:

| Verdict | Outcome |
|---|---|
| `ok` | Admitted |
| `advisory` | **Admitted**, with its failing criteria recorded. A marginal photograph is representative of real conditions; excluding it would narrow the dataset to an unrepresentative subpopulation |
| `blocking` | Refused. Retake it |
| `unvalidated` | Refused. The analyzer could not measure the file, so no metrics could be recorded for it |

Every admitted image carries its seven measured metrics in the manifest, so if a
threshold is recalibrated later the decision can be recomputed without
re-photographing or re-reading anything.

**A refused image is moved, not deleted.** `--write` moves it into
`rejected/`, mirroring the path it had, and lists it in
`admission-rejected.csv`. It stays as the evidence for the refusal and as the
thing a retake is judged against, and the validator ignores that directory — so
the version admission just produced still validates. No row may declare a path
inside `rejected/`.

**A refusal can break a pair.** If one condition of a sample is refused, retake
that photograph before the version is finalised; the validator will report the
sample as unpaired until you do.

**Admission will not rewrite a version a split already claims.** Once
`validate_dataset.py --splits-dir …` has published a `splits.json` recording this
manifest's digest, rewriting the manifest would leave that split unverifiable
against anything. `--write` refuses in that case: collect into `vN+1`, which is
what §6 asks for anyway.

## 8. How many samples

Counts are of **samples**, not photographs. Each sample yields two photographs
and they count as one group.

| Milestone | Per class | What it is for |
|---|---|---|
| Feasibility floor | 30 | Enough for the go/no-go probe to separate a real model from a label-shuffled control |
| Programme target | 67 | Each class then holds at least 10 samples in the test set |

**The smallest class is the binding number, not the total.** A version with 100
of one class and 8 of another clears any average and cannot support a five-way
verdict, because the class most likely to be confused is the one with almost no
evidence. Silty soils are genuinely uncommon in much of the Brazilian soil
population, so a shortfall there is expected to be a property of the material
rather than of effort — report the per-class count and let the programme decide,
rather than photographing to hit an average.
