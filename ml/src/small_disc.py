"""Whether a soil disc too small for nine patches loses quality (SPEC 0141).

The app reads a soil disc of 46.5 to 51.4 mm on the first real photographs, and
the floor of nine patches needs 58.5 mm. Below it, a disc holds the centred
five (from 49.9 mm) or the half-stride block of four (from 43.9 mm). This study
measures what scoring from those patches costs, on the only labelled data there
is: the archive's dish photographs, through the released descriptor arm's own
cross-validation.

For each of the arm's 25 folds it refits the probe on the training side's full
grids, at the C that fold's selection chose, and scores each held-out photograph
three ways:

- **full**: its own grid, which must reproduce the stored predictions;
- **five**: the centred grid of a 51.0 mm disc;
- **four**: the half-stride grid of a 47.5 mm disc.

The small grids are cut by the training cut itself, around the dish's measured
centre, with only the disc diameter replaced. Every criterion and the decision
table are SPEC 0141's, fixed before the run. Nothing is retrained and no
weight is written: the study writes `small_disc_study.json` beside the arm's
`metrics.json`.

Run from the `ml/` directory:

    python -m src.small_disc --version v1
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Mapping

import numpy as np

from .arms.descriptors import descriptor_features
from .arms.probe import _patch_matrix, _predict, fit_probe
from .descriptors import GROUPS, describe_patch

STUDY_FILENAME = "small_disc_study.json"

#: Each small patch set, by the disc diameter in millimetres that yields it. Any
#: disc from 49.9 to 58.5 mm carries the same centred five, and any from 43.9 to
#: 49.9 mm the same half-stride four, so one diameter stands for each range.
PATCH_SETS = {"five": 51.0, "four": 47.5}

#: The floor the small sets are cut at: the lowest the study can propose.
STUDY_FLOOR = 4

#: How far below the full grid's median photograph macro-F1 a set may score.
MAX_MACRO_F1_DROP = 0.02

#: The share of held-out predictions, pooled over every fold, whose top class a
#: set must keep.
MIN_AGREEMENT = 0.90

#: How closely the full grid must reproduce the stored predictions.
REPRODUCTION_TOLERANCE = 1e-9

#: The floor each outcome of the decision table ships.
FLOOR_IF_BOTH_PASS = 4
FLOOR_IF_ONLY_FIVE_PASSES = 5
FLOOR_IF_FIVE_FAILS = 9


def study_config(cfg: Mapping) -> dict:
    """``cfg`` with the floor lowered to the study's, and nothing else changed."""
    study = copy.deepcopy(dict(cfg))
    study["preprocessing"]["min_patches"] = STUDY_FLOOR
    return study


def simulated_measurement(measurement: Mapping[str, float], disc_mm: float) -> dict:
    """The dish's measurement with its disc replaced by one of ``disc_mm``.

    The diameter is in the photograph's own pixels, as the manifest records it,
    so the cut resamples it to the canonical scale with the photograph.
    """
    simulated = dict(measurement)
    simulated["disc_diameter_px"] = disc_mm / measurement["mm_per_px"]
    return simulated


def set_featuriser(disc_mm: float):
    """The descriptor arm's featuriser, cut from a disc of ``disc_mm``."""

    def featurise(entry: Mapping, cfg: Mapping) -> np.ndarray:
        from .dataset import _measurement_of, _photograph_patches, photograph_scale

        measurement = _measurement_of(entry, photograph_scale(cfg))
        patches = _photograph_patches(
            entry, simulated_measurement(measurement, disc_mm), study_config(cfg)
        )
        return np.stack([describe_patch(patch, groups=GROUPS) for patch in patches])

    return featurise


