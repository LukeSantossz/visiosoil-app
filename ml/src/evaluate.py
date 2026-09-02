"""Reporting for the repeated group k-fold protocol (SPEC 0042, ADR 0020).

This module reads stored predictions and never loads a model, so it imports no
TensorFlow: what a result says can be recomputed by anyone holding the
prediction files, on a machine that could not run the training that produced
them. Prediction is `src.crossval`'s job, which is where the training stack is
needed.

Three rules the module enforces rather than documents:

- **Photograph-level macro-F1 is the primary number**, pooled over the k test
  sides of a repeat, because that is the level the product operates at.
- **The group carries every interval and every contrast.** A group's prediction
  is the argmax of the mean of its photographs' distributions; photographs of
  one physical sample are not independent, and counting them would overstate the
  evidence by roughly the number of photographs per sample.
- **The spread across folds is never reported as uncertainty.** Fold test sides
  are disjoint and small, so their spread understates the interval on the pooled
  figure (Varoquaux 2018). The Wilson interval on the pooled group count carries
  sampling variance and the spread across repeats carries training variance.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from statistics import median
from typing import Mapping, Sequence

import numpy as np
from sklearn.metrics import confusion_matrix, f1_score, precision_recall_fscore_support

from .config import load_config, resolve_paths
from .dataset import load_folds_for_config
from .stats import (
    group_level_predictions,
    holm_adjust,
    mcnemar_exact_p_value,
    mcnemar_minimum_detectable_effect,
    wilson_interval,
)

#: Names recorded in `metrics.json` so a consumer reads the level off the file
#: rather than inferring it from the number.
PRIMARY_METRIC = "photograph_macro_f1"
SECONDARY_METRIC = "group_macro_f1"

METRICS_FILENAME = "metrics.json"
CONTRASTS_FILENAME = "contrasts.json"

INTERVAL_CONFIDENCE = 0.95

#: Written beside every interval, because the sentence is the decision: a reader
#: who does not know where the width came from cannot tell a measurement from a
#: restatement of the fold count.
INTERVAL_SOURCE = (
    "Wilson score interval at 95 % on the pooled group count of one repeat. "
    "The spread across folds is not an interval and is not reported as one: "
    "fold test sides are disjoint and small, so their spread understates the "
    "interval on the pooled figure (Varoquaux 2018, NeuroImage 180:68-77)."
)

REPEAT_SPREAD_SOURCE = (
    "Median and range of the primary number across repeats. Repeats test the "
    "same groups, so this measures training and fold-assignment variance, not "
    "sampling variance, and it is not a confidence interval."
)


def arm_metrics(
    fold_manifest: Mapping,
    *,
    arm: str,
    version: str,
    predictions: Mapping[tuple[int, int], Sequence[Mapping]],
    costs: Mapping[tuple[int, int], Mapping],
    shuffled_control: bool = False,
    runtime: Mapping | None = None,
) -> dict:
    """Assemble one arm's `metrics.json` from its per-fold predictions.

    Args:
        fold_manifest: The fold manifest the arm was run against.
        arm: Name of the experimental arm.
        version: Dataset version the arm was run on.
        predictions: ``(repeat, fold)`` to that fold's prediction records, each
            carrying ``path``, ``group``, ``label`` and ``probabilities``.
        costs: ``(repeat, fold)`` to that fold's ``trainings`` count and its
            per-training wall-clock seconds.
        shuffled_control: Whether the arm trained on permuted labels.
        runtime: The runtime record training wrote, or ``None`` when the
            artifacts predate it. Absent is not the same as deterministic.

    Returns:
        The metrics dict, which the caller writes to ``metrics.json``.
    """
    classes = list(fold_manifest["classes"])
    labels = list(range(len(classes)))

    repeat_records = []
    pooled_photograph: list[tuple[int, int]] = []
    pooled_group: list[tuple[int, int]] = []

    for repeat in range(fold_manifest["repeats"]):
        fold_records = []
        photograph_pairs: list[tuple[int, int]] = []
        group_pairs: list[tuple[int, int]] = []

        for fold in range(fold_manifest["k"]):
            records = predictions[(repeat, fold)]
            fold_photographs = _photograph_pairs(records)
            fold_groups = _group_pairs(records)
            photograph_pairs.extend(fold_photographs)
            group_pairs.extend(fold_groups)
            # No key here names an interval, and none may: a width computed from
            # a single fold's fifteen groups is the error ADR 0020 exists to
            # remove, and the surest way to keep it out is to have no field for
            # it to hide in.
            fold_records.append(
                {
                    "fold": fold,
                    "photographs": len(fold_photographs),
                    "groups": len(fold_groups),
                    "photograph_macro_f1": _macro_f1(fold_photographs, labels),
                    "photograph_accuracy": _accuracy(fold_photographs),
                    "group_macro_f1": _macro_f1(fold_groups, labels),
                    "group_accuracy": _accuracy(fold_groups),
                }
            )

        correct = sum(1 for truth, predicted in group_pairs if truth == predicted)
        low, high = wilson_interval(correct, len(group_pairs), INTERVAL_CONFIDENCE)
        repeat_records.append(
            {
                "repeat": repeat,
                "seed": fold_manifest["seeds"][str(repeat)],
                "photographs": len(photograph_pairs),
                "groups": len(group_pairs),
                "groups_correct": correct,
                "photograph_macro_f1": _macro_f1(photograph_pairs, labels),
                "photograph_accuracy": _accuracy(photograph_pairs),
                "group_macro_f1": _macro_f1(group_pairs, labels),
                "group_accuracy": _accuracy(group_pairs),
                "wilson_interval_95_group_accuracy": {
                    "low": low,
                    "high": high,
                    "confidence": INTERVAL_CONFIDENCE,
                    "source": INTERVAL_SOURCE,
                },
                "folds": fold_records,
            }
        )
        pooled_photograph.extend(photograph_pairs)
        pooled_group.extend(group_pairs)

    primary_values = [record["photograph_macro_f1"] for record in repeat_records]
    secondary_values = [record["group_macro_f1"] for record in repeat_records]

    return {
        "version": version,
        "arm": arm,
        "shuffled_control": bool(shuffled_control),
        "protocol": _protocol_record(fold_manifest),
        "primary": _headline(PRIMARY_METRIC, "photograph", primary_values),
        "secondary": {
            **_headline(SECONDARY_METRIC, "group", secondary_values),
            "group_accuracy_per_repeat": [
                record["group_accuracy"] for record in repeat_records
            ],
        },
        "repeats": repeat_records,
        "uncertainty": {
            "interval_source": INTERVAL_SOURCE,
            "across_repeats": {
                "primary_median": float(median(primary_values)),
                "primary_range": [min(primary_values), max(primary_values)],
                "primary_values": primary_values,
                "source": REPEAT_SPREAD_SOURCE,
            },
        },
        "per_class": _per_class(
            fold_manifest, classes, labels, pooled_photograph, pooled_group
        ),
        "confusion_matrix": {
            "photograph": _confusion(pooled_photograph, labels),
            "group": _confusion(pooled_group, labels),
        },
        "cost": _cost(fold_manifest, costs),
        # Read from what training recorded, never recomputed here: evaluation
        # often runs on another machine, so a value derived now would describe
        # this host while claiming to describe the run that produced the model.
        "runtime": runtime,
    }


def contrast_results(
    registry: Sequence[Mapping],
    predictions_by_arm: Mapping[str, Mapping[tuple[int, int], Sequence[Mapping]]],
    fold_manifest: Mapping,
    *,
    alpha: float,
    power: float,
) -> dict:
    """Compute every registered contrast from the arms' pooled predictions.

    Each contrast is an exact McNemar test on group-level correctness, paired on
    the sample group and pooled over the same folds and repeats for both arms.
    The pairing is at the group and not the photograph because photographs of
    one sample are not independent; it pools across repeats rather than counting
    each repeat as a fresh pair for the same reason, since every repeat tests
    the same 77 groups.

    Args:
        registry: The pre-registered contrasts from ``evaluation.contrasts``.
        predictions_by_arm: Arm name to its ``(repeat, fold)`` predictions.
        fold_manifest: The fold manifest every arm was run against.
        alpha: Two-sided significance level.
        power: Power the minimum detectable effect is computed at.

    Returns:
        The contrast record, which the caller writes to ``contrasts.json``.
    """
    correctness = {
        arm: _pooled_group_correctness(predictions)
        for arm, predictions in predictions_by_arm.items()
    }

    computed = []
    for contrast in registry:
        first, second = contrast["arms"]
        for arm in (first, second):
            if arm not in correctness:
                raise ValueError(
                    f"contrast {contrast['name']!r} names arm {arm!r}, which "
                    f"has no predictions. Run it with: python -m src.crossval "
                    f"--version {fold_manifest.get('dataset_version')} "
                    f"--arm {arm}"
                )
        computed.append(
            _one_contrast(contrast, correctness[first], correctness[second], alpha, power)
        )

    _apply_holm_within_families(computed)

    families: dict[str, int] = {}
    for contrast in computed:
        families[contrast["family"]] = families.get(contrast["family"], 0) + 1

    return {
        "dataset_version": fold_manifest.get("dataset_version"),
        "manifest_digest": fold_manifest.get("manifest_digest"),
        "alpha": alpha,
        "power": power,
        "unit": "sample group",
        "families": families,
        "contrasts": computed,
    }


def require_registered_contrast(registry: Sequence[Mapping], name: str) -> Mapping:
    """Return the named contrast, refusing one that was not pre-registered.

    Pre-registration is what stops a result from being read for whichever
    comparison happens to clear, so an unregistered name is a refusal and never
    a contrast computed on the spot.
    """
    if not registry:
        raise ValueError(
            f"no contrast is registered in evaluation.contrasts, so "
            f"{name!r} cannot be evaluated. Register it in ml/config.yaml "
            "before the run"
        )
    for contrast in registry:
        if contrast["name"] == name:
            return contrast
    registered = ", ".join(sorted(entry["name"] for entry in registry))
    raise ValueError(
        f"contrast {name!r} is not registered in evaluation.contrasts, which "
        f"registers: {registered}. A contrast is pre-registered before the run "
        "or it is not evaluated"
    )


def evaluate(
    version: str,
    arm: str,
    config_path: str | None = None,
    contrasts: bool = False,
    contrast_name: str | None = None,
) -> dict:
    """Recompute an arm's metrics, or the registered contrast family.

    Reads what `src.crossval` wrote; it neither trains nor predicts.
    """
    from .crossval import (
        arm_directory,
        first_runtime,
        load_arm_predictions,
        read_fold_metadata,
    )

    # Checked before anything is read or written: `--contrast` without
    # `--contrasts` used to fall through to the metrics path, which reported no
    # contrast at all and overwrote the arm's metrics.json on the way past.
    if contrast_name is not None and not contrasts:
        raise ValueError(
            f"--contrast {contrast_name!r} names a contrast to compute but "
            "--contrasts was not given, so nothing would compute it and the "
            "arm's metrics would be rewritten instead. Pass --contrasts as "
            "well, or drop --contrast"
        )

    cfg = resolve_paths(load_config(config_path))
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    evaluation = cfg["evaluation"]
    output_dir = Path(cfg["export"]["output_dir"]) / version

    if contrasts:
        registry = list(evaluation["contrasts"])
        if contrast_name is not None:
            registry = [require_registered_contrast(registry, contrast_name)]
        if not registry:
            raise ValueError(
                "no contrast is registered in evaluation.contrasts, so there "
                "is nothing to compute. Register the comparison in "
                "ml/config.yaml before the run"
            )

        arms = sorted({name for entry in registry for name in entry["arms"]})
        predictions_by_arm = {
            name: load_arm_predictions(
                arm_directory(output_dir, name), fold_manifest
            )[0]
            for name in arms
        }
        results = contrast_results(
            registry,
            predictions_by_arm,
            fold_manifest,
            alpha=evaluation["alpha"],
            power=evaluation["power"],
        )
        destination = output_dir / CONTRASTS_FILENAME
        destination.parent.mkdir(parents=True, exist_ok=True)
        with open(destination, "w") as handle:
            json.dump(results, handle, indent=2)
        _print_contrasts(results, destination)
        return results

    arm_dir = arm_directory(output_dir, arm)
    predictions, costs = load_arm_predictions(arm_dir, fold_manifest)
    metrics = arm_metrics(
        fold_manifest,
        arm=arm,
        version=version,
        predictions=predictions,
        costs=costs,
        # Read from the artifacts, not from a flag this invocation repeats: a
        # control reported as a real arm is the one mislabelling that would
        # invert E0's verdict.
        shuffled_control=bool(
            read_fold_metadata(arm_dir, 0, 0).get("shuffled_control", False)
        ),
        runtime=first_runtime(arm_dir, fold_manifest),
    )
    with open(arm_dir / METRICS_FILENAME, "w") as handle:
        json.dump(metrics, handle, indent=2)
    _save_confusion_matrix_plot(
        metrics["confusion_matrix"]["group"],
        list(fold_manifest["classes"]),
        arm_dir / "confusion_matrix.png",
    )
    _print_metrics(metrics, arm_dir / METRICS_FILENAME)
    return metrics


def _protocol_record(fold_manifest: Mapping) -> dict:
    return {
        "design": "repeated stratified group k-fold with nested selection",
        "record": "ADR 0020",
        "k": fold_manifest["k"],
        "repeats": fold_manifest["repeats"],
        "seed": fold_manifest["seed"],
        "seed_derivation": fold_manifest["seed_derivation"],
        # The seed reproduces the partition only together with these: the fold
        # generator is a heuristic that has changed between scikit-learn
        # releases.
        "library_versions": fold_manifest.get("library_versions"),
        "dataset_version": fold_manifest.get("dataset_version"),
        "manifest_digest": fold_manifest.get("manifest_digest"),
        "train_only_samples": len(fold_manifest.get("train_only_samples", [])),
    }


def _headline(metric: str, level: str, values: list[float]) -> dict:
    return {
        "metric": metric,
        "level": level,
        "per_repeat": values,
        "median": float(median(values)),
        "range": [min(values), max(values)],
    }


def _photograph_pairs(records: Sequence[Mapping]) -> list[tuple[int, int]]:
    return [
        (int(record["label"]), int(np.argmax(record["probabilities"])))
        for record in records
    ]


def _group_pairs(records: Sequence[Mapping]) -> list[tuple[int, int]]:
    distributions: dict[str, list[Sequence[float]]] = {}
    truth: dict[str, int] = {}
    for record in records:
        distributions.setdefault(record["group"], []).append(record["probabilities"])
        truth[record["group"]] = int(record["label"])
    predicted = group_level_predictions(distributions)
    return [(truth[group], predicted[group]) for group in sorted(predicted)]


def _macro_f1(pairs: Sequence[tuple[int, int]], labels: Sequence[int]) -> float:
    if not pairs:
        return 0.0
    truth, predicted = zip(*pairs)
    return float(
        f1_score(truth, predicted, average="macro", labels=list(labels), zero_division=0)
    )


def _accuracy(pairs: Sequence[tuple[int, int]]) -> float:
    if not pairs:
        return 0.0
    return sum(1 for truth, predicted in pairs if truth == predicted) / len(pairs)


def _confusion(pairs: Sequence[tuple[int, int]], labels: Sequence[int]) -> list[list[int]]:
    if not pairs:
        return [[0] * len(labels) for _ in labels]
    truth, predicted = zip(*pairs)
    return confusion_matrix(truth, predicted, labels=list(labels)).tolist()


def _per_class(
    fold_manifest: Mapping,
    classes: Sequence[str],
    labels: Sequence[int],
    photograph_pairs: Sequence[tuple[int, int]],
    group_pairs: Sequence[tuple[int, int]],
) -> dict:
    """Per-class figures, each carrying the flag that says it is not a result.

    At three to four test groups of a class per fold, a per-class figure is a
    diagnostic and not a number anyone may report (#197). The flag travels
    inside the class record rather than beside the block, so a consumer that
    lifts one class out of the file cannot leave the caveat behind.
    """
    counts = {name: {"groups": 0, "photographs": 0} for name in classes}
    for record in fold_manifest["groups"].values():
        if record["train_only"]:
            continue
        counts[record["class"]]["groups"] += 1
        counts[record["class"]]["photographs"] += len(record["images"])

    photograph = _precision_recall_f1(photograph_pairs, labels)
    group = _precision_recall_f1(group_pairs, labels)

    return {
        name: {
            "headline": False,
            "why": (
                "a per-class figure rests on three to four test groups per fold "
                "and is a diagnostic, not a reportable result (#197)"
            ),
            "groups": counts[name]["groups"],
            "photographs": counts[name]["photographs"],
            "photograph": photograph[index],
            "group": group[index],
        }
        for index, name in enumerate(classes)
    }


def _precision_recall_f1(
    pairs: Sequence[tuple[int, int]], labels: Sequence[int]
) -> list[dict]:
    if not pairs:
        return [{"precision": 0.0, "recall": 0.0, "f1": 0.0} for _ in labels]
    truth, predicted = zip(*pairs)
    precision, recall, f1, _ = precision_recall_fscore_support(
        truth, predicted, labels=list(labels), zero_division=0
    )
    return [
        {"precision": float(p), "recall": float(r), "f1": float(f)}
        for p, r, f in zip(precision, recall, f1)
    ]


def _cost(fold_manifest: Mapping, costs: Mapping[tuple[int, int], Mapping]) -> dict:
    """What the run cost, so the choice of k and R is auditable against it.

    ``None`` rather than zero when nothing was measured: a run whose cost was
    not recorded and a run that cost nothing are different facts.
    """
    seconds: list[float] = []
    trainings = 0
    for record in costs.values():
        trainings += int(record.get("trainings", 0))
        seconds.extend(float(value) for value in record.get("wall_clock_seconds", []))

    return {
        "trainings": trainings if costs else None,
        "wall_clock_seconds_per_training": seconds,
        "wall_clock_seconds_total": sum(seconds) if seconds else None,
        "outer_folds": fold_manifest["k"],
        "repeats": fold_manifest["repeats"],
    }


def _pooled_group_correctness(
    predictions: Mapping[tuple[int, int], Sequence[Mapping]],
) -> dict[str, bool]:
    """Whether each group is right, pooling its distributions over every repeat.

    Pooled rather than counted once per repeat: every repeat tests the same
    groups, so treating each repeat as a fresh pair would multiply the apparent
    evidence by the repeat count without adding a single independent sample.
    """
    distributions: dict[str, list[Sequence[float]]] = {}
    truth: dict[str, int] = {}
    for records in predictions.values():
        for record in records:
            distributions.setdefault(record["group"], []).append(
                record["probabilities"]
            )
            truth[record["group"]] = int(record["label"])
    predicted = group_level_predictions(distributions)
    return {group: predicted[group] == truth[group] for group in predicted}


def _one_contrast(
    contrast: Mapping,
    first_correct: Mapping[str, bool],
    second_correct: Mapping[str, bool],
    alpha: float,
    power: float,
) -> dict:
    first, second = contrast["arms"]
    if set(first_correct) != set(second_correct):
        raise ValueError(
            f"contrast {contrast['name']!r} pairs {first!r} and {second!r}, "
            "which were not scored on the same groups. A paired test needs the "
            "same groups over the same folds and repeats"
        )

    groups = sorted(first_correct)
    favouring_first = sum(
        1 for group in groups if first_correct[group] and not second_correct[group]
    )
    favouring_second = sum(
        1 for group in groups if second_correct[group] and not first_correct[group]
    )
    pairs = len(groups)
    discordant_rate = (favouring_first + favouring_second) / pairs

    return {
        "name": contrast["name"],
        "family": contrast["family"],
        "arms": [first, second],
        "pairs": pairs,
        "unit": "sample group",
        "accuracy": {
            first: sum(first_correct.values()) / pairs,
            second: sum(second_correct.values()) / pairs,
        },
        "discordant": {
            f"favouring_{first}": favouring_first,
            f"favouring_{second}": favouring_second,
        },
        "discordant_rate": discordant_rate,
        "observed_difference": (favouring_first - favouring_second) / pairs,
        "p_value": mcnemar_exact_p_value(favouring_first, favouring_second),
        "alpha": alpha,
        "power": power,
        "minimum_detectable_effect": mcnemar_minimum_detectable_effect(
            pairs, discordant_rate, alpha, power
        ),
        "minimum_detectable_effect_note": (
            "smallest difference in group-level accuracy the exact McNemar test "
            "would find at this observed discordance; a difference below it has "
            "not been shown. null when no rejection region exists at all"
        ),
    }


def _apply_holm_within_families(contrasts: list[dict]) -> None:
    """Correct each registered family separately, in place.

    Within the family and not across all contrasts: the primary family is every
    arm against the shuffled control, and correcting the one named secondary
    against it would penalise a comparison that answers a different question.
    """
    by_family: dict[str, list[dict]] = {}
    for contrast in contrasts:
        by_family.setdefault(contrast["family"], []).append(contrast)

    for family in by_family.values():
        adjusted = holm_adjust([contrast["p_value"] for contrast in family])
        for contrast, value in zip(family, adjusted):
            contrast["p_value_holm"] = value
            contrast["family_size"] = len(family)


def _print_metrics(metrics: Mapping, path: Path) -> None:
    print(f"\n{'=' * 50}")
    print(f"{metrics['arm']} on {metrics['version']} — {metrics['protocol']['design']}")
    print(f"{'=' * 50}")
    primary = metrics["primary"]
    print(
        f"primary  {primary['metric']}: median {primary['median']:.4f}, "
        f"range {primary['range'][0]:.4f}-{primary['range'][1]:.4f} over "
        f"{len(primary['per_repeat'])} repeat(s)"
    )
    for record in metrics["repeats"]:
        interval = record["wilson_interval_95_group_accuracy"]
        print(
            f"  repeat {record['repeat']} (seed {record['seed']}): "
            f"group accuracy {record['group_accuracy']:.4f} "
            f"[{interval['low']:.4f}, {interval['high']:.4f}] "
            f"over {record['groups']} group(s)"
        )
    cost = metrics["cost"]
    print(f"cost: {cost['trainings']} training(s), {cost['wall_clock_seconds_total']}s")
    print("per-class figures are recorded with headline=false and are not results")
    print(f"metrics saved to {path}")


def _print_contrasts(results: Mapping, path: Path) -> None:
    print(f"\n{'=' * 50}")
    print(f"Pre-registered contrasts — unit: {results['unit']}")
    print(f"{'=' * 50}")
    for contrast in results["contrasts"]:
        mde = contrast["minimum_detectable_effect"]
        rendered = "not detectable at any size" if mde is None else f"{mde:.4f}"
        print(
            f"{contrast['name']} ({contrast['family']}): "
            f"difference {contrast['observed_difference']:+.4f}, "
            f"p {contrast['p_value']:.4g}, Holm {contrast['p_value_holm']:.4g}, "
            f"MDE {rendered} over {contrast['pairs']} pair(s)"
        )
    print(f"contrasts saved to {path}")


def _save_confusion_matrix_plot(cm: list, classes: list[str], path: Path) -> None:
    """Save confusion matrix heatmap as PNG."""
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import seaborn as sns

        fig, ax = plt.subplots(figsize=(8, 6))
        sns.heatmap(
            np.array(cm),
            annot=True,
            fmt="d",
            cmap="Blues",
            xticklabels=classes,
            yticklabels=classes,
            ax=ax,
        )
        ax.set_xlabel("Predicted")
        ax.set_ylabel("True")
        ax.set_title("Confusion Matrix — group level, pooled over repeats")
        plt.tight_layout()
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"Confusion matrix saved to {path}")
    except ImportError:
        print("matplotlib/seaborn not available, skipping confusion matrix plot")


def main():
    parser = argparse.ArgumentParser(
        description="Report the k-fold evaluation of a trained arm"
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument("--arm", type=str, default="cnn", help="Experimental arm")
    parser.add_argument(
        "--contrasts",
        action="store_true",
        help="Compute the pre-registered contrasts instead of one arm's metrics",
    )
    parser.add_argument(
        "--contrast",
        type=str,
        default=None,
        help="Restrict --contrasts to one registered contrast, by name",
    )
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    evaluate(
        args.version,
        args.arm,
        args.config,
        contrasts=args.contrasts,
        contrast_name=args.contrast,
    )


if __name__ == "__main__":
    main()
