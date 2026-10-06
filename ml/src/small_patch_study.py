"""Research-only 128 px descriptor candidate for small soil discs (SPEC 0143)."""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Callable, Mapping

import numpy as np

from .descriptors import GROUPS, describe_patch
from .small_disc import simulated_measurement


PATCH_PX = 128
DISC_MM = 47.2
MAX_MACRO_F1_DROP = 0.02
METRIC_TOLERANCE = 1e-12
STUDY_ARM = "descriptors_128px_small_disc"
STUDY_FILENAME = "small_patch_study.json"


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


def cached_candidate_features(cache: dict[str, np.ndarray]) -> Callable:
    """Reuse pixel-derived features while folds partition the same photographs."""
    def featurise(entry: Mapping, cfg: Mapping) -> np.ndarray:
        path = entry["path"]
        if path not in cache:
            cache[path] = candidate_features(entry, cfg)
        return cache[path]

    return featurise


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


def train_candidate_fold(
    cfg: Mapping,
    fold_manifest: Mapping,
    arm_dir: Path | str,
    *,
    repeat: int,
    fold: int,
    verify: bool = True,
    featuriser: Callable | None = None,
) -> dict:
    """Use the established nested probe selection for one candidate fold."""
    from .arms.probe import probe_fold

    return probe_fold(
        cfg,
        fold_manifest,
        arm_dir=arm_dir,
        arm=STUDY_ARM,
        repeat=repeat,
        fold=fold,
        featuriser=candidate_features if featuriser is None else featuriser,
        verify=verify,
    )


def _plan_candidate_run(planner, candidate_dir, fold_manifest, candidate_cfg):
    try:
        return planner(
            candidate_dir,
            fold_manifest,
            cfg=candidate_cfg,
            arm=STUDY_ARM,
            shuffled_control=False,
        )
    except ValueError as error:
        message, separator, _ = str(error).partition("\nPass --force to recompute them")
        if not separator:
            raise
        raise ValueError(
            f"{message}\nArchive or remove those stale candidate artifacts before "
            "rerunning the study."
        ) from error


def run_study(
    cfg: Mapping,
    fold_manifest: Mapping,
    baseline_dir: Path | str,
    candidate_dir: Path | str,
) -> dict:
    """Compare nested candidate folds with matching released-arm folds."""
    from .crossval import (
        _images_by_class,
        begin_fold,
        first_runtime,
        fold_directory,
        load_arm_predictions,
        plan_arm_run,
        require_uniform_runtime,
    )
    from .dataset import verify_images
    from .evaluate import arm_metrics
    from .small_disc import top1_agreement

    if cfg["data"]["image_size"] != 160:
        raise ValueError("baseline configuration must use the released 160 px patch")

    baseline_dir = Path(baseline_dir)
    candidate_dir = Path(candidate_dir)
    baseline_predictions, baseline_costs = load_arm_predictions(baseline_dir, fold_manifest)
    baseline_plan = plan_arm_run(
        baseline_dir,
        fold_manifest,
        cfg=cfg,
        arm="descriptors",
        shuffled_control=False,
    )
    if baseline_plan["run"]:
        raise ValueError("baseline has unfinished folds")
    require_uniform_runtime(baseline_dir, fold_manifest)
    baseline_metrics = arm_metrics(
        fold_manifest,
        arm="descriptors",
        version=fold_manifest["dataset_version"],
        predictions=baseline_predictions,
        costs=baseline_costs,
        runtime=first_runtime(baseline_dir, fold_manifest),
    )
    with open(baseline_dir / "metrics.json", encoding="utf-8") as handle:
        recorded_baseline = json.load(handle)
    require_baseline_metrics(baseline_metrics, recorded_baseline)

    candidate_cfg = study_config(cfg)
    plan = _plan_candidate_run(
        plan_arm_run, candidate_dir, fold_manifest, candidate_cfg
    )
    if plan["run"]:
        verify_images(_images_by_class(fold_manifest))
        candidate_dir.mkdir(parents=True, exist_ok=True)
    featuriser = cached_candidate_features({})
    for repeat, fold in plan["run"]:
        begin_fold(candidate_dir, repeat, fold)
        train_candidate_fold(
            candidate_cfg,
            fold_manifest,
            candidate_dir,
            repeat=repeat,
            fold=fold,
            verify=False,
            featuriser=featuriser,
        )

    require_uniform_runtime(candidate_dir, fold_manifest)
    candidate_predictions, candidate_costs = load_arm_predictions(candidate_dir, fold_manifest)
    require_paired_predictions(baseline_predictions, candidate_predictions)
    candidate_metrics = arm_metrics(
        fold_manifest,
        arm=STUDY_ARM,
        version=fold_manifest["dataset_version"],
        predictions=candidate_predictions,
        costs=candidate_costs,
        runtime=first_runtime(candidate_dir, fold_manifest),
    )
    selected_c = {}
    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            audit = fold_directory(candidate_dir, repeat, fold) / "selection_audit.json"
            with open(audit, encoding="utf-8") as handle:
                selected_c[f"{repeat}/{fold}"] = json.load(handle)["chosen"]["C"]

    return {
        "spec": "SPEC 0143",
        "dataset_version": fold_manifest["dataset_version"],
        "seed": fold_manifest["seed"],
        "fold_library_versions": fold_manifest["library_versions"],
        "candidate_patch_px": PATCH_PX,
        "candidate_disc_mm": DISC_MM,
        "min_patches": candidate_cfg["preprocessing"]["min_patches"],
        "max_macro_f1_drop": MAX_MACRO_F1_DROP,
        "baseline": baseline_metrics,
        "candidate": candidate_metrics,
        "top1_agreement": top1_agreement(baseline_predictions, candidate_predictions),
        "selected_c": selected_c,
        "verdict": verdict(
            baseline_median=baseline_metrics["primary"]["median"],
            candidate_median=candidate_metrics["primary"]["median"],
        ),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="v1", help="Dataset version")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    args = parser.parse_args()

    from .config import load_config, resolve_paths
    from .crossval import arm_directory
    from .dataset import load_folds_for_config

    cfg = resolve_paths(load_config(args.config))
    if cfg["data"]["dataset_version"] != args.version:
        raise ValueError("requested dataset version differs from the configuration")
    folds = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    output_root = Path(cfg["export"]["output_dir"]) / args.version
    baseline_dir = arm_directory(output_root, "descriptors")
    candidate_dir = arm_directory(output_root, STUDY_ARM)
    result = run_study(cfg, folds, baseline_dir, candidate_dir)
    destination = candidate_dir / STUDY_FILENAME
    with open(destination, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2)
    print(
        f"candidate median photograph macro-F1 "
        f"{result['candidate']['primary']['median']:.4f}; "
        f"baseline {result['baseline']['primary']['median']:.4f}; "
        f"{'passes' if result['verdict']['passes'] else 'fails'}"
    )
    print(f"study saved to {destination}")


if __name__ == "__main__":
    main()
