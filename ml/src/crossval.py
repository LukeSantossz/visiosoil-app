"""Orchestrator for one arm of the k-fold protocol (SPEC 0042, ADR 0020).

Runs every outer fold of every repeat, pools the predictions, and writes the
arm's ``metrics.json``. The training stack is imported inside :func:`run_arm`
rather than at module import, so the artifact layout, the loader and the pooling
can be read and tested on a machine with no TensorFlow — which is where the
protocol's own tests run.

The on-disk layout is::

    models/<version>/<arm>/
        metrics.json
        repeat-<r>/fold-<i>/
            model.keras
            config.json
            runtime.json
            selection_audit.json
            predictions.json
            cost.json

Every artifact of a fold lives under that fold, including the audit of what
selection read, so a result and the evidence that it was produced honestly
cannot be separated by moving a file.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Mapping, Sequence

from .config import load_config, resolve_paths
from .dataset import (
    FOLD_MANIFEST_FILENAME,
    create_folds_for_config,
    load_folds,
)
from .evaluate import METRICS_FILENAME, arm_metrics

PREDICTIONS_FILENAME = "predictions.json"
COST_FILENAME = "cost.json"
SELECTION_AUDIT_FILENAME = "selection_audit.json"
RUNTIME_FILENAME = "runtime.json"

#: Default arm names. The real arm is named for what it is rather than for the
#: run, so two experiments comparing the same thing land in the same directory
#: and can be contrasted; the control is named separately so a control run
#: cannot silently overwrite the arm it is the control for.
DEFAULT_ARM = "cnn"
SHUFFLED_CONTROL_ARM = "shuffled_control"


def arm_directory(output_dir: Path | str, arm: str) -> Path:
    """Where one arm's folds and metrics live."""
    return Path(output_dir) / arm


def fold_directory(arm_dir: Path | str, repeat: int, fold: int) -> Path:
    """Where one outer fold's artifacts live."""
    return Path(arm_dir) / f"repeat-{repeat}" / f"fold-{fold}"


def write_fold_predictions(
    arm_dir: Path | str,
    *,
    repeat: int,
    fold: int,
    arm: str,
    classes: Sequence[str],
    records: Sequence[Mapping],
    shuffled_control: bool,
) -> Path:
    """Write one fold's test-side predictions.

    The full distribution is stored, not the argmax, because the group-level
    prediction is the argmax of the *mean* of a group's distributions and cannot
    be recovered from per-photograph labels.
    """
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / PREDICTIONS_FILENAME
    with open(path, "w") as handle:
        json.dump(
            {
                "repeat": repeat,
                "fold": fold,
                "arm": arm,
                "shuffled_control": bool(shuffled_control),
                "classes": list(classes),
                "predictions": list(records),
            },
            handle,
            indent=2,
        )
    return path


def write_fold_cost(
    arm_dir: Path | str, repeat: int, fold: int, trainings: int, seconds: Sequence[float]
) -> Path:
    """Record what one outer fold cost, so k and R are auditable against it."""
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / COST_FILENAME
    with open(path, "w") as handle:
        json.dump(
            {"trainings": int(trainings), "wall_clock_seconds": list(seconds)},
            handle,
            indent=2,
        )
    return path


def write_selection_audit(
    arm_dir: Path | str,
    repeat: int,
    fold: int,
    *,
    selection_group_ids: Sequence[str],
    test_group_ids: Sequence[str],
    inner_k: int,
    chosen: Mapping,
    refit_group_count: int,
) -> Path:
    """Record every group read while selecting a setting for this fold.

    Written beside the fold's own artifacts, and asserted against the fold's
    test groups by `tests/test_folds.py`. An audit that lived somewhere central
    could be regenerated from the code that produced the leak; this one is
    produced by the same call that built the inner folds.
    """
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / SELECTION_AUDIT_FILENAME
    leaked = sorted(set(selection_group_ids) & set(test_group_ids))
    with open(path, "w") as handle:
        json.dump(
            {
                "repeat": repeat,
                "fold": fold,
                "inner_k": inner_k,
                "groups_read_during_selection": sorted(set(selection_group_ids)),
                "test_groups": sorted(set(test_group_ids)),
                "leaked_groups": leaked,
                "chosen": dict(chosen),
                "refit_groups": refit_group_count,
            },
            handle,
            indent=2,
        )
    if leaked:
        raise ValueError(
            f"selection for repeat {repeat} fold {fold} read {len(leaked)} of "
            f"its own test groups: {', '.join(leaked)}. Nested selection is "
            "what makes the fold's number honest (ADR 0020)"
        )
    return path


def load_runtime(fold_dir: Path | str) -> dict | None:
    """The recorded runtime of the training run that produced ``fold_dir``.

    ``None`` when the directory predates this record, which is honest: absent is
    not the same as deterministic, and a comparison must be able to tell them
    apart rather than assuming the safe value.

    It lives here rather than in `src.train` so that reading a result never
    reaches the training stack: `src.train` imports TensorFlow at module scope,
    and reporting has to run where TensorFlow cannot be installed.
    """
    path = Path(fold_dir) / RUNTIME_FILENAME
    if not path.exists():
        return None
    with open(path) as handle:
        return json.load(handle)


