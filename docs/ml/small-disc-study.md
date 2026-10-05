# What a soil disc too small for nine patches costs, on the cross-validated folds

[SPEC 0141](../specs/0141-classify-a-soil-patch-too-small-for-nine.md) asks
whether a photograph could be classified from fewer than nine patches without
losing quality. The first real photographs carry a soil disc of 46.5 to 51.4 mm
([the check](sheet-reader-real-photographs.md)), and the floor of nine needs
58.5 mm. Below it, a disc holds the centred five (from 49.9 mm) or a half-stride
block of four (from 43.9 mm).

The study reuses the released `descriptors` arm's cross-validation on `v1`: five
repeats of five folds, seed 42 (ADR 0020). For each fold it refits the probe on
the training side's full grids, at the C that fold's selection chose, and scores
each held-out photograph three ways:

- **full**: its own grid, 25 patches on the archive's 90 mm dish;
- **five**: the centred grid of a 51.0 mm disc, the centre patch and the four
  at ±80 px;
- **four**: the half-stride grid of a 47.5 mm disc, the 2 × 2 block at
  (±40, ±40) px.

The small grids are cut by the training cut, around each dish's measured centre,
with only the disc diameter replaced. Each repeat scores 167 photographs over
77 groups. Nothing is retrained and nothing is released.

## The answer

**Both small sets lose quality, so the floor stays at nine and ADR 0027 is
withdrawn.** The criteria were fixed in the spec before the run: a set passes
when its median photograph macro-F1 is at most 0.02 below the full grid's, and
when at least 90 % of the held-out predictions keep the full grid's top class.

| | Photograph macro-F1, median (range) | Drop | Top-1 agreement | Verdict |
|---|---:|---:|---:|---|
| full | 0.6232 (0.6108–0.6384) | — | — | reproduces the released arm |
| five, 51.0 mm | 0.5758 (0.5630–0.5810) | 0.047 | 0.842 | fails both |
| four, 47.5 mm | 0.5639 (0.5543–0.5986) | 0.059 | 0.811 | fails both |

By the spec's decision table, a failing five keeps the floor of nine whatever
four does. The group macro-F1 tells the same story: 0.6219 for the full grid,
0.5900 for five and 0.5555 for four.

## How to read it

- **The loss is not noise.** Every repeat of five scores below every repeat of
  the full grid, and so does every repeat of four. Within each repeat, five
  loses 0.035 to 0.062 and four loses 0.021 to 0.081, so no repeat would have
  passed on its own.
- **16 % and 19 % of readings change class.** Of the 835 held-out
  predictions, the full grid's top class is kept by 703 under five and by 677
  under four. Those are readings a user would see change, not a shift in
  confidence.
- **The full grid is the released arm.** Its distributions equal the stored
  `predictions.json` within 1e-9 on all 25 folds, so the figures above describe
  the model the app ships. The folds chose C = 10 eleven times, C = 1 eight
  times, C = 0.1 four times and C = 100 twice.
- **Dish photographs, not sheet ones.** The small grids come from the middle of
  a 90 mm dish, where the soil is spread evenly. A real 50 mm patch may be
  thinner at its rim, which this study cannot see.

## What it decides

- **The floor stays at nine**, as ADR 0018 set it, and the grid stays centred.
  The half-stride grid is not in `ml/src/patches.py` or in the Dart cutter; the
  study holds its own copy, `small_disc.half_stride_offsets`.
- **The remedy is a bigger soil patch.** Nine patches need a disc of 58.5 mm.
  The reader keeps 2 mm inside the soil's edge, so that is a round patch of
  about 6.3 cm. The onboarding already asks for 8 to 10 cm, and the 2026-10-05
  session still produced about 5 cm. The capture screen saying so is the next
  change.

## Reproducing it

```sh
cd ml
python -m src.crossval --version v1 --arm descriptors   # about 35 min, if the folds are absent
python -m src.small_disc --version v1
```

The study takes about ten minutes and writes
`models/v1/descriptors/small_disc_study.json`. It needs the archive at
`ml/data/archive` and the arm's fold artifacts, which are both git-ignored. The
figures above come from Python 3.12 with `ml/requirements.txt`.
