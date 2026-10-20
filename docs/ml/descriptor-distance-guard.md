# A descriptor-distance guard against the excluded Siltosa: 2026-10-20

SPEC 0176 asked whether a distance in the contract's descriptor space could tell the Siltosa samples, which ADR 0016 keeps out of the model, apart from the soils the model was fitted on. The answer would decide whether `ClassificationOutcome.rejectedOod` gets a producer. This document records the run on `v1`.

## The answer

**No. The guard does not catch Siltosa, and it should not be wired.** It refuses none of the six Siltosa photographs. The AUROC of Siltosa against held-out soil is 0.145, far below chance: Siltosa sits *closer* to the class centroids than most of the soils the model was fitted on. Four of the six score below the archive's 6th percentile.

Both conditions SPEC 0176 fixed before the run fail, so the field condition was not measured and does not need to be. `rejectedOod` keeps having no producer.

## The run

From `python -m src.ood_study --version v1` with SPEC 0176's implementation. The archive is the 221 photographs of `v1`. The held-out side is the 167 photographs that are splittable, cut by the patch grid and not in population `B`. Each is scored by the repeat-0 fold that held it out. Each Siltosa photograph is scored by all five folds' fits, and its score is their mean.

**Threshold:** 1.588, the 0.99 quantile of the held-out soil scores.

| Set | Photographs | Refused | Rate |
|---|---|---|---|
| Held-out soil | 167 | 2 | 0.012 |
| Arenosa | 56 | 1 | 0.018 |
| Argilosa | 30 | 0 | 0.000 |
| Media | 39 | 1 | 0.026 |
| Muito Argilosa | 42 | 0 | 0.000 |
| Siltosa | 6 | 0 | 0.000 |

Held-out soil scores have a median of 0.772 (quartiles 0.652 and 0.929, maximum 1.607). The Siltosa photographs:

| Sample | Score | Held-out soil below it |
|---|---|---|
| 111930-33 | 0.652 | 25 % |
| 111930-33 | 0.792 | 53 % |
| 115158-2 | 0.485 | 5 % |
| 115158-2 | 0.422 | 2 % |
| 116201-8 | 0.428 | 2 % |
| 116201-8 | 0.380 | 0 % |

**AUROC**, Siltosa against held-out soil: 0.145.

| Condition | Required | Measured | Holds |
|---|---|---|---|
| Siltosa refused at the threshold | at least 4 of 6 | 0 of 6 | no |
| AUROC | at least 0.80 | 0.145 | no |
| Field refusal at the threshold | at most 0.10 | not measured | open |

## Why it fails

The camera cannot see silt. One canonical pixel is 0.129 mm, and silt grains are 0.002 to 0.05 mm, so a patch shows colour, clods and roughness, not grain size. On those, a silty soil is an ordinary soil, between sand and clay, which is where the four class centroids sit. A distance to the nearest centroid is smallest exactly there. Two of the three Siltosa samples score lower than almost every held-out soil.

That points at the space rather than at the guard's form. A full covariance, the deferred alternative, reshapes the distance, and kNN measures nearness to training patches instead of centroids, but both measure in the same descriptors. Neither was run, and with Siltosa nearer than most soils under this distance, nothing here suggests either would find it far. Catching Siltosa needs a feature that sees grain size, which a photograph at this scale does not have.

## What it leaves

- #194's question is answered for Siltosa: the guard is not worth wiring. A Siltosa sample keeps receiving one of the four classes, and that limitation is stated, not detected.
- A guard against inputs that are not soil at all remains a separate question. It would need a set of such inputs, and any of them would first have to pass the A4-sheet reader.
- `models/v1/ood_study/report.json` holds every photograph's score, for a later study that scores the field export (`--field`).