def load_arm_predictions(
    arm_dir: Path | str, fold_manifest: Mapping
) -> tuple[dict[tuple[int, int], list[dict]], dict[tuple[int, int], dict]]:
    """Read every fold's predictions and cost record for one arm.

    A missing fold is named rather than skipped: a pooled figure computed over
    twenty-four of twenty-five folds is not the figure the protocol defines, and
    silently producing it is worse than producing nothing.
    """
    arm_path = Path(arm_dir)
    predictions: dict[tuple[int, int], list[dict]] = {}
    costs: dict[tuple[int, int], dict] = {}

    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            directory = fold_directory(arm_path, repeat, fold)
            path = directory / PREDICTIONS_FILENAME
            if not path.exists():
                raise FileNotFoundError(
                    f"repeat {repeat} fold {fold} of {arm_path.name} has no "
                    f"{PREDICTIONS_FILENAME} at {path}. Run the arm with: "
                    f"python -m src.crossval --arm {arm_path.name}"
                )
            with open(path) as handle:
                predictions[(repeat, fold)] = json.load(handle)["predictions"]

            cost_path = directory / COST_FILENAME
            if cost_path.exists():
                with open(cost_path) as handle:
                    costs[(repeat, fold)] = json.load(handle)

    return predictions, costs


def run_arm(
    version: str,
    arm: str = DEFAULT_ARM,
    config_path: str | None = None,
    shuffled_control: bool = False,
) -> dict:
    """Train, predict and pool every fold of every repeat for one arm.

    The per-fold training recipe is unchanged (SPEC 0032): what changes here is
    which data a training sees and how the results are pooled.
    """
    # Imported here, not at module scope: everything above this function is
    # readable and testable without the training stack, and the tests that
    # assert what a result says run on a machine that has none.
    from .dataset import verify_images
    from .train import train_fold

    cfg = resolve_paths(load_config(config_path))
    splits_dir = cfg["data"]["splits_dir"]
    if not (Path(splits_dir) / FOLD_MANIFEST_FILENAME).exists():
        print(f"No fold manifest at {splits_dir}; generating it.")
        fold_manifest = create_folds_for_config(cfg, splits_dir)
    else:
        fold_manifest = load_folds(splits_dir)

    output_dir = Path(cfg["export"]["output_dir"]) / version
    arm_dir = arm_directory(output_dir, arm)
    arm_dir.mkdir(parents=True, exist_ok=True)

    # Once for the run, not once per fold: every fold reads the same images, and
    # an unreadable file has to stop the run before the first training rather
    # than twenty-four folds later. `train_fold` verifies when called directly.
    verify_images(_images_by_class(fold_manifest))

    runtime = None
    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            started = time.monotonic()
            print(
                f"\n=== {arm}: repeat {repeat + 1}/{fold_manifest['repeats']}, "
                f"fold {fold + 1}/{fold_manifest['k']} ==="
            )
            runtime = train_fold(
                cfg,
                fold_manifest,
                arm_dir=arm_dir,
                arm=arm,
                repeat=repeat,
                fold=fold,
                shuffled_control=shuffled_control,
                verify=False,
            )
            print(f"fold finished in {time.monotonic() - started:.1f}s")

    predictions, costs = load_arm_predictions(arm_dir, fold_manifest)
    metrics = arm_metrics(
        fold_manifest,
        arm=arm,
        version=version,
        predictions=predictions,
        costs=costs,
        shuffled_control=shuffled_control,
        runtime=runtime,
    )
    with open(arm_dir / METRICS_FILENAME, "w") as handle:
        json.dump(metrics, handle, indent=2)
    print(f"\nmetrics saved to {arm_dir / METRICS_FILENAME}")
    return metrics


def _images_by_class(fold_manifest: Mapping) -> dict[str, list[str]]:
    """Every image the folds reference, grouped by class for verification."""
    grouped: dict[str, list[str]] = {}
    for record in fold_manifest["groups"].values():
        grouped.setdefault(record["class"], []).extend(record["images"])
    return grouped


def default_arm_name(arm: str | None, shuffled_control: bool) -> str:
    """The arm a run writes to when none was named.

    A control run defaults to its own directory, so running the control without
    naming an arm cannot overwrite the arm it is the control for.
    """
    if arm is not None:
        return arm
    return SHUFFLED_CONTROL_ARM if shuffled_control else DEFAULT_ARM


def main():
    parser = argparse.ArgumentParser(
        description="Run one arm across every repeat and outer fold"
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument(
        "--arm",
        type=str,
        default=None,
        help=f"Experimental arm (default: {DEFAULT_ARM}, "
        f"or {SHUFFLED_CONTROL_ARM} with --shuffled-control)",
    )
    parser.add_argument(
        "--shuffled-control",
        action="store_true",
        help="Permute texture_class across groups within each fold's training side",
    )
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    run_arm(
        args.version,
        default_arm_name(args.arm, args.shuffled_control),
        args.config,
        shuffled_control=args.shuffled_control,
    )


if __name__ == "__main__":
    main()
