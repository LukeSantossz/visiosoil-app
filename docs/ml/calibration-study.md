# A temperature and conformal verdict bands, on the cross-validated predictions

The study [SPEC 0098](../specs/0098-study-a-temperature-and-conformal-verdict-bands.md)
specifies, and the E15 experiment #193 asks for. It reads the `descriptors`
arm's stored predictions on `v1`, the same run SPEC 0095 measured, and answers
two questions with numbers. Would a temperature correct the calibration? How do
split-conformal verdict bands compare with ADR 0011's hand-set constants? It
publishes nothing: no contract field, no band constant, no app change.

Every fitted quantity is cross-fitted. Within each of the five repeats, the
temperature, the conformal thresholds and the matched level applied to a fold
are fitted on the other four folds, which share no sample group with it. Each
repeat scores 167 photographs over 77 groups. Each fold is fitted on about 134
photographs. Figures are medians across repeats, with ranges where they matter.

## The answer

**A temperature does not help, so none should be published on these numbers.**
The fit that maximises the likelihood barely moves the calibration error, and
it would make the verdicts bolder and less accurate:

| | Raw | Scaled |
|---|---:|---:|
| Expected calibration error, 10 bins | 0.074 | 0.075 |
| ADR 0011 `conclusive` share | 0.665 | 0.707 |
| Accuracy of the `conclusive` photographs | 0.783 | 0.762 |
| ADR 0011 coverage | 0.826 | 0.808 |

The cross-fitted temperatures have a median of 0.90, ranging from 0.63 to 1.00
across folds. The single temperature fitted on every out-of-fold prediction is
0.87. That is a mild sharpening, yet the underconfidence SPEC 0095 found is
5 to 8 points. The likely reason is that the likelihood is dominated by
confident errors, which sharpening punishes, so one global temperature cannot
remove a gap that is not a uniform scale. This study does not isolate the cause.

**At the incumbent's coverage, conformal bands assert as accurately and leave
far fewer photographs without an answer.** ADR 0011's constants cover the true
class 82.6 % of the time. Conformal sets fitted to the same coverage give:

| At coverage 0.83 | ADR 0011 constants | Conformal, matched |
|---|---:|---:|
| `conclusive` share | 0.665 | 0.587 |
| `ambiguous` share | 0.198 | 0.371 |
| `insufficient` share | 0.150 | 0.042 |
| Accuracy of the `conclusive` photographs | 0.783 | 0.786 |
| Mean classes asserted | 1.63 | 1.46 |

- **Conformal turns most `insufficient` verdicts into named pairs.** Of every
  hundred photographs, about eleven that the constants leave unanswered come
  out of conformal as `ambiguous` between two classes. That is the outcome
  ADR 0011 built the `ambiguous` state for.
- **The constants call more photographs `conclusive`**, 67 against 59 in a
  hundred, at the same accuracy. The constants trade unanswered photographs for
  extra assertions; conformal trades them for pairs.
- **The matched level varies by fold** from α = 0.12 to 0.23, because the
  constants' coverage is itself a property of the predictions, not a chosen
  level.

**The coverage conformal promises is the coverage it delivers:**

| α | Coverage | Mean set size | `conclusive` | `ambiguous` | `insufficient` | `conclusive` accuracy |
|---:|---:|---:|---:|---:|---:|---:|
| 0.05 | 0.958 | 2.41 | 0.192 | 0.275 | 0.521 | 0.875 |
| 0.10 | 0.898 | 1.82 | 0.365 | 0.437 | 0.192 | 0.870 |
| 0.15 | 0.856 | 1.57 | 0.485 | 0.431 | 0.054 | 0.827 |
| 0.20 | 0.802 | 1.37 | 0.647 | 0.323 | 0.024 | 0.761 |

Choosing α is choosing between those rows. A smaller α makes a `conclusive`
verdict more trustworthy, rising to 0.87 at α = 0.10, and makes it rarer, at 37
in a hundred.

## How to read it

- **Dish photographs, not sheet ones.** Every number describes the archive.
  What carries over to the A4-sheet photographs is the procedure. The thresholds
  and the matched level would be refitted on sheet photographs, which SPEC 0097
  now keeps the distribution of.
- **The guarantee is approximate.** The calibration scores come from the other
  folds' models (cross-conformal), and photographs of one sample stay in one
  fold. The empirical coverage is within a point of the nominal level at every
  α, so the approximation costs little here.
- **Empty sets are rare.** Pooled over the repeats, a set admitting no class
  came out:
  - for none of the photographs at α = 0.05 and 0.10;
  - for 0.1 % of them at α = 0.15;
  - for 0.6 % of them at α = 0.20.

  So `insufficient` mostly means three or four classes in contention. An empty
  set is the candidate signal #193 names for the reserved `rejectedOod`, and on
  dish photographs it is almost never raised.
- **What this does not decide.** Adopting conformal bands changes what
  ADR 0011's numbers mean, which is an amendment to it, and α is the
  Developer's choice of trade-off. Both wait for the sheet photographs, as the
  temperature did in SPEC 0095.

## Reproducing it

```sh
cd ml
python -m src.crossval --version v1 --arm descriptors   # about 35 min, if the predictions are absent
python -m src.calibration_study --version v1 --arm descriptors
```

The study takes a few seconds and writes
`models/v1/descriptors/calibration_study.json`.
