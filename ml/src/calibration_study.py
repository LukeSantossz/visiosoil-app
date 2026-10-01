"""A temperature and conformal verdict bands, studied on stored predictions
(SPEC 0098, #193's E15).

The study reads one arm's cross-validated predictions and measures two things
the app does not do yet:

- how much a temperature would correct the photograph distribution's
  calibration;
- how split-conformal verdict bands compare with ADR 0011's hand-set constants,
  at four levels and at the constants' own coverage.

Every fitted quantity is cross-fitted. Within a repeat, the temperature and the
thresholds applied to fold k are fitted on the other folds' predictions, and
the folds are disjoint by sample group, so nothing is scored on what fitted it.

It publishes nothing. It writes `calibration_study.json` beside the arm's
`metrics.json`, and the figures describe the archive's dish photographs, not
the A4-sheet photographs the app takes.

Run from the `ml/` directory:

    python -m src.calibration_study --version v1 --arm descriptors
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from statistics import median
from typing import Mapping, Sequence

from .calibration import (
    adr0011_verdict,
    apply_temperature,
    calibration_error,
    conformal_set,
    conformal_threshold,
    fit_temperature,
    verdict_of_set,
)

STUDY_FILENAME = "calibration_study.json"

#: The conformal levels the study reports, besides the incumbent's own coverage.
ALPHAS = (0.05, 0.10, 0.15, 0.20)
VERDICTS = ("conclusive", "ambiguous", "insufficient")

CONFORMAL_SCORE = "1 - p(true class), on the raw photograph distribution"
POOLED_TEMPERATURE_WHY = (
    "Fitted on every out-of-fold prediction of every repeat: the value a release "
    "would publish. Not scored here, since it saw every photograph; the "
    "cross-fitted temperatures are what the scaled figures use."
)


def _sets_summary(entries: Sequence[tuple[int, Sequence[int]]]) -> dict:
    """Coverage, mean size, verdict shares and conclusive accuracy of sets.

    Each entry is a photograph's true class and its prediction set. A
    conclusive set holds one class, so its accuracy is its coverage.
    """
    count = len(entries)
    verdicts = [verdict_of_set(len(classes)) for _, classes in entries]
    conclusive = [label in classes for (label, classes), verdict in zip(entries, verdicts) if verdict == "conclusive"]
    return {
        "photographs": count,
        "coverage": sum(label in classes for label, classes in entries) / count,
        "mean_set_size": sum(len(classes) for _, classes in entries) / count,
        "verdicts": {name: verdicts.count(name) / count for name in VERDICTS},
        "conclusive_accuracy": sum(conclusive) / len(conclusive) if conclusive else None,
    }


def _spread(values: Sequence[float | None]) -> dict:
    present = [value for value in values if value is not None]
    if not present:
        return {"median": None, "range": None}
    return {"median": float(median(present)), "range": [min(present), max(present)]}


def _finite(value: float) -> float | None:
    """JSON has no infinity: an unbounded threshold is written as null."""
    return None if math.isinf(value) else value


def calibration_study(
    fold_manifest: Mapping, predictions: Mapping[tuple[int, int], Sequence[Mapping]]
) -> dict:
    """The cross-fitted study over every repeat of one arm's predictions.

    Args:
        fold_manifest: Supplies ``repeats``, ``k`` and ``classes``.
        predictions: ``(repeat, fold)`` to that fold's records, each carrying
            ``group``, ``label`` and ``probabilities``.
    """
    repeats_out = []
    pooled_labels: list[int] = []
    pooled_distributions: list[Sequence[float]] = []

    for repeat in range(fold_manifest["repeats"]):
        folds = [list(predictions[(repeat, fold)]) for fold in range(fold_manifest["k"])]
        labels: list[int] = []
        raw: list[Sequence[float]] = []
        scaled: list[list[float]] = []
        groups: set[str] = set()
        levels: dict[float, list] = {alpha: [] for alpha in ALPHAS}
        matched: list = []
        incumbent_raw: list = []
        incumbent_scaled: list = []
        fold_records = []

        for fold, scored in enumerate(folds):
            fitting = [record for other, records in enumerate(folds) if other != fold for record in records]
            fit_labels = [int(record["label"]) for record in fitting]
            fit_distributions = [record["probabilities"] for record in fitting]

            temperature = fit_temperature(fit_labels, fit_distributions)
            scores = [1.0 - d[label] for label, d in zip(fit_labels, fit_distributions)]
            thresholds = {alpha: conformal_threshold(scores, alpha) for alpha in ALPHAS}
            # The incumbent's coverage on the fitting folds sets the matched
            # level, so the match too is fitted without the scored fold.
            incumbent_coverage = sum(
                label in adr0011_verdict(d)[1] for label, d in zip(fit_labels, fit_distributions)
            ) / len(fitting)
            matched_alpha = 1.0 - incumbent_coverage
            matched_threshold = conformal_threshold(scores, matched_alpha)

            for record in scored:
                label = int(record["label"])
                distribution = record["probabilities"]
                calibrated = apply_temperature(distribution, temperature)
                labels.append(label)
                raw.append(distribution)
                scaled.append(calibrated)
                groups.add(record["group"])
                for alpha in ALPHAS:
                    levels[alpha].append((label, conformal_set(distribution, thresholds[alpha])))
                matched.append((label, conformal_set(distribution, matched_threshold)))
                incumbent_raw.append((label, adr0011_verdict(distribution)[1]))
                incumbent_scaled.append((label, adr0011_verdict(calibrated)[1]))

            fold_records.append(
                {
                    "fold": fold,
                    "temperature": temperature,
                    "fitted_on": {
                        "photographs": len(fitting),
                        "groups": len({record["group"] for record in fitting}),
                    },
                    "thresholds": [
                        {"alpha": alpha, "threshold": _finite(thresholds[alpha])} for alpha in ALPHAS
                    ],
                    "matched_alpha": matched_alpha,
                    "matched_threshold": _finite(matched_threshold),
                }
            )

        pooled_labels.extend(labels)
        pooled_distributions.extend(raw)
        repeats_out.append(
            {
                "repeat": repeat,
                "photographs": len(labels),
                "groups": len(groups),
                "calibration": {
                    "raw": calibration_error(labels, raw),
                    "scaled": calibration_error(labels, scaled),
                },
                "temperatures": [record["temperature"] for record in fold_records],
                "conformal": {
                    "score": CONFORMAL_SCORE,
                    "levels": [{"alpha": alpha, **_sets_summary(levels[alpha])} for alpha in ALPHAS],
                    "matched": {
                        "alphas": [record["matched_alpha"] for record in fold_records],
                        **_sets_summary(matched),
                    },
                },
                "incumbent": {
                    "raw": _sets_summary(incumbent_raw),
                    "scaled": _sets_summary(incumbent_scaled),
                },
                "folds": fold_records,
            }
        )

    def across(path) -> dict:
        return _spread([path(record) for record in repeats_out])

    def sets_across(select) -> dict:
        return {
            "coverage": across(lambda r: select(r)["coverage"]),
            "mean_set_size": across(lambda r: select(r)["mean_set_size"]),
            "verdicts": {name: across(lambda r, name=name: select(r)["verdicts"][name]) for name in VERDICTS},
            "conclusive_accuracy": across(lambda r: select(r)["conclusive_accuracy"]),
        }

    return {
        "level": "photograph",
        "fitting": (
            "cross-fitted: each fold's temperature and thresholds come from the "
            "other folds of its repeat, which share no sample group with it"
        ),
        "repeats": repeats_out,
        "summary": {
            "expected_calibration_error": {
                key: across(lambda r, key=key: r["calibration"][key]["expected_calibration_error"])
                for key in ("raw", "scaled")
            },
            "temperature": _spread([t for record in repeats_out for t in record["temperatures"]]),
            "pooled_temperature": {
                "temperature": fit_temperature(pooled_labels, pooled_distributions),
                "photographs": len(pooled_labels),
                "why": POOLED_TEMPERATURE_WHY,
            },
            "conformal": [
                {"alpha": alpha, **sets_across(lambda r, i=index: r["conformal"]["levels"][i])}
                for index, alpha in enumerate(ALPHAS)
            ],
            "matched": sets_across(lambda r: r["conformal"]["matched"]),
            "incumbent": {
                key: sets_across(lambda r, key=key: r["incumbent"][key]) for key in ("raw", "scaled")
            },
        },
    }


def _print_summary(study: Mapping, path: Path) -> None:
    summary = study["summary"]
    ece = summary["expected_calibration_error"]
    print(f"calibration error: raw {ece['raw']['median']:.4f}, scaled {ece['scaled']['median']:.4f}")
    print(
        f"temperature: cross-fitted median {summary['temperature']['median']:.3f}, "
        f"pooled {summary['pooled_temperature']['temperature']:.3f}"
    )
    for level in summary["conformal"]:
        print(
            f"conformal alpha {level['alpha']:.2f}: coverage {level['coverage']['median']:.3f}, "
            f"set size {level['mean_set_size']['median']:.2f}"
        )
    for key in ("raw", "scaled"):
        incumbent = summary["incumbent"][key]
        print(
            f"ADR 0011 ({key}): coverage {incumbent['coverage']['median']:.3f}, "
            f"conclusive share {incumbent['verdicts']['conclusive']['median']:.3f}"
        )
    print(f"study saved to {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="v1", help="Dataset version")
    parser.add_argument("--arm", default="descriptors", help="Arm whose predictions to read")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    args = parser.parse_args()

    from .config import load_config, resolve_paths
    from .crossval import arm_directory, load_arm_predictions
    from .dataset import load_folds_for_config

    cfg = resolve_paths(load_config(args.config))
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    arm_dir = arm_directory(Path(cfg["export"]["output_dir"]) / args.version, args.arm)
    predictions, _ = load_arm_predictions(arm_dir, fold_manifest)

    study = {
        "version": args.version,
        "arm": args.arm,
        "spec": "SPEC 0098",
        **calibration_study(fold_manifest, predictions),
    }
    destination = arm_dir / STUDY_FILENAME
    with open(destination, "w") as handle:
        json.dump(study, handle, indent=2)
    _print_summary(study, destination)


if __name__ == "__main__":
    main()
