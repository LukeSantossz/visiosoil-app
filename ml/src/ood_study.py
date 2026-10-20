"""Does a distance in descriptor space tell the excluded Siltosa, or the field,
apart from the soils the model was fitted on? (SPEC 0176)

On repeat 0 of the fold manifest, each fold's training side fits the guard
(`ood.fit_guard`) and its test side is scored, so every splittable archive
photograph is scored once by a fit that never saw its soil sample. Population
`B` trains on every side and is never scored (ADR 0021). Each fold's fit also
scores the archive photographs of the classes the configuration excludes, and
an excluded photograph's score is the mean over the folds. With a field export
(SPEC 0174), the guard fitted on the whole archive scores it.

The threshold and the rule are fixed here, before any run:

    the threshold is the 0.99 quantile of the held-out soil scores, and a
    photograph scoring above it is refused. The guard is worth wiring when it
    refuses at least 4 of the 6 Siltosa photographs and the AUROC of Siltosa
    against held-out soil is at least 0.80. A third condition, a field refusal
    rate of at most 0.10, stays open until a field export is scored.

Wiring is a spec of its own. This study writes no contract.

Run from the `ml/` directory, on the machine that holds the archive:

    python -m src.ood_study --version v1 [--field <export dir>]
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
from sklearn.metrics import roc_auc_score

from .arms.descriptors import descriptor_features
from .arms.probe import Featuriser, _patch_matrix, _require_a_patch_block
from .config import load_config, resolve_paths
from .dataset import (
    _group_id,
    drop_refused_photographs,
    fold_split,
    load_folds_for_config,
    photograph_scale_of,
)
from .field import field_features, load_field_export
from .manifest import ARCHIVE_CLASSES, Manifest, dataset_root, read_manifest
from .ood import fit_guard, photograph_score

THRESHOLD_QUANTILE = 0.99
SILTOSA_REFUSED = 4
MIN_AUROC = 0.80
MAX_FIELD_REFUSAL = 0.10
_TOLERANCE = 1e-9

STUDY_DIRNAME = "ood_study"
REPORT_FILENAME = "report.json"


def excluded_entries(manifest: Manifest, cfg: Mapping) -> list[dict]:
    """The archive photographs of the classes the configuration excludes, as
    entries the descriptor featuriser reads, less any the patch grid refuses."""
    entries = [
        {
            "path": str(manifest.root / row.image),
            "class": row.texture_class,
            "group": _group_id(row.texture_class, row.sample_id),
        }
        for row in manifest.rows
        if row.texture_class not in cfg["classes"]
    ]
    accepted, refused = drop_refused_photographs(
        entries, cfg, scale=photograph_scale_of(manifest)
    )
    for path, refusal in refused.items():
        print(f"left out {path}: {refusal}")
    return accepted


def _block(entry: Mapping, cfg: Mapping, featuriser: Featuriser, cache: dict) -> np.ndarray:
    block = cache.get(entry["path"])
    if block is None:
        block = np.asarray(featuriser(entry, cfg), dtype=np.float64)
        _require_a_patch_block(entry, block)
        cache[entry["path"]] = block
    return block


def _refusals(records: Sequence[Mapping], threshold: float, key: str) -> dict:
    """How many of ``records`` score above ``threshold``, overall and by ``key``."""

    def count(subset):
        refused = sum(r["score"] > threshold for r in subset)
        return {
            "count": len(subset),
            "refused": int(refused),
            "rate": refused / len(subset) if subset else None,
        }

    names = sorted({r[key] for r in records})
    return {
        **count(records),
        f"per_{key}": {name: count([r for r in records if r[key] == name]) for name in names},
    }


def apply_rule(*, refused: int, auroc: float | None, field_refusal: float | None) -> dict:
    """The rule written in this module's docstring."""
    siltosa = refused >= SILTOSA_REFUSED
    separates = auroc is not None and auroc >= MIN_AUROC - _TOLERANCE
    field = "open" if field_refusal is None else field_refusal <= MAX_FIELD_REFUSAL + _TOLERANCE
    if not (siltosa and separates) or field is False:
        verdict = "fail"
    elif field == "open":
        verdict = "open"
    else:
        verdict = "pass"
    return {"siltosa_refused": siltosa, "auroc": separates, "field": field, "verdict": verdict}


