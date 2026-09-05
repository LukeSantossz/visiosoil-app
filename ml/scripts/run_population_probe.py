"""Run the capture-population probe over a dataset version (SPEC 0055).

Asks whether the capture population is recoverable from the same patches the
texture arms see. It is a **diagnostic about the data**, not an arm: it takes no
entry in `evaluation.contrasts`, is Holm-corrected with nothing, and writes its
own partition and report under `models/<version>/population_probe/`.

**Read it before the E0 verdict.** If the population is recoverable, the gate's
result may be reading a compression signature rather than soil, and that is a
fact about how to read E0 rather than a correction to it.

Run from the `ml/` directory:

    python scripts/run_population_probe.py
    python scripts/run_population_probe.py --version v1

Exit codes: 0 the probe ran and its report was written — **whichever way it
read** — and 1 the version could not be probed.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.crossval import (  # noqa: E402
    FOLD_MANIFEST_FILENAME,
    load_arm_predictions,
    plan_arm_run,
    require_uniform_runtime,
)
from src.dataset import library_versions  # noqa: E402
from src.manifest import ARCHIVE_CLASSES, dataset_root, read_manifest  # noqa: E402
from src.population_probe import (  # noqa: E402
    POPULATION_PROBE_ARM,
    majority_prior,
    population_images,
    probe_directory,
    probe_featuriser,
    probe_partition,
    probe_refusals,
    write_probe_report,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="dataset version; defaults to the config")
    parser.add_argument("--config", help="path to config.yaml")
    parser.add_argument(
        "--force",
        action="store_true",
        help="recompute every fold, discarding artifacts already on disk",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    version = args.version or cfg["data"]["dataset_version"]

    try:
        root = Path(dataset_root(cfg["data"]["datasets_dir"], version))
        manifest = read_manifest(root, ARCHIVE_CLASSES)
    except (ValueError, FileNotFoundError) as error:
        print(f"cannot probe {version}: {error}", file=sys.stderr)
        return 1

    # The patches the arms see, and only those. Two restrictions, and the probe
    # is unreadable without either: the classes the model emits — four, not the
    # archive's five (ADR 0016) — and the photographs the patch grid can cut. A
    # probe over a different set of photographs would answer a question about
    # that set.
    classes = cfg["classes"]
    refused = probe_refusals(cfg, manifest, classes)
    images = population_images(manifest, refused=refused, classes=classes)
    populations = sorted(images)

    directory = probe_directory(Path(cfg["export"]["output_dir"]) / version)
    directory.mkdir(parents=True, exist_ok=True)
    splits_dir = directory / "splits"
    splits_dir.mkdir(parents=True, exist_ok=True)

    print(
        f"{sum(len(paths) for paths in images.values())} photograph(s) in "
        f"{len(populations)} capture population(s); {len(refused)} refused by "
        f"the patch grid"
    )

    fold_manifest = probe_partition(
        cfg, manifest, str(splits_dir), refused, classes=classes
    )
    # After the partition and from it, because the unit of the prior has to be
    # the unit of the accuracy it is compared against.
    prior = majority_prior(fold_manifest)
    print(
        f"{len(fold_manifest['groups'])} sample group(s); majority-population "
        f"prior at group level: {prior:.3f}"
    )
    # Written by `create_folds` under the probe's own directory, never over the
    # arms' `splits.json`: the two partitions answer different questions and a
    # run that read one for the other would be scoring the wrong thing.
    assert (splits_dir / FOLD_MANIFEST_FILENAME).exists()

    # `classes` is what the probe predicts, and here it is the capture
    # populations rather than the texture classes. That one substitution is the
    # whole difference between this and the descriptor arm: same patches, same
    # features, same probe, same nesting — a different label. Overriding the key
    # rather than threading a second one through `probe_fold` keeps the arm's
    # code path literally unchanged, which is what lets the probe be read as a
    # statement about the representation the arms use.
    probe_cfg = {**cfg, "classes": populations}
    from src.arms.probe import probe_fold  # noqa: E402  (needs the training stack)

    # The same classification the arms get (SPEC 0056). This loop is the one an
    # interruption actually killed, at 17 of 25 folds, so a guard that protected
    # only `run_arm` would leave the probe exactly where it was.
    try:
        plan = plan_arm_run(
            directory,
            fold_manifest,
            cfg=probe_cfg,
            arm=POPULATION_PROBE_ARM,
            shuffled_control=False,
            force=args.force,
        )
    except ValueError as refusal:
        print(refusal, file=sys.stderr)
        return 1
    if plan["reuse"]:
        print(
            f"{len(plan['reuse'])} fold(s) already computed under this "
            f"configuration and manifest; reusing them untouched."
        )

    started = time.monotonic()
    for repeat, fold in plan["run"]:
        print(
            f"\n=== population probe: repeat {repeat + 1}/"
            f"{fold_manifest['repeats']}, fold {fold + 1}/{fold_manifest['k']} ==="
        )
        probe_fold(
            probe_cfg,
            fold_manifest,
            arm_dir=directory,
            arm=POPULATION_PROBE_ARM,
            repeat=repeat,
            fold=fold,
            featuriser=probe_featuriser,
            verify=False,
            forced=args.force,
        )
    print(f"\nprobe finished in {time.monotonic() - started:.1f}s")

    # An arm assembled from two library versions is one arm in name only, and
    # resuming is not what makes that possible.
    require_uniform_runtime(directory, fold_manifest)
    predictions, _ = load_arm_predictions(directory, fold_manifest)
    pairs = _group_pairs(predictions)
    # The prior was counted over the partition's groups, so the accuracy has to
    # be counted over the same ones. A group the folds hold and no fold scored
    # would leave the two denominators quietly different.
    if len(pairs) != len(fold_manifest["groups"]):
        print(
            f"{len(pairs)} group(s) were scored out of "
            f"{len(fold_manifest['groups'])} in the partition, so the prior and "
            f"the accuracy would be counted over different sets",
            file=sys.stderr,
        )
        return 1

    report = write_probe_report(
        directory,
        version=version,
        manifest_digest=manifest.digest,
        populations=populations,
        pairs=pairs,
        prior=prior,
        seeds=fold_manifest["seeds"],
        library_versions=library_versions(),
    )

    verdict = report["verdict"]
    print(
        f"\ngroup-level accuracy {verdict['accuracy']:.3f} "
        f"[{verdict['lower_bound']:.3f}, {verdict['upper_bound']:.3f}] "
        f"against a prior of {verdict['prior']:.3f}"
    )
    for population, recall in report["recall"].items():
        shown = "not scored" if recall is None else f"{recall:.3f}"
        print(f"  recall {population}: {shown}")
    print(f"\n{verdict['reading']}")
    return 0


def _group_pairs(predictions) -> list[tuple[int, int]]:
    """Pool every fold's photographs into one (truth, predicted) per group.

    Through `evaluate.group_level_predictions`, so the probe's group prediction
    is formed exactly as an arm's is and the two numbers mean the same thing.
    """
    from src.evaluate import group_level_predictions

    distributions: dict[str, list] = {}
    truth: dict[str, int] = {}
    for records in predictions.values():
        for record in records:
            distributions.setdefault(record["group"], []).append(
                record["probabilities"]
            )
            truth[record["group"]] = int(record["label"])
    predicted = group_level_predictions(distributions)
    return [(truth[group], predicted[group]) for group in sorted(predicted)]


if __name__ == "__main__":
    raise SystemExit(main())
