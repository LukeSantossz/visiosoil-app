"""The release fit: the adopted descriptor pipeline, fitted once on all of a
dataset version and written as a contract (SPEC 0082, B3).

E0 chose `C` on grouped inner folds of each outer training side and refitted.
A release has no outer test side, so one level of that nesting collapses and
the whole pool is the training side. `C` is chosen over the fold manifest's own
outer partition, every fold of every repeat, by E0's criterion: mean
photograph-level accuracy, ties to the strongest regularisation. Population
`B` sits on every training side and on no scored side (ADR 0021). The refit
then holds every photograph the manifest holds, and
`contract.descriptor_contract` writes it.

The selection accuracy is the best of five settings on folds it was chosen on,
so it flatters. `selection.json` records it as the reason `C` was chosen,
never as a performance figure: the release's performance is E0's
cross-validated estimate of this procedure.

Run from the `ml/` directory:

    python -m src.release --version v1 --model-version 1.0.0

It writes `models/<version>/release/`, which `scripts/deploy_to_app.sh`
promotes into the app (ADR 0012).
"""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

import numpy as np
from sklearn.pipeline import Pipeline

from .arms.descriptors import descriptor_features
from .arms.probe import (
    C_GRID,
    SELECTION_CRITERION,
    Featuriser,
    _patch_matrix,
    _photograph_accuracy,
    _select,
    fit_probe,
)
from .config import load_config, resolve_paths
from .contract import descriptor_contract
from .dataset import fold_split, load_folds_for_config

RELEASE_DIRNAME = "release"
CONTRACT_FILENAME = "spec.json"
SELECTION_FILENAME = "selection.json"


@dataclass(frozen=True)
class Release:
    """One release: the contract, how its `C` was chosen, and the fit itself."""

    contract: dict
    selection: dict
    pipeline: Pipeline


def release_fit(
    cfg: Mapping,
    fold_manifest: Mapping,
    *,
    model_version: str,
    featuriser: Featuriser = descriptor_features,
) -> Release:
    """Select `C` over every fold of ``fold_manifest``, refit on all of it, and
    write the contract.

    The dataset version is the manifest's own, never a parameter, so the
    contract cannot name a dataset it was not fitted on.
    """
    # One block of features per photograph for the whole release: every fold's
    # training side and the refit hold most of the same photographs.
    cache: dict[str, np.ndarray] = {}

    accuracies: list[list[float]] = []
    for repeat in range(int(fold_manifest["repeats"])):
        for fold in range(int(fold_manifest["k"])):
            # Train-only groups have no fold index, so `fold_split` puts them on
            # every training side and never on a test side: no photograph of
            # population `B` is ever scored.
            split = fold_split(fold_manifest, repeat, fold)
            features, labels, _ = _patch_matrix(split["train"], cfg, featuriser, cache)
            accuracies.append(
                [
                    _photograph_accuracy(
                        fit_probe(features, labels, c=candidate),
                        split["test"],
                        cfg,
                        featuriser,
                        cache,
                    )
                    for candidate in C_GRID
                ]
            )
            print(
                f"repeat {repeat} fold {fold}: accuracy per C "
                f"{[round(value, 4) for value in accuracies[-1]]}"
            )

    mean_accuracy = [float(value) for value in np.mean(accuracies, axis=0)]
    chosen = _select(C_GRID, mean_accuracy)

    # Every group once: the train and test sides of any one fold partition the
    # manifest between them.
    everything = [
        entry for side in fold_split(fold_manifest, 0, 0).values() for entry in side
    ]
    print(f"refitting on all {len(everything)} photograph(s) at C = {chosen}")
    features, labels, _ = _patch_matrix(everything, cfg, featuriser, cache)
    pipeline = fit_probe(features, labels, c=chosen)

    dataset_version = str(fold_manifest["dataset_version"])
    contract = descriptor_contract(
        pipeline, cfg, model_version=model_version, dataset_version=dataset_version
    )
    groups = fold_manifest["groups"]
    selection = {
        "criterion": SELECTION_CRITERION,
        "c_grid": [float(candidate) for candidate in C_GRID],
        "mean_accuracy_per_c": [
            {"C": float(candidate), "mean_accuracy": value}
            for candidate, value in zip(C_GRID, mean_accuracy, strict=True)
        ],
        "chosen_c": float(chosen),
        "scored_folds": len(accuracies),
        "manifest_digest": fold_manifest["manifest_digest"],
        "dataset_version": dataset_version,
        "model_version": str(model_version),
        "photographs": len(everything),
        "groups": len(groups),
        "train_only_groups": sum(1 for group in groups.values() if group["train_only"]),
        "note": (
            "The selection accuracy is the best of the grid on the folds it was "
            "chosen on, and is not a performance figure. The release's "
            "performance is E0's cross-validated estimate of this procedure."
        ),
    }
    return Release(contract=contract, selection=selection, pipeline=pipeline)


def write_release(fitted: Release, directory: Path | str) -> Path:
    """Write ``spec.json`` and ``selection.json`` into ``directory``."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    for name, document in (
        (CONTRACT_FILENAME, fitted.contract),
        (SELECTION_FILENAME, fitted.selection),
    ):
        (directory / name).write_text(
            json.dumps(document, indent=2) + "\n", encoding="utf-8"
        )
    return directory


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fit the descriptor pipeline on a whole dataset version and "
        "write its contract (SPEC 0082)."
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument(
        "--model-version",
        type=str,
        required=True,
        help="The version this release is named by, such as 1.0.0",
    )
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    cfg = resolve_paths(load_config(args.config))
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    fitted = release_fit(cfg, fold_manifest, model_version=args.model_version)
    directory = write_release(
        fitted, Path(cfg["export"]["output_dir"]) / args.version / RELEASE_DIRNAME
    )
    print(f"wrote {directory / CONTRACT_FILENAME} and {directory / SELECTION_FILENAME}")
    print(f"chosen C = {fitted.selection['chosen_c']}")


if __name__ == "__main__":
    main()
