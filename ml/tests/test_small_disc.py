"""Acceptance criteria for the small-disc study (SPEC 0141).

Each test name matches a criterion in
`docs/specs/0141-classify-a-soil-patch-too-small-for-nine.md`.

The study refits the released descriptor arm's folds and scores each held-out
photograph from its full grid, from the centred five and from the half-stride
four. Its rules are pure and tested here on hand-made records; the one test that
refits a real fold is gated on the archive, and the guard it relies on is tested
without it.
"""

import copy
import json
from pathlib import Path

import pytest

from src.config import load_config
from src.patches import patch_geometry
from src.small_disc import (
    MAX_MACRO_F1_DROP,
    MIN_AGREEMENT,
    PATCH_SETS,
    decide_floor,
    require_reproduction,
    rescore_fold,
    set_verdict,
    simulated_measurement,
    study_config,
    top1_agreement,
)

ML_ROOT = Path(__file__).resolve().parents[1]
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"
RELEASED_ARM = ML_ROOT / "models" / "v1" / "descriptors"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file()
    or not (RELEASED_ARM / "repeat-0" / "fold-0" / "predictions.json").is_file(),
    reason="the ingested dataset and the released arm's folds are absent; both are git-ignored",
)


def _record(path, probabilities, label=0):
    return {"path": path, "group": f"g::{path}", "label": label, "probabilities": probabilities}


# --- the patch sets ------------------------------------------------------------


def test_a_simulated_disc_cuts_the_patch_set_it_names():
    cfg = load_config()
    study = study_config(cfg)
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    measurement = {
        "mm_per_px": 0.11,
        "disc_centre_y_px": 1000.0,
        "disc_centre_x_px": 900.0,
        "disc_diameter_px": 818.0,
    }
    before = copy.deepcopy(measurement)
    expected = {
        "five": ((-80.0, 0.0), (0.0, -80.0), (0.0, 0.0), (0.0, 80.0), (80.0, 0.0)),
        "four": ((-40.0, -40.0), (-40.0, 40.0), (40.0, -40.0), (40.0, 40.0)),
    }

    for name, offsets in expected.items():
        simulated = simulated_measurement(measurement, PATCH_SETS[name])
        # Only the diameter moves: the scale and the centre are the dish's own.
        assert {k: v for k, v in simulated.items() if k != "disc_diameter_px"} == {
            k: v for k, v in measurement.items() if k != "disc_diameter_px"
        }
        geometry = patch_geometry(
            region_diameter_px=simulated["disc_diameter_px"] * measurement["mm_per_px"] / canonical,
            input_size=study["data"]["image_size"],
            canonical_mm_per_px=canonical,
            min_patches=study["preprocessing"]["min_patches"],
            stride_fraction=study["preprocessing"]["patch_stride_fraction"],
        )
        assert geometry.offsets == offsets, name
    assert measurement == before


def test_the_study_cuts_at_a_floor_of_four_and_changes_nothing_else():
    cfg = load_config()
    study = study_config(cfg)

    assert study["preprocessing"]["min_patches"] == 4
    study["preprocessing"]["min_patches"] = cfg["preprocessing"]["min_patches"]
    assert study == cfg


# --- the criteria, fixed before the run ---------------------------------------------


def test_a_patch_set_passes_only_inside_both_margins():
    assert MAX_MACRO_F1_DROP == 0.02
    assert MIN_AGREEMENT == 0.90

    assert set_verdict(full_median=0.62, set_median=0.605, agreement=0.95)["passes"]
    # Better than the full grid is not a loss.
    assert set_verdict(full_median=0.62, set_median=0.64, agreement=0.95)["passes"]
    # Exactly at the agreement floor passes; just under it does not.
    assert set_verdict(full_median=0.62, set_median=0.62, agreement=45 / 50)["passes"]
    assert not set_verdict(full_median=0.62, set_median=0.62, agreement=44 / 50)["passes"]
    # A macro-F1 loss over the margin fails whatever the agreement.
    assert not set_verdict(full_median=0.62, set_median=0.598, agreement=1.0)["passes"]


def test_the_decision_table_is_the_specs():
    assert decide_floor(five_passes=True, four_passes=True) == 4
    assert decide_floor(five_passes=True, four_passes=False) == 5
    assert decide_floor(five_passes=False, four_passes=True) == 9
    assert decide_floor(five_passes=False, four_passes=False) == 9


def test_agreement_is_pooled_over_every_fold():
    full = {
        (0, 0): [_record("a", [0.6, 0.4, 0.0, 0.0]), _record("b", [0.1, 0.9, 0.0, 0.0])],
        (0, 1): [_record("c", [0.2, 0.2, 0.6, 0.0])],
    }
    other = {
        # Order within a fold does not matter; the path pairs the records.
        (0, 0): [_record("b", [0.2, 0.8, 0.0, 0.0]), _record("a", [0.3, 0.7, 0.0, 0.0])],
        (0, 1): [_record("c", [0.1, 0.1, 0.7, 0.1])],
    }

    assert top1_agreement(full, other) == pytest.approx(2 / 3)


# --- reproducing the released arm ------------------------------------------------------


def test_the_study_reproduces_the_released_arm_or_stops():
    stored = {(0, 0): [_record("a", [0.25, 0.25, 0.25, 0.25]), _record("b", [0.7, 0.1, 0.1, 0.1])]}

    require_reproduction(copy.deepcopy(stored), stored)

    drifted = copy.deepcopy(stored)
    drifted[(0, 0)][1]["probabilities"][0] += 1e-8
    with pytest.raises(ValueError, match="not the released arm"):
        require_reproduction(drifted, stored)

    missing = {(0, 0): stored[(0, 0)][:1]}
    with pytest.raises(ValueError, match="not the released arm"):
        require_reproduction(missing, stored)


@real_only
def test_the_study_reproduces_the_released_arm_on_one_fold():
    from src.config import resolve_paths
    from src.dataset import load_folds_for_config

    cfg = resolve_paths(load_config())
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])

    scored = rescore_fold(cfg, fold_manifest, RELEASED_ARM, repeat=0, fold=0)

    stored = json.loads(
        (RELEASED_ARM / "repeat-0" / "fold-0" / "predictions.json").read_text(encoding="utf-8")
    )["predictions"]
    require_reproduction({(0, 0): scored["full"]}, {(0, 0): stored})
    assert {len(scored[name]) for name in ("full", "five", "four")} == {len(stored)}
