# SPEC: feat(inference): classify a soil patch too small for nine

## Problem

The app refuses every real photograph whose sheet it finds, because the soil disc on them (46.5 to 51.4 mm) holds fewer than the nine patches the grid demands, and nine is a floor set for a dispersion measure the app does not compute.

The reader now finds the A4 sheet on 24 of the 31 photographs taken on 2026-10-05 (SPEC 0140). On every one of them, classification stops at `soilRegionTooSmall`. The soil was moulded into a round patch of about 54 mm. After the reader's 2 mm margin, the largest disc inside it measures 46.5 to 51.4 mm.

The grid is fixed in millimetres: a patch is 160 px at the canonical 0.1292 mm/px (20.7 mm), the stride is half a patch, and every patch must lie inside the disc. Nine patches need a disc of 58.5 mm. On these photographs, a disc of 49.9 mm or more holds five patches (15 photographs), and a smaller one holds one (9 photographs).

ADR 0018 set the floor at nine for one reason: the spread of the patch predictions is reported as an eighth quality criterion, and an entropy over fewer than nine patches is too coarse to warn with. `ml/config.yaml` says the same in its own words: "a mean over four patches is usable". Nothing in `lib/` computes that dispersion today. So the floor refuses photographs for a measure that is not taken.

## Design Decision

The scale, the patch size, the stride, the 2 mm soil margin and every refusal stay exactly as they are. Two things change, and the second ships only if an archive study shows that it costs no quality.

**1. The grid may shift by half a stride when the centred grid falls short.** Today the grid is centred on the disc: its patch centres sit at whole multiples of the stride from the disc centre. A second grid is the same lattice moved by half a stride on both axes, so its centres sit at (±40, ±40), (±40, ±120), … px. The rule:

- Use the centred grid when it holds at least `min_patches`.
- Otherwise, use the half-stride grid when it holds at least `min_patches`.
- Otherwise, refuse as `soilRegionTooSmall`, as today.

With today's floor of nine, the half-stride grid never wins, because it holds 4 patches up to a 61.9 mm disc and the centred grid holds 9 from 58.5 mm. So the rule changes nothing until the floor changes: the archive's grids, the training and every committed golden stay byte-identical. With a floor of four, it reaches a disc of 43.9 to 49.9 mm, where the centred grid holds 1 and the half-stride grid holds a 2 × 2 block of 4.

Python's `patch_geometry` and Dart's `patchGeometry` carry the same rule, and the committed goldens pin them to each other, as they do today.

**2. The classification floor drops from 9 to 4, if the study allows it.** The floor is `geometry.min_patches` in the contract, and it comes from `preprocessing.min_patches` in `ml/config.yaml`. Every archive photograph already holds at least nine patches, because the dataset build refuses one that does not. So lowering the floor changes no training input. The contract is re-released as model version `1.1.0` with the same weights. Records saved under it carry `1.1.0` (SPEC 0097), so a reading taken on a smaller disc can be told apart.

The dispersion measure keeps its own floor of nine. When it is wired, it is computed only over nine patches or more. Below nine, a photograph is classified with no dispersion warning, which is the state every photograph is in today. ADR 0027 records this amendment of ADR 0018.

**The study decides the floor, and its criteria are fixed here, before it runs.** It reuses the released descriptor arm's cross-validation (repeated stratified group k-fold, k = 5, 5 repeats, seed 42; ADR 0020) on dataset `v1`. No new data and no new labels are used.

The steps:

1. For each of the 25 folds, refit the probe on the training side's full grids, at the C its selection audit chose.
2. Score each held-out photograph three ways, through the same cutter the training uses, with a disc diameter put in place of the measured one:
   - **full**: its own grid (25 patches on the archive's 90 mm dish);
   - **five**: the centred grid of a 51.0 mm disc, which is the centre patch and the four at ±80 px;
   - **four**: the half-stride grid of a 47.5 mm disc, which is the 2 × 2 block at (±40, ±40).

   Any disc from 49.9 to 58.5 mm gives the same five patches, and any disc from 43.9 to 49.9 mm gives the same four, so these two diameters stand for every photograph in this session.
3. Average each photograph's patch distributions, and compute the headline metrics with `evaluate.arm_metrics`, as the released run did.

Sanity check: the **full** distributions must equal the stored `predictions.json` within 1e-9. If they do not, the study is not measuring the released arm, and it stops there.

For each of **five** and **four**, two criteria must both hold:

- **Macro-F1.** The median over repeats of the photograph macro-F1 is at most 0.02 below the **full** median. The released median is 0.6232, and its repeats range over 0.028.
- **Agreement.** At least 90 % of the held-out predictions keep the same top class as **full**. The predictions are pooled over all 25 folds, so each photograph counts five times.

What ships depends on the result:

| **five** | **four** | What ships |
|---|---|---|
| passes | passes | Floor 4, with the half-stride grid. All 24 photographs classify. |
| passes | fails | Floor 5, and the half-stride grid is removed from the branch. 15 of the 24 photographs classify. |
| fails | either | Floor 9 is kept, and only the study and its record ship. |

The study's code, its command and its numbers are committed, whatever the result.

## Alternatives Considered

- **Keep the floor, and only ask for a bigger patch on the capture screen.** Rejected as the whole answer. The onboarding already asks for 8 to 10 cm, and the session still produced 5 cm patches. A floor that refuses for a measure nobody computes turns a usable photograph into a retake. The guide stays as it is, because more patches are still better.
- **Halve the stride, to 40 px, so a 50 mm disc holds 13 patches.** Rejected. Those patches cover the same soil as the five at today's stride, so the floor would pass without a single new millimetre of evidence. That is the floor being gamed rather than met. It would also change the training geometry.
- **A smaller soil margin.** Rejected. One millimetre less adds 2 mm to the disc, which takes 160647 (49.6 mm) to five patches and leaves the eight photographs at 46.5 to 47.8 mm on one. The margin exists to keep the paper's edge and the patch rim out of the patches.
- **Always use whichever grid holds more patches.** Rejected. On the archive's 90 mm dish, the half-stride grid holds 32 against the centred grid's 25, so this rule would move every training patch. The rule above uses the half-stride grid only where the centred grid falls short of the floor.
- **Lower the floor with no study.** Rejected. "Without losing quality" has to be measured, and the archive is the only labelled data. The real photographs carry no labels.
- **Smaller patches, or retraining.** Out of scope. A different patch size is a different model, and the dataset is closed at 105 samples.

## Scope

- Includes:
  - **Grid rule:**
    - `ml/src/patches.py`: the half-stride grid in `patch_geometry`, with its tests in `ml/tests/test_patches.py`.
    - `lib/core/services/descriptors/patch_grid.dart`: the same rule in `patchGeometry`, with its tests in `test/services/patch_grid_test.dart`.
    - New cases appended to `ml/scripts/generate_patch_golden.py` and `ml/scripts/generate_patch_geometry.py`, and the regenerated `test/fixtures/patches/golden.json` and `test/fixtures/patch_geometry/geometry.json`. Every earlier entry stays byte-identical.
  - **Study:**
    - `ml/src/small_disc.py`, its tests in `ml/tests/test_small_disc.py`, and its record `docs/ml/small-disc-study.md`.
  - **ADR 0027**, promoted at the Gate and conditional on the study. If the centred five fails, it is marked `Withdrawn` in place.
  - **If the study passes:**
    - `preprocessing.min_patches` in `ml/config.yaml`, and its default in `ml/src/config.py` and `ml/src/patches.py`.
    - The re-released `assets/models/spec.json`, at model version `1.1.0`.
    - The README's Engineering Decisions row for ADR 0027.
    - `test/services/small_soil_patch_test.dart`, with two real photographs in `test/fixtures/sheet_photos/native/`. They are reduced to 0.12 mm/px and stripped of EXIF, about 0.5 MB each:
      - 160706, a 51.4 mm disc, which holds five patches;
      - 160908, a 47.2 mm disc, which holds four.
    - The check document `docs/ml/sheet-reader-real-photographs.md`, the README, `docs/agents/project.md` (and the generated `CLAUDE.md`), and `docs/architecture/ml-implementation-map.md`, each updated to say what classifies now.
- Does NOT include:
  - The patch size, the stride, the canonical scale, the 2 mm soil margin, or the sheet reader. The false edge on 160808 and 160808_1 is the next spec.
  - The dispersion measure itself, `ClassificationVerdict`, or `ImageQualityAnalyzer`. They stay unwired.
  - Retraining, or any change to the probe's weights, features or dataset.
  - The capture screen, onboarding copy, and any user-facing text.
  - Accuracy on the real photographs. They have no labels, so the study on the archive is the quality evidence.

## Acceptance Criteria

- `the_half_stride_grid_fills_a_small_disc` (Python and Dart): with a floor of 4, a disc of 47.5 mm gives four patches at (±40, ±40) px, and a disc of 51.0 mm gives the centred five.
- `a_disc_below_the_half_stride_block_is_refused` (Python and Dart): with a floor of 4, a disc of 43.5 mm is refused as `region_too_small_for_the_patch_floor` (`soilRegionTooSmall` in Dart).
- `the_floor_of_nine_never_reaches_the_half_stride_grid`: for every disc from 40 to 100 mm in 0.1 mm steps, the geometry at a floor of 9 equals today's centred-only geometry, or is refused where today's is refused.
- The patch and geometry goldens regenerate. Every entry that existed before is byte-identical, and the Dart parity tests pass on the new entries.
- `the_study_reproduces_the_released_arm`: the **full** distributions equal the stored predictions within 1e-9. The study's criteria and verdict are recorded in `docs/ml/small-disc-study.md`, with the command that produced them.
- If the study passes:
  - The re-released `spec.json` differs from today's only in `model_version` and `geometry.min_patches`.
  - `a_small_real_soil_patch_is_classified`: 160706 classifies from five centred patches, and 160908 from four half-stride patches. Each outcome is a success, with a distribution over the four classes. This fails on today's `main`, which refuses both as `soilRegionTooSmall`.
  - Every earlier test in `test/services/inference_service_test.dart`, `test/services/patch_grid_test.dart` and `ml/tests/test_patches.py` passes unchanged.

## Reproducibility

```sh
cd ml && python -m pytest tests/test_patches.py tests/test_small_disc.py tests/test_patch_golden.py -q
cd ml && python -m src.small_disc --version v1
cd ml && python -m src.release --version v1 --model-version 1.1.0 && bash scripts/deploy_to_app.sh v1
flutter test test/services/patch_grid_test.dart test/services/small_soil_patch_test.dart
flutter analyze && flutter test && mf check
```

The study needs the archive at `ml/data/archive` and the released arm's fold artifacts under `ml/models/v1/descriptors/`. Both are local and git-ignored. Python 3.12 with `ml/requirements.txt`, Flutter 3.44.1, and Dart 3.12.1.

## Risks and Assumptions

- **Risk: the central 31 mm of a 90 mm dish is not a 50 mm patch.** The study cuts the small grids from the middle of the archive's dishes, where the soil is evenly spread. A field patch of 50 mm may be thinner at its rim. The 2 mm margin and the patch inset keep the rim out of every patch, but the soil's thickness is not measured.
- **Risk: a mean over four patches is noisier.** That is the cost the study measures. A margin of 0.02 sits inside the spread between repeats (0.028), so a real loss smaller than the run-to-run noise would pass. That is the limit of what 105 samples can resolve.
- **Risk: a reading from 4 patches looks as sure as one from 25.** The screen shows the same confidence. Until the dispersion measure is wired, nothing tells the two apart. The record's `model_version` (`1.1.0`) and the stored distribution are what a later audit can use.
- **Assumption: the study's 25 folds stand for the field.** They are the archive's dish photographs, the same population the released metrics come from. Real photographs remain unlabelled, and accuracy on them is still owed before the Play release (ADR 0026).
- **What would invalidate this spec:** a study that fails both criteria. The floor then stays at nine, and the remedy is the capture protocol: a soil patch of at least 6 cm.