def rescore_fold(
    cfg: Mapping,
    fold_manifest: Mapping,
    arm_dir: Path | str,
    *,
    repeat: int,
    fold: int,
    caches: dict[str, dict] | None = None,
) -> dict:
    """Refit one fold on its full grids and score its test side three ways.

    ``caches`` holds each featuriser's patch features by path. Features are a
    function of the pixels alone, so one cache serves every fold of the run.
    """
    from .crossval import SELECTION_AUDIT_FILENAME, fold_directory
    from .dataset import fold_split

    caches = {} if caches is None else caches
    audit_path = fold_directory(arm_dir, repeat, fold) / SELECTION_AUDIT_FILENAME
    with open(audit_path) as handle:
        chosen_c = float(json.load(handle)["chosen"]["C"])

    split = fold_split(fold_manifest, repeat, fold)
    full_cache = caches.setdefault("full", {})
    features, labels, _ = _patch_matrix(split["train"], cfg, descriptor_features, full_cache)
    model = fit_probe(features, labels, c=chosen_c)

    scored = {"C": chosen_c}
    scored["full"] = _predict(model, split["test"], cfg, descriptor_features, full_cache)
    for name, disc_mm in PATCH_SETS.items():
        scored[name] = _predict(
            model, split["test"], cfg, set_featuriser(disc_mm), caches.setdefault(name, {})
        )
    return scored


def require_reproduction(
    scored: Mapping[tuple[int, int], list[Mapping]],
    stored: Mapping[tuple[int, int], list[Mapping]],
) -> None:
    """Refuse a full-grid rescoring that differs from the stored predictions.

    If the refit does not reproduce the released arm, every figure the study
    would go on to report describes some other model.
    """
    for key, records in scored.items():
        mine = {record["path"]: record["probabilities"] for record in records}
        theirs = {record["path"]: record["probabilities"] for record in stored[key]}
        if mine.keys() != theirs.keys():
            raise ValueError(
                f"repeat {key[0]} fold {key[1]} scored {len(mine)} photograph(s) "
                f"and the stored predictions hold {len(theirs)}; this is not the "
                "released arm, and the study stops here"
            )
        for path, probabilities in mine.items():
            drift = np.max(np.abs(np.asarray(probabilities) - np.asarray(theirs[path])))
            if not drift <= REPRODUCTION_TOLERANCE:
                raise ValueError(
                    f"repeat {key[0]} fold {key[1]}: {path} differs from its stored "
                    f"prediction by {drift:.3g}, over {REPRODUCTION_TOLERANCE}; this "
                    "is not the released arm, and the study stops here"
                )


def top1_agreement(
    full: Mapping[tuple[int, int], list[Mapping]],
    other: Mapping[tuple[int, int], list[Mapping]],
) -> float:
    """The share of held-out predictions whose top class ``other`` keeps.

    Pooled over every fold, so a photograph counts once per repeat.
    """
    kept = total = 0
    for key, records in full.items():
        theirs = {record["path"]: record["probabilities"] for record in other[key]}
        for record in records:
            total += 1
            kept += int(np.argmax(record["probabilities"])) == int(
                np.argmax(theirs[record["path"]])
            )
    return kept / total


def set_verdict(*, full_median: float, set_median: float, agreement: float) -> dict:
    """SPEC 0141's two criteria for one patch set, and whether both hold."""
    drop = full_median - set_median
    return {
        "macro_f1_drop": drop,
        "agreement": agreement,
        "macro_f1_passes": drop <= MAX_MACRO_F1_DROP,
        "agreement_passes": agreement >= MIN_AGREEMENT,
        "passes": drop <= MAX_MACRO_F1_DROP and agreement >= MIN_AGREEMENT,
    }


def decide_floor(*, five_passes: bool, four_passes: bool) -> int:
    """SPEC 0141's decision table: the floor the result ships."""
    if not five_passes:
        return FLOOR_IF_FIVE_FAILS
    return FLOOR_IF_BOTH_PASS if four_passes else FLOOR_IF_ONLY_FIVE_PASSES


