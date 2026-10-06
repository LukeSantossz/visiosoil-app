"""Acceptance tests for the 128 px small-disc study (SPEC 0143)."""

import copy
import importlib
import importlib.util
from pathlib import Path

import numpy as np
import pytest

from src.config import load_config, resolve_paths
from src.dataset import fold_split, load_folds_for_config
from src.patches import patch_geometry
from src.small_disc import simulated_measurement


ML_ROOT = Path(__file__).resolve().parents[1]
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested dataset is absent; it is git-ignored",
)


def _study():
    assert importlib.util.find_spec("src.small_patch_study") is not None, "study module missing"
    return importlib.import_module("src.small_patch_study")


def test_a_47_2_mm_disc_holds_nine_128_px_patches():
    study = _study()
    cfg = study.study_config(load_config())
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    stride = cfg["preprocessing"]["patch_stride_fraction"]

    geometry = patch_geometry(
        study.DISC_MM / canonical, study.PATCH_PX, canonical, stride_fraction=stride
    )
    assert len(geometry.offsets) == 9
    with pytest.raises(ValueError, match="region_too_small_for_the_patch_floor"):
        patch_geometry(
            46.5 / canonical, study.PATCH_PX, canonical, stride_fraction=stride
        )
    for disc_mm in (study.DISC_MM, 46.5):
        with pytest.raises(ValueError, match="region_too_small_for_the_patch_floor"):
            patch_geometry(
                disc_mm / canonical, 160, canonical, stride_fraction=stride
            )


def test_the_candidate_changes_only_patch_size_and_disc_footprint():
    study = _study()
    cfg = load_config()
    before = copy.deepcopy(cfg)
    candidate = study.study_config(cfg)
    assert candidate["data"]["image_size"] == 128
    candidate["data"]["image_size"] = cfg["data"]["image_size"]
    assert candidate == cfg == before

    measurement = {
        "mm_per_px": 0.11,
        "disc_centre_y_px": 500.0,
        "disc_centre_x_px": 600.0,
        "disc_diameter_px": 800.0,
    }
    simulated = simulated_measurement(measurement, study.DISC_MM)
    assert simulated["disc_diameter_px"] == pytest.approx(
        study.DISC_MM / measurement["mm_per_px"]
    )
    assert {key: value for key, value in simulated.items() if key != "disc_diameter_px"} == {
        key: value for key, value in measurement.items() if key != "disc_diameter_px"
    }


@real_only
def test_candidate_features_use_nine_patches_and_not_the_label():
    study = _study()
    cfg = resolve_paths(study.study_config(load_config()))
    folds = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    entry = fold_split(folds, 0, 0)["train"][0]

    features = study.candidate_features(entry, cfg)
    changed_label = {**entry, "label": (entry["label"] + 1) % len(cfg["classes"])}
    assert features.shape[0] == 9
    assert np.array_equal(features, study.candidate_features(changed_label, cfg))


def _prediction(path, label, probabilities):
    return {
        "path": path,
        "group": f"group::{path}",
        "label": label,
        "probabilities": probabilities,
    }


def test_the_comparison_pairs_folds_and_paths_not_row_order():
    study = _study()
    baseline = {
        (0, 0): [
            _prediction("a", 0, [0.8, 0.2]),
            _prediction("b", 1, [0.1, 0.9]),
        ],
        (0, 1): [_prediction("c", 0, [0.7, 0.3])],
    }
    candidate = {
        (0, 1): [_prediction("c", 0, [0.6, 0.4])],
        (0, 0): [
            _prediction("b", 1, [0.2, 0.8]),
            _prediction("a", 0, [0.3, 0.7]),
        ],
    }

    study.require_paired_predictions(baseline, candidate)

    missing_path = copy.deepcopy(candidate)
    missing_path[(0, 0)].pop()
    with pytest.raises(ValueError, match="photograph paths"):
        study.require_paired_predictions(baseline, missing_path)

    duplicate_path = copy.deepcopy(candidate)
    duplicate_path[(0, 0)].append(duplicate_path[(0, 0)][0])
    with pytest.raises(ValueError, match="duplicate"):
        study.require_paired_predictions(baseline, duplicate_path)

    missing_fold = {(0, 0): candidate[(0, 0)]}
    with pytest.raises(ValueError, match="folds"):
        study.require_paired_predictions(baseline, missing_fold)


def test_the_verdict_uses_only_the_registered_macro_f1_margin():
    study = _study()
    assert study.MAX_MACRO_F1_DROP == 0.02
    boundary = 0.625 - study.MAX_MACRO_F1_DROP
    assert study.verdict(baseline_median=0.625, candidate_median=boundary)["passes"]
    assert not study.verdict(baseline_median=0.625, candidate_median=boundary - 0.001)[
        "passes"
    ]
    assert study.verdict(baseline_median=0.625, candidate_median=0.65)["passes"]


def test_the_baseline_metric_must_reproduce_its_record():
    study = _study()
    recorded = {
        "protocol": {"manifest_digest": "same-manifest"},
        "primary": {
            "per_repeat": [0.61, 0.62, 0.63],
            "median": 0.62,
            "range": [0.61, 0.63],
        },
    }
    study.require_baseline_metrics(copy.deepcopy(recorded), recorded)

    drifted = copy.deepcopy(recorded)
    drifted["primary"]["median"] += 0.001
    with pytest.raises(ValueError, match="baseline.*macro-F1"):
        study.require_baseline_metrics(drifted, recorded)

    wrong_manifest = copy.deepcopy(recorded)
    wrong_manifest["protocol"]["manifest_digest"] = "other-manifest"
    with pytest.raises(ValueError, match="manifest"):
        study.require_baseline_metrics(wrong_manifest, recorded)
