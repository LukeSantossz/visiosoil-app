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
)
from src.dataset import (  # noqa: E402
    drop_refused_photographs,
    fold_split,
    library_versions,
)
from src.manifest import ARCHIVE_CLASSES, dataset_root, read_manifest  # noqa: E402
from src.population_probe import (  # noqa: E402
    POPULATION_PROBE_ARM,
    majority_prior,
    population_images,
    probe_directory,
    probe_featuriser,
    probe_partition,
    relabel_by_population,
    write_probe_report,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="dataset version; defaults to the config")
    parser.add_argument("--config", help="path to config.yaml")
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

    # The patches the arms see, which excludes the ones the grid refuses. A
    # probe over a different set of photographs would answer a question about
    # that set.
    entries = [
        {"path": path}
        for paths in population_images(manifest, refused=()).values()
        for path in paths
    ]
    _, refused = drop_refused_photographs(entries, cfg)
    images = population_images(manifest, refused=refused)
    populations = sorted(images)
    prior = majority_prior(images)
    by_path = {
        path: population for population, paths in images.items() for path in paths
    }

    directory = probe_directory(Path(cfg["export"]["output_dir"]) / version)
    directory.mkdir(parents=True, exist_ok=True)
    splits_dir = directory / "splits"
    splits_dir.mkdir(parents=True, exist_ok=True)

    print(
        f"{sum(len(paths) for paths in images.values())} photograph(s) in "
        f"{len(populations)} capture population(s); {len(refused)} refused by "
        f"the patch grid"
    )
    print(f"majority-population prior at group level: {prior:.3f}")

    fold_manifest = probe_partition(cfg, manifest, str(splits_dir), refused)
    # Written by `create_folds` under the probe's own directory, never over the
    # arms' `splits.json`: the two partitions answer different questions and a
    # run that read one for the other would be scoring the wrong thing.
    assert (splits_dir / FOLD_MANIFEST_FILENAME).exists()

    probe_cfg = {**cfg, "classes": populations}
    from src.arms.probe import probe_fold  # noqa: E402  (needs the training stack)

    started = time.monotonic()
    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
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
            )
    print(f"\nprobe finished in {time.monotonic() - started:.1f}s")

    predictions, _ = load_arm_predictions(directory, fold_manifest)
    pairs = _group_pairs(predictions)

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
