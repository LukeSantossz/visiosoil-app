"""Does a phone's look in training carry the classifier to the field?
(SPEC 0175)

Four arms fit the released procedure, `fit_probe` at the release's chosen `C`,
on different training sides:

    A0  the archive, as released
    A1  the archive and phone variants of each archive photograph
    A2  A0 and phone variants of the field photographs of every other soil
    A3  A1 and A2's field variants

Each field soil sample is held out in turn and scored on its own unaugmented
photographs, by the app's aggregation: the mean of the patch probabilities. The
archive is guarded on repeat 0 of the fold manifest, augmented on the training
side only. The adoption rule is fixed here, before any run:

    an arm is adoptable when its field macro accuracy beats A0's by at least
    0.20 and its archive accuracy is no more than 0.02 below A0's; of the
    adoptable arms A1 is preferred, as the only one owing nothing to the
    field soils.

Adopting is a release spec of its own. This study writes no contract.

Run from the `ml/` directory, on the machine that holds the archive:

    python -m src.field_study --version v1 --field <export dir>
"""

from __future__ import annotations

import argparse
import json
from functools import partial
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np

from .arms.probe import _photograph_accuracy, _predict, fit_probe, _patch_matrix
from .config import load_config, resolve_paths
from .dataset import fold_split, load_folds_for_config
from .field import DEFAULT_SEED, archive_features, field_features, load_field_export
from .release import RELEASE_DIRNAME, SELECTION_FILENAME

ARMS = ("A0", "A1", "A2", "A3")
_ARCHIVE_VARIANTS = ("A1", "A3")
_FIELD_VARIANTS = ("A2", "A3")
#: Preferred first among adoptable arms.
PREFERENCE = ("A1", "A2", "A3")

FIELD_GAIN = 0.20
ARCHIVE_LOSS = 0.02
_TOLERANCE = 1e-9

DEFAULT_VARIANTS = 8
STUDY_DIRNAME = "field_study"
REPORT_FILENAME = "report.json"


def variants_of(entries: Sequence[Mapping], count: int) -> list[dict]:
    """``count`` variant entries of each of ``entries``, each keyed apart so a
    cache never confuses a variant with its source."""
    return [
        {**entry, "path": f"{entry['path']}::aug{k}", "image": entry.get("image", entry["path"]), "variant": k}
        for entry in entries
        for k in range(count)
    ]


def held_out_sides(
    arm: str,
    archive: Sequence[Mapping],
    field: Sequence[Mapping],
    held_out: str,
    *,
    variants: int,
) -> tuple[list[dict], list[dict]]:
    """``arm``'s training side with ``held_out`` withheld, and that sample's
    own photographs, unaugmented, as the scored side."""
    train = [dict(entry) for entry in archive]
    if arm in _ARCHIVE_VARIANTS:
        train += variants_of(archive, variants)
    if arm in _FIELD_VARIANTS:
        others = [entry for entry in field if entry["sample"] != held_out]
        train += variants_of(others, variants)
    test = [dict(entry) for entry in field if entry["sample"] == held_out]
    return train, test


def archive_guard_sides(
    arm: str,
    fold_manifest: Mapping,
    field: Sequence[Mapping],
    *,
    variants: int,
) -> list[tuple[list[dict], list[dict]]]:
    """Repeat 0's folds, ``arm``'s augmentation on each training side and
    none on its test side."""
    sides = []
    for fold in range(int(fold_manifest["k"])):
        split = fold_split(fold_manifest, 0, fold)
        train = [dict(entry) for entry in split["train"]]
        if arm in _ARCHIVE_VARIANTS:
            train += variants_of(split["train"], variants)
        if arm in _FIELD_VARIANTS:
            train += variants_of(field, variants)
        sides.append((train, [dict(entry) for entry in split["test"]]))
    return sides


def release_c(models_dir: Path | str, version: str) -> float:
    """The `C` the release of ``version`` chose."""
    path = Path(models_dir) / version / RELEASE_DIRNAME / SELECTION_FILENAME
    if not path.exists():
        raise FileNotFoundError(
            f"{path} does not exist; fit the release first with "
            f"`python -m src.release --version {version} --model-version <v>`"
        )
    return float(json.loads(path.read_text(encoding="utf-8"))["chosen_c"])


def adoptable(arm: Mapping, baseline: Mapping) -> bool:
    """The rule written in this module's docstring, applied to one arm."""
    gains = arm["field_macro"] - baseline["field_macro"] >= FIELD_GAIN - _TOLERANCE
    keeps = baseline["archive"] - arm["archive"] <= ARCHIVE_LOSS + _TOLERANCE
    return bool(gains and keeps)