def small_disc_study(cfg: Mapping, fold_manifest: Mapping, arm_dir: Path | str) -> dict:
    """Run the study over every fold of the arm, stopping at a failed reproduction."""
    from .crossval import load_arm_predictions
    from .evaluate import arm_metrics
    from .patches import patch_geometry

    stored, _ = load_arm_predictions(arm_dir, fold_manifest)
    caches: dict[str, dict] = {}
    scored: dict[str, dict] = {"full": {}, **{name: {} for name in PATCH_SETS}}
    chosen: dict[str, float] = {}

    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            print(f"repeat {repeat} fold {fold}")
            result = rescore_fold(
                cfg, fold_manifest, arm_dir, repeat=repeat, fold=fold, caches=caches
            )
            # Checked fold by fold, so a refit that is not the released arm
            # stops the run before it spends the rest of it.
            require_reproduction({(repeat, fold): result["full"]}, stored)
            chosen[f"{repeat}/{fold}"] = result["C"]
            for name in scored:
                scored[name][(repeat, fold)] = result[name]

    version = cfg["data"]["dataset_version"]
    metrics = {
        name: arm_metrics(
            fold_manifest,
            arm=f"descriptors/{name}",
            version=version,
            predictions=predictions,
            costs={},
        )
        for name, predictions in scored.items()
    }

    def headline(name: str) -> dict:
        return {
            "photograph_macro_f1": metrics[name]["primary"],
            "group_macro_f1": {
                key: metrics[name]["secondary"][key] for key in ("per_repeat", "median", "range")
            },
        }

    full_median = metrics["full"]["primary"]["median"]
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    sets = {}
    for name, disc_mm in PATCH_SETS.items():
        geometry = patch_geometry(
            region_diameter_px=disc_mm / canonical,
            input_size=cfg["data"]["image_size"],
            canonical_mm_per_px=canonical,
            min_patches=STUDY_FLOOR,
            stride_fraction=cfg["preprocessing"]["patch_stride_fraction"],
        )
        sets[name] = {
            "disc_mm": disc_mm,
            "offsets_px": [list(offset) for offset in geometry.offsets],
            **headline(name),
            **set_verdict(
                full_median=full_median,
                set_median=metrics[name]["primary"]["median"],
                agreement=top1_agreement(scored["full"], scored[name]),
            ),
        }

    return {
        "spec": "SPEC 0141",
        "version": version,
        "arm": "descriptors",
        "criteria": {
            "max_macro_f1_drop": MAX_MACRO_F1_DROP,
            "min_agreement": MIN_AGREEMENT,
            "reproduction_tolerance": REPRODUCTION_TOLERANCE,
        },
        "reproduced": True,
        "chosen_c": chosen,
        "full": headline("full"),
        "sets": sets,
        "floor": decide_floor(
            five_passes=sets["five"]["passes"], four_passes=sets["four"]["passes"]
        ),
    }


def _print_summary(study: Mapping, path: Path) -> None:
    print(f"full: median photograph macro-F1 {study['full']['photograph_macro_f1']['median']:.4f}")
    for name, record in study["sets"].items():
        print(
            f"{name} ({record['disc_mm']} mm): median "
            f"{record['photograph_macro_f1']['median']:.4f}, drop "
            f"{record['macro_f1_drop']:+.4f}, agreement {record['agreement']:.3f} -> "
            f"{'passes' if record['passes'] else 'fails'}"
        )
    print(f"floor: {study['floor']}")
    print(f"study saved to {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", default="v1", help="Dataset version")
    parser.add_argument("--config", default=None, help="Path to config.yaml")
    args = parser.parse_args()

    from .config import load_config, resolve_paths
    from .crossval import arm_directory
    from .dataset import load_folds_for_config

    cfg = resolve_paths(load_config(args.config))
    fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    arm_dir = arm_directory(Path(cfg["export"]["output_dir"]) / args.version, "descriptors")

    study = small_disc_study(cfg, fold_manifest, arm_dir)
    destination = arm_dir / STUDY_FILENAME
    with open(destination, "w") as handle:
        json.dump(study, handle, indent=2)
    _print_summary(study, destination)


if __name__ == "__main__":
    main()
