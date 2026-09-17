"""Run the descriptor ablation the E0 gate reports (SPEC 0065).

Four runs over **one partition**: the descriptor arm with each of its component
groups removed in turn, each paired against the full arm SPEC 0044 compares.

It decides nothing. The report says so in its own words, and no ablation arm is
registered in `evaluation.contrasts`, so the gate's own contrast machinery cannot
compute one.

Run from the `ml/` directory:

    python scripts/run_descriptor_ablation.py
    python scripts/run_descriptor_ablation.py --version v1 --groups lbp glcm

Exit codes: 0 the ablation ran and its report was written — **whichever way it
read** — and 1 it could not be run at all.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.ablation import (  # noqa: E402
    ABLATION_ARMS,
    ABLATION_DIRNAME,
    BASE_ARM,
    ablation_arm_name,
    ablation_contrasts,
    write_ablation_report,
)
from src.config import load_config, resolve_paths  # noqa: E402
from src.crossval import (  # noqa: E402
    arm_directory,
    first_runtime,
    load_arm_predictions,
    require_uniform_runtime,
    run_arm,
)
from src.dataset import load_folds_for_config  # noqa: E402
from src.descriptors import GROUPS  # noqa: E402
from src.evaluate import pooled_group_correctness  # noqa: E402


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="dataset version; defaults to the config")
    parser.add_argument("--config", help="path to config.yaml")
    parser.add_argument(
        "--groups",
        nargs="+",
        choices=sorted(GROUPS),
        default=sorted(GROUPS),
        help="which component groups to remove (default: every one, about four hours)",
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
    # Written back, not merely held: `load_folds_for_config` reads the version
    # from the configuration, so a `--version` that only reached the output path
    # would load one version's folds and file the result under another's name.
    cfg["data"]["dataset_version"] = version
    evaluation = cfg["evaluation"]

    try:
        fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    except (ValueError, FileNotFoundError) as error:
        print(f"cannot ablate over {version}: {error}", file=sys.stderr)
        return 1

    output_dir = Path(cfg["export"]["output_dir"]) / version
    arms = [BASE_ARM, *(ablation_arm_name(group) for group in args.groups)]

    started = time.monotonic()
    for arm in arms:
        print(f"\n=== {arm} over {version} ===")
        try:
            run_arm(version, arm, args.config, force=args.force)
        except ValueError as refusal:
            # The full arm is the pair every contrast is read against, so its
            # refusal ends the run. An ablation arm's refusal is recorded as not
            # executed instead, which is SPEC 0063's rule and this spec's.
            print(refusal, file=sys.stderr)
            if arm == BASE_ARM:
                return 1
            print(f"{arm} did not run; it will be recorded as not executed")
    print(f"\nall arms finished in {time.monotonic() - started:.1f}s")

    correctness = {}
    runtimes: dict[str, dict | None] = {}
    for arm in arms:
        arm_dir = arm_directory(output_dir, arm)
        try:
            # Both halves of the check the pairing rests on: the folds belong to
            # this manifest, and the arm ran under one stack.
            require_uniform_runtime(arm_dir, fold_manifest)
            predictions, _ = load_arm_predictions(arm_dir, fold_manifest)
        except (ValueError, FileNotFoundError) as refusal:
            if arm == BASE_ARM:
                print(refusal, file=sys.stderr)
                return 1
            print(f"{arm}: {refusal}", file=sys.stderr)
            continue
        runtimes[arm] = first_runtime(arm_dir, fold_manifest)
        correctness[arm] = pooled_group_correctness(predictions)

    try:
        computed = ablation_contrasts(
            correctness,
            alpha=evaluation["alpha"],
            power=evaluation["power"],
        )
    except ValueError as refusal:
        print(refusal, file=sys.stderr)
        return 1

    report = write_ablation_report(
        output_dir / ABLATION_DIRNAME,
        version=version,
        manifest_digest=fold_manifest["manifest_digest"],
        contrasts=computed["contrasts"],
        not_executed=computed["not_executed"],
        seeds=fold_manifest["seeds"],
        runtimes=runtimes,
    )

    for entry in report["contrasts"]:
        reading = entry["reading"]
        mde = entry["minimum_detectable_effect"]
        print(
            f"\n{entry['name']}: difference {entry['observed_difference']:+.3f} "
            f"over {entry['pairs']} group(s), p = {entry['p_value']:.4f}, "
            f"Holm {entry['p_value_holm']:.4f}, minimum detectable effect "
            f"{'none' if mde is None else format(mde, '.3f')}"
        )
        print(f"  cell: {reading['cell']}")
        print(f"  {reading['reading']}")

    for entry in report["not_executed"]:
        print(f"\n{entry['arm']}: not executed, so no contrast was computed for it")

    carrying = report["carries_signal"]
    print(
        f"\ngroups whose removal changed a scored result by at least the "
        f"minimum detectable effect: {', '.join(carrying) if carrying else 'none'}"
    )
    print(f"\n{report['licence']}")
    print(f"\nwritten to {output_dir / ABLATION_DIRNAME}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