def _field_scores(records: list[dict], classes: Sequence[str]) -> dict:
    def accuracy(subset: list[dict]) -> dict:
        right = [r for r in subset if r["predicted"] == r["label"]]
        per_class = {}
        for index, name in enumerate(classes):
            of_class = [r for r in subset if r["label"] == index]
            if of_class:
                per_class[name] = sum(r["predicted"] == index for r in of_class) / len(of_class)
        return {
            "photographs": len(subset),
            "accuracy": len(right) / len(subset) if subset else None,
            "macro": float(np.mean(list(per_class.values()))) if per_class else None,
            "per_class": per_class,
        }

    samples = sorted({r["sample"] for r in records})
    confusion = [[0] * len(classes) for _ in classes]
    for r in records:
        confusion[r["label"]][r["predicted"]] += 1
    return {
        "all": accuracy(records),
        "native": accuracy([r for r in records if not r["upsampled"]]),
        "per_sample": {
            sample: accuracy([r for r in records if r["sample"] == sample])["accuracy"]
            for sample in samples
        },
        "confusion": confusion,
    }


def run_study(
    cfg: Mapping,
    fold_manifest: Mapping,
    field: Sequence[Mapping],
    *,
    c: float,
    archive_featuriser=archive_features,
    field_featuriser=field_features,
    variants: int = DEFAULT_VARIANTS,
) -> dict:
    """Every arm, every held-out sample and the archive guard, as a report."""

    def featuriser(entry, cfg):
        if "sample" in entry:
            return field_featuriser(entry, cfg)
        return archive_featuriser(entry, cfg)

    cache: dict[str, np.ndarray] = {}
    archive = [entry for side in fold_split(fold_manifest, 0, 0).values() for entry in side]
    samples = sorted({entry["sample"] for entry in field})
    arms = {}
    for arm in ARMS:
        records = []
        for held_out in samples:
            train, test = held_out_sides(arm, archive, field, held_out, variants=variants)
            features, labels, _ = _patch_matrix(train, cfg, featuriser, cache)
            model = fit_probe(features, labels, c=c)
            by_path = {entry["path"]: entry for entry in test}
            for record in _predict(model, test, cfg, featuriser, cache):
                entry = by_path[record["path"]]
                records.append(
                    {
                        "path": record["path"],
                        "sample": entry["sample"],
                        "upsampled": entry["upsampled"],
                        "label": record["label"],
                        "predicted": int(np.argmax(record["probabilities"])),
                    }
                )
        guard = []
        for train, test in archive_guard_sides(arm, fold_manifest, field, variants=variants):
            features, labels, _ = _patch_matrix(train, cfg, featuriser, cache)
            model = fit_probe(features, labels, c=c)
            guard.append(_photograph_accuracy(model, test, cfg, featuriser, cache))
        field_scores = _field_scores(records, cfg["classes"])
        arms[arm] = {
            "field": field_scores,
            "field_macro": field_scores["all"]["macro"],
            "archive": float(np.mean(guard)),
        }
        print(
            f"{arm}: field macro {arms[arm]['field_macro']:.3f}, "
            f"archive {arms[arm]['archive']:.3f}"
        )

    passing = [arm for arm in ARMS[1:] if adoptable(arms[arm], arms["A0"])]
    preferred = next((arm for arm in PREFERENCE if arm in passing), None)
    return {
        "c": float(c),
        "variants": int(variants),
        "samples": samples,
        "rule": {"field_gain": FIELD_GAIN, "archive_loss": ARCHIVE_LOSS, "field_score": "all.macro"},
        "arms": arms,
        "adoptable": passing,
        "preferred": preferred,
    }


def write_report(report: Mapping, directory: Path | str) -> Path:
    """Writes ``report.json`` and prints the arms' table."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / REPORT_FILENAME
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("| Arm | Field macro (all) | Field macro (native) | Archive |")
    print("|---|---|---|---|")
    for arm, scores in report["arms"].items():
        native = scores["field"]["native"]["macro"]
        print(
            f"| {arm} | {scores['field_macro']:.3f} | "
            f"{'-' if native is None else f'{native:.3f}'} | {scores['archive']:.3f} |"
        )
    print(f"adoptable: {report['adoptable'] or 'none'}; preferred: {report['preferred']}")
    return path


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Measure phone-camera augmentation and field photographs by "
        "holding one soil sample out at a time (SPEC 0175)."
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument("--field", type=str, required=True, help="The app's field export (SPEC 0174)")
    parser.add_argument("--variants", type=int, default=DEFAULT_VARIANTS, help="Variants per photograph")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="The variants' seed")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()
    if args.variants < 1:
        parser.error("--variants must be at least 1")

    cfg = resolve_paths(load_config(args.config))
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    models_dir = Path(cfg["export"]["output_dir"])
    report = run_study(
        cfg,
        fold_manifest,
        load_field_export(args.field, cfg),
        c=release_c(models_dir, args.version),
        archive_featuriser=partial(archive_features, seed=args.seed),
        field_featuriser=partial(field_features, seed=args.seed),
        variants=args.variants,
    )
    path = write_report(report, models_dir / args.version / STUDY_DIRNAME)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