def run_study(
    cfg: Mapping,
    fold_manifest: Mapping,
    excluded: Sequence[Mapping],
    field: Sequence[Mapping] | None = None,
    *,
    featuriser: Featuriser = descriptor_features,
    field_featuriser: Featuriser = field_features,
) -> dict:
    """The held-out soil, the excluded photographs and the field, as a report."""
    classes = len(cfg["classes"])
    cache: dict[str, np.ndarray] = {}
    soil = []
    fold_scores: dict[str, list[float]] = {entry["path"]: [] for entry in excluded}
    for fold in range(int(fold_manifest["k"])):
        split = fold_split(fold_manifest, 0, fold)
        features, labels, _ = _patch_matrix(split["train"], cfg, featuriser, cache)
        guard = fit_guard(features, labels, classes=classes)
        for entry in split["test"]:
            soil.append(
                {
                    "path": entry["path"],
                    "group": entry["group"],
                    "class": entry["class"],
                    "fold": fold,
                    "score": photograph_score(guard, _block(entry, cfg, featuriser, cache)),
                }
            )
        for entry in excluded:
            fold_scores[entry["path"]].append(
                photograph_score(guard, _block(entry, cfg, featuriser, cache))
            )

    threshold = float(np.quantile([r["score"] for r in soil], THRESHOLD_QUANTILE))
    outside = [
        {
            "path": entry["path"],
            "group": entry["group"],
            "class": entry["class"],
            "fold_scores": fold_scores[entry["path"]],
            "score": float(np.mean(fold_scores[entry["path"]])),
        }
        for entry in excluded
    ]
    for record in soil + outside:
        record["refused"] = bool(record["score"] > threshold)
    auroc = None
    if outside:
        auroc = float(
            roc_auc_score(
                [0] * len(soil) + [1] * len(outside),
                [r["score"] for r in soil] + [r["score"] for r in outside],
            )
        )

    field_report = None
    if field is not None:
        everything = [e for side in fold_split(fold_manifest, 0, 0).values() for e in side]
        features, labels, _ = _patch_matrix(everything, cfg, featuriser, cache)
        guard = fit_guard(features, labels, classes=classes)
        field_cache: dict[str, np.ndarray] = {}
        scored = [
            {
                "path": entry["path"],
                "sample": entry["sample"],
                "class": entry["class"],
                "score": photograph_score(
                    guard, _block(entry, cfg, field_featuriser, field_cache)
                ),
            }
            for entry in field
        ]
        field_report = {**_refusals(scored, threshold, "class"), "scores": scored}

    excluded_report = _refusals(outside, threshold, "group")
    return {
        "threshold": threshold,
        "quantile": THRESHOLD_QUANTILE,
        "held_out_soil": {**_refusals(soil, threshold, "class"), "photographs": soil},
        "excluded": {**excluded_report, "photographs": outside},
        "auroc": auroc,
        "field": field_report,
        "rule": apply_rule(
            refused=excluded_report["refused"],
            auroc=auroc,
            field_refusal=None if field_report is None else field_report["rate"],
        ),
    }


def write_report(report: Mapping, directory: Path | str) -> Path:
    """Writes ``report.json`` and prints the refusals and the rule."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / REPORT_FILENAME
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    soil = report["held_out_soil"]
    print(f"threshold ({report['quantile']} quantile of held-out soil): {report['threshold']:.4f}")
    print("| Set | Photographs | Refused | Rate |")
    print("|---|---|---|---|")
    rows = [("held-out soil", soil)] + [(name, c) for name, c in soil["per_class"].items()]
    rows.append(("excluded", report["excluded"]))
    rows += [(name, c) for name, c in report["excluded"]["per_group"].items()]
    if report["field"] is not None:
        rows.append(("field", report["field"]))
        rows += [(f"field {name}", c) for name, c in report["field"]["per_class"].items()]
    for name, counts in rows:
        rate = "-" if counts["rate"] is None else f"{counts['rate']:.3f}"
        print(f"| {name} | {counts['count']} | {counts['refused']} | {rate} |")
    auroc = report["auroc"]
    print(f"AUROC excluded vs held-out soil: {'-' if auroc is None else f'{auroc:.3f}'}")
    rule = report["rule"]
    print(
        f"verdict: {rule['verdict']} (siltosa refused {rule['siltosa_refused']}, "
        f"auroc {rule['auroc']}, field {rule['field']})"
    )
    return path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure a descriptor-space distance guard against held-out "
        "soil, the excluded Siltosa and, optionally, the field (SPEC 0176)."
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument("--field", type=str, default=None, help="The app's field export (SPEC 0174)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    cfg = resolve_paths(load_config(args.config))
    if cfg["data"]["dataset_version"] != args.version:
        raise ValueError("requested dataset version differs from the configuration")
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    root = dataset_root(cfg["data"]["datasets_dir"], cfg["data"]["dataset_version"])
    excluded = excluded_entries(read_manifest(root, ARCHIVE_CLASSES), cfg)
    field = None if args.field is None else load_field_export(args.field, cfg)
    report = run_study(
        cfg,
        fold_manifest,
        excluded,
        field,
        featuriser=descriptor_features,
        field_featuriser=field_features,
    )
    models_dir = Path(cfg["export"]["output_dir"])
    path = write_report(report, models_dir / args.version / STUDY_DIRNAME)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
