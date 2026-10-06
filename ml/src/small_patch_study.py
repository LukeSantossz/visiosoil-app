"""Research-only 128 px descriptor candidate for small soil discs (SPEC 0143)."""

from __future__ import annotations

import copy
import math
from typing import Mapping

import numpy as np

from .descriptors import GROUPS, describe_patch
from .small_disc import simulated_measurement


PATCH_PX = 128
DISC_MM = 47.2
MAX_MACRO_F1_DROP = 0.02
METRIC_TOLERANCE = 1e-12


def study_config(cfg: Mapping) -> dict:
    """Copy the released configuration with only the candidate patch size changed."""
    study = copy.deepcopy(dict(cfg))
    study["data"]["image_size"] = PATCH_PX
    return study


def candidate_features(entry: Mapping, cfg: Mapping) -> np.ndarray:
    """Describe the central nine patches of an entry's measured photograph."""
    from .dataset import _measurement_of, _photograph_patches, photograph_scale

    measurement = _measurement_of(entry, photograph_scale(cfg))
    simulated = simulated_measurement(measurement, DISC_MM)
    patches = _photograph_patches(entry, simulated, cfg)
    return np.stack([describe_patch(patch, groups=GROUPS) for patch in patches])


def _records_by_path(records, *, fold: tuple[int, int], arm: str) -> dict:
    indexed = {}
    for record in records:
        try:
            path = record["path"]
        except KeyError as error:
            raise ValueError(f"{arm} repeat {fold[0]} fold {fold[1]} has no path") from error
        if path in indexed:
            raise ValueError(f"{arm} repeat {fold[0]} fold {fold[1]} has duplicate path {path}")
        indexed[path] = record
    return indexed


def require_paired_predictions(baseline: Mapping, candidate: Mapping) -> None:
    """Refuse comparisons whose held-out photographs do not match exactly."""
    if baseline.keys() != candidate.keys():
        raise ValueError("baseline and candidate folds differ")
    for fold in baseline:
        base_records = _records_by_path(baseline[fold], fold=fold, arm="baseline")
        candidate_records = _records_by_path(candidate[fold], fold=fold, arm="candidate")
        if base_records.keys() != candidate_records.keys():
            raise ValueError(f"repeat {fold[0]} fold {fold[1]} photograph paths differ")
        for path, record in base_records.items():
            other = candidate_records[path]
            if (record["label"], record["group"]) != (other["label"], other["group"]):
                raise ValueError(f"repeat {fold[0]} fold {fold[1]} labels or groups differ for {path}")


def verdict(*, baseline_median: float, candidate_median: float) -> dict:
    """Apply the pre-registered non-inferiority margin to median macro-F1."""
    if not math.isfinite(baseline_median) or not math.isfinite(candidate_median):
        raise ValueError("macro-F1 medians must be finite")
    drop = baseline_median - candidate_median
    return {
        "macro_f1_drop": drop,
        "passes": candidate_median >= baseline_median - MAX_MACRO_F1_DROP,
    }


def require_baseline_metrics(computed: Mapping, recorded: Mapping) -> None:
    """Refuse a baseline whose stored headline cannot be reproduced."""
    try:
        computed_digest = computed["protocol"]["manifest_digest"]
        recorded_digest = recorded["protocol"]["manifest_digest"]
        computed_primary = computed["primary"]
        recorded_primary = recorded["primary"]
    except KeyError as error:
        raise ValueError(f"baseline metrics missing {error.args[0]}") from error
    if computed_digest != recorded_digest:
        raise ValueError("baseline manifest digest differs from its record")
    for key in ("per_repeat", "median", "range"):
        try:
            ours = np.asarray(computed_primary[key], dtype=float)
            theirs = np.asarray(recorded_primary[key], dtype=float)
        except KeyError as error:
            raise ValueError(f"baseline macro-F1 missing {error.args[0]}") from error
        if ours.shape != theirs.shape or not np.allclose(
            ours, theirs, rtol=0, atol=METRIC_TOLERANCE
        ):
            raise ValueError(f"baseline photograph macro-F1 {key} does not match its record")
