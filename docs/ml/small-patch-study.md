# A nine-patch grid at 128 px, on the cross-validated folds

[SPEC 0143](../specs/0143-study-a-nine-patch-grid-on-small-soil-discs.md)
asks whether smaller descriptor patches can preserve the nine-patch floor on a
47.2 mm soil disc. At the released scale of 0.12920342774728033 mm/px and the
unchanged half-patch stride, nine centred 128 px patches fit that disc. The
released 160 px geometry does not.

The comparison reuses the released `descriptors` arm's exact 25 outer folds on
`v1`: five repeats of five grouped folds, seed 42. The candidate extracts only
the nine central 128 px patches from every archive photograph. Inside each
outer training side it selects the logistic probe's regularisation strength,
then fits the final standardiser and probe without reading the held-out groups.
The baseline numbers are reproduced from its stored predictions and paired by
repeat, fold, and photograph.

## The answer

**The 128 px candidate fails the registered margin, so it must not replace the
released procedure.** The rule was fixed before the run: the candidate passes
only when its median photograph macro-F1 is no more than 0.02 below the
baseline median.

| | Photograph macro-F1, median (range) | Drop | Group macro-F1, median (range) | Top-1 agreement | Verdict |
|---|---:|---:|---:|---:|---|
| released 160 px full grid | 0.6232 (0.6108-0.6384) | - | 0.6219 (0.5915-0.6920) | - | baseline |
| 128 px, nine patches, 47.2 mm | 0.5781 (0.5597-0.6022) | 0.0451 | 0.6065 (0.5861-0.6570) | 0.8060 | fails |

The candidate's photograph macro-F1 by repeat was 0.5668, 0.5825, 0.5781,
0.6022, and 0.5597. Its selected C values were 0.1 twice, 1 six times, 10
eleven times, and 100 six times across the 25 outer folds.

Per-class F1 is diagnostic because each fold has few groups per class:

| Class | Baseline photograph F1 | Candidate photograph F1 | Baseline group F1 | Candidate group F1 |
|---|---:|---:|---:|---:|
| Arenosa | 0.8362 | 0.8097 | 0.7946 | 0.7818 |
| Media | 0.5014 | 0.4603 | 0.5056 | 0.5193 |
| Muito Argilosa | 0.7669 | 0.7162 | 0.7807 | 0.7577 |
| Argilosa | 0.3893 | 0.3259 | 0.4429 | 0.3944 |

## What it decides

- The app keeps the released 160 px model and the nine-patch floor.
- A 128 px contract is not released. No app, model contract, capture flow, or
  A4 reader file changes under this study.
- Smaller patches do not solve the supplied photographs within the accepted
  quality margin. The practical next step remains capturing an 8-10 cm soil
  patch as the onboarding requests.
- The result says nothing about the seven supplied photographs where the A4
  sheet was not detected completely. It also does not validate dish-trained
  descriptors on paper-backed field samples.

## Reproducing it

```sh
cd ml
python -m pytest tests/test_small_patch_study.py -q
python -m src.small_patch_study --version v1
```

The measured run used Python 3.12.13, NumPy 1.26.4, scikit-learn 1.5.2,
TensorFlow 2.21.0, and Keras 3.14.0 on CPU with deterministic operations. It
writes the ignored result to
`models/v1/descriptors_128px_small_disc/small_patch_study.json`. It requires
the local `v1` archive and the released arm's 25 local fold artifacts. The
candidate run recorded 125 training units: 100 inner selection passes and 25
refits, comprising 525 fitted probes. It reported 154.326 seconds for those
units; descriptor extraction is cached across folds within the process.
