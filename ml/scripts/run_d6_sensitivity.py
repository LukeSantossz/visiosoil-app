"""Run the D6 sensitivity comparison over a dataset version (SPEC 0057).

Four runs over **one partition**: the descriptor arm and the incumbent CNN, each
with the capture population SPEC 0040 D6 restricts in its training side and
without it. Two paired contrasts, each read by the rule SPEC 0057 fixed before
any of them ran.

**Read it before ADR 0021**, which is the decision it exists to inform, and which
this script deliberately does not take.

The partition is untouched by construction, so whichever configuration ADR 0021
settles on is the E0 gate's arm already computed — `crossval.run_arm` will reuse
it under SPEC 0056's rule, after checking that the configuration, the manifest
digest and the library versions have not moved.

Run from the `ml/` directory:

    python scripts/run_d6_sensitivity.py
    python scripts/run_d6_sensitivity.py --version v1 --arms descriptors

Exit codes: 0 the comparison ran and its report was written — **whichever way it
read** — and 1 it could not be run.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.crossval import (  # noqa: E402
    arm_directory,
    first_runtime,
    load_arm_predictions,
    require_uniform_runtime,
    run_arm,
)
from src.dataset import load_folds_for_config  # noqa: E402
from src.evaluate import pooled_group_correctness  # noqa: E402
from src.sensitivity import (  # noqa: E402
    CNN_PAIR,
    DESCRIPTOR_PAIR,
    sensitivity_contrast,
    write_sensitivity_report,
)

#: Which pair each `--arms` choice runs. Named rather than positional so a run
#: that does only the cheap half says so in its own command line.
PAIRS = {
    "descriptors": (DESCRIPTOR_PAIR,),
    "cnn": (CNN_PAIR,),
    "both": (DESCRIPTOR_PAIR, CNN_PAIR),
}

SENSITIVITY_DIRNAME = "d6_sensitivity"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="dataset version; defaults to the config")
    parser.add_argument("--config", help="path to config.yaml")
    parser.add_argument(
        "--arms",
        choices=sorted(PAIRS),
        default="both",
        help="which pair(s) to run (default: both, about fifteen hours)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="recompute every fold of every arm, discarding what is on disk",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    version = args.version or cfg["data"]["dataset_version"]
    evaluation = cfg["evaluation"]

    try:
        fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    except (ValueError, FileNotFoundError) as error:
        print(f"cannot compare over {version}: {error}", file=sys.stderr)
        return 1

    output_dir = Path(cfg["export"]["output_dir"]) / version
    pairs = PAIRS[args.arms]

    started = time.monotonic()
    for base, withheld in pairs:
        for arm in (base, withheld):
            print(f"\n=== {arm} over {version} ===")
            try:
                run_arm(version, arm, args.config, force=args.force)
            except ValueError as refusal:
                print(refusal, file=sys.stderr)
                return 1
    print(f"\nall arms finished in {time.monotonic() - started:.1f}s")

    contrasts = []
    runtimes: dict[str, dict | None] = {}
    for base, withheld in pairs:
        correctness = {}
        for arm in (base, withheld):
            arm_dir = arm_directory(output_dir, arm)
            # Both halves of the check the pairing rests on: the folds belong to
            # this manifest, and the arm ran under one stack.
            require_uniform_runtime(arm_dir, fold_manifest)
            # Each arm's own, from its own folds: this experiment may span two
            # machines, and one stack taken from whoever wrote the report would
            # describe half the run while claiming to describe all of it.
            runtimes[arm] = first_runtime(arm_dir, fold_manifest)
            predictions, _ = load_arm_predictions(arm_dir, fold_manifest)
            correctness[arm] = pooled_group_correctness(predictions)

        contrasts.append(
            sensitivity_contrast(
                f"{base}_sensitivity",
                correctness[base],
                correctness[withheld],
                alpha=evaluation["alpha"],
                power=evaluation["power"],
            )
        )

    directory = output_dir / SENSITIVITY_DIRNAME
    report = write_sensitivity_report(
        directory,
        version=version,
        manifest_digest=fold_manifest["manifest_digest"],
        contrasts=contrasts,
        seeds=fold_manifest["seeds"],
        runtimes=runtimes,
    )

    for entry in report["contrasts"]:
        reading = entry["reading"]
        mde = entry["minimum_detectable_effect"]
        print(
            f"\n{entry['name']}: difference {entry['observed_difference']:+.3f} "
            f"over {entry['pairs']} group(s), p = {entry['p_value']:.4f}, "
            f"minimum detectable effect "
            f"{'none' if mde is None else format(mde, '.3f')}"
        )
        print(f"  cell: {reading['cell']}")
        print(f"  {reading['reading']}")

    verdict = report["verdict"]
    print(f"\nSPEC 0040 D6: {verdict['d6']}")
    if verdict["reopened_by"]:
        print(f"  re-opened by: {', '.join(verdict['reopened_by'])}")
    print(f"\n{report['licence']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
