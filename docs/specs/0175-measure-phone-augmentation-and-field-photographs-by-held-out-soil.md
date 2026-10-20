# SPEC: feat(ml): measure phone-camera augmentation and field photographs by holding one soil out

## Problem

The released classifier reads every field photograph of 2026-10-19 as clay, scoring Media and Arenosa 0 of 24, and no preprocessing in the app corrected it, but the descriptor regression is fitted on archive photographs alone with no augmentation, and nothing measures whether a phone's look in training would carry it to the field.

## Design Decision

Augmentation acts on a photograph's region **at the canonical scale**, before the patch grid is cut, so it never changes how many millimetres a pixel covers. One augmented variant is a fixed, seeded draw of:

- brightness, contrast and gamma, each a factor in [0.85, 1.15];
- a white balance gain per channel in [0.93, 1.07];
- Gaussian noise with a standard deviation in [0, 4] grey levels;
- a JPEG recompression at a quality in [60, 95];
- either a Gaussian blur with sigma in [0, 0.8] px or an unsharp mask with amount in [0, 0.8];
- a quarter turn and a mirror, with the disc's centre moved with them.

Variants enter the probe as entries of their own, keyed `<path>::aug<k>`, so `_patch_matrix`'s cache never confuses a variant with its source.

A study, `python -m src.field_study --version v1 --field <export>`, fits the released procedure (`fit_probe` at the release's chosen `C`, read from `models/<version>/release/selection.json`) under four arms and scores them on the field export of SPEC 0174:

| Arm | Training side |
|---|---|
| A0 | the archive, as released |
| A1 | the archive and `k` phone variants of each archive photograph |
| A2 | A0, plus `k` variants of the field photographs of every soil sample but the held-out one |
| A3 | A1 and A2's field variants |

Each soil sample is held out in turn. It is scored on its own unaugmented photographs, by the app's aggregation (the mean of the patch probabilities), counting only photographs that were not upsampled, then again counting every photograph. A1 and A0 are also scored on the archive's own grouped folds (repeat 0 of the fold manifest), with augmentation on the training side only, so a loss on the archive is seen.

The report gives, per arm, the field accuracy macro-averaged over the four classes and per sample, the field confusion matrix, and the archive accuracy. It writes `models/<version>/field_study/report.json` and prints a table.

**The adoption rule is fixed before the run.** An arm is adoptable when:

1. its field macro accuracy beats A0's by at least 0.20; and
2. its archive accuracy is no more than 0.02 below A0's.

Of the adoptable arms, A1 is preferred over A2 and A3, because only A1 owes nothing to the five field soils. Adopting is a separate release spec, never this one.

## Alternatives Considered

- **Train on the field photographs and score on the same photographs.** Rejected by the Developer: the score would count soils the model has seen.
- **Augment the patches rather than the region.** Rejected: a quarter turn or a recompression of a 160 px patch is not what a phone does to a photograph, and the grid would be cut from different pixels than the variant's.
- **Augment with scale jitter.** Rejected: the descriptors are read at one canonical scale (ADR 0018), and changing the scale is what the too-coarse rule exists to prevent.
- **Choose `C` per arm by nested cross-validation.** Deferred: a study with five held-out soils would cost hours per arm to settle a parameter the release already chose. A release spec that adopts an arm re-selects `C` as `release_fit` does.

## Scope

- Includes:
  - `ml/src/phone_augment.py`: the seeded variant draw on a canonical RGB region, with the centre carried through the turn and the mirror.
  - `ml/src/field.py`: reading SPEC 0174's export and featurising its entries, plain or augmented, with `cut_patches`.
  - An archive featuriser that resamples, augments and then cuts, reusing `dataset._canonical_region`, `resample_to_canonical` and `cut_patches`.
  - `ml/src/field_study.py`: the arms, the held-out loop, the archive guard, the report and the CLI.
  - The study's two settings as command-line options, `--variants` (default 8) and `--seed` (default 20261019), not as a `config.yaml` section: `crossval.comparable_config` compares the whole configuration, so a new section would invalidate the reuse of every cross-validation run already on the other machine.
  - Tests in `ml/tests/` on synthetic regions and a synthetic archive (`tests/support.py`).
  - A `ml/README.md` section on running the study on the machine that holds the archive.
- Does NOT include:
  - Running the study, which needs the `v1` archive on the Developer's other machine.
  - Writing or deploying a new `spec.json`, or changing the released contract or `release.py`.
  - The CNN training path and its augmentation layer.
  - Any change to `ml/config.yaml`.
  - Any app change.

## Acceptance Criteria

- `a_variant_is_deterministic`: the same region, seed and `k` give byte-identical variants, and two `k` give different ones.
- `a_variant_keeps_the_scale`: a variant has the region's size, rotated with a quarter turn, and every photometric draw stays within its range.
- `the_centre_turns_with_the_region`: a disc centred at (y, x) in an H × W region is at (x, H − 1 − y) after a clockwise quarter turn and at (y, W − 1 − x) after a mirror.
- `variants_are_entries_of_their_own`: two variants of one photograph have distinct cache keys and both reach the training matrix.
- `the_held_out_soil_never_trains`: for every held-out sample, no training entry of A2 or A3, plain or augmented, comes from that sample.
- `scoring_uses_unaugmented_photographs`: the held-out side holds the sample's exported photographs once each, unaugmented.
- `upsampled_photographs_are_reported_apart`: the report gives field accuracy over non-upsampled photographs and over all of them.
- `the_archive_guard_trains_augmented_and_tests_plain`: in the archive guard, augmentation appears on the training side only.
- `c_is_the_releases`: the study fits at `selection.json`'s `chosen_c`, and a missing file fails with a message naming the release command.
- `the_adoption_rule_is_applied_as_written`: on synthetic accuracies, an arm 0.20 over A0 in the field and 0.02 under it on the archive is adoptable, and one 0.19 over, or 0.021 under, is not.
- `the_study_runs_end_to_end`: on a synthetic archive of two classes and a synthetic field export of three samples, the CLI writes a report with all four arms and every held-out sample.

## Reproducibility

```sh
cd ml && python -m pytest tests/ -q
cd ml && python -m src.field_study --version v1 --field <export dir>
```

Python 3.12, the pins in `ml/requirements.txt`, and the seed given by `--seed`. The study is deterministic for a given archive, export and seed.

## Risks and Assumptions

- Assumption: SPEC 0174's export is cut by Python exactly as the app cuts it (the patch goldens hold the two grids together).
- Risk: five soils, two of them Argilosa, make every field figure coarse: one sample is 20 % of the macro score. The report names the samples, and the rule's 0.20 margin is set at one sample's weight for that reason.
- Risk: augmentation could make the archive classes harder to tell apart. The archive guard measures this, and its 0.02 bound is the rule's second half.
- What would invalidate this spec: a field export whose patches differ from the app's, or an arm adopted on a run that broke the held-out rule.
