"""Run the descriptor ablation the E0 gate reports (SPEC 0065).

Four runs over **one partition**: the descriptor arm with each of its component
groups removed in turn, each paired against the full arm SPEC 0044 compares.

It decides nothing. The report says so in its own words, and no ablation arm is
registered in `evaluation.contrasts`, so the gate's own contrast machinery cannot
compute one.

Run from the `ml/` directory:

    python scripts/run_descriptor_ablation.py
    python scripts/run_descriptor_ablation.py --groups lbp glcm

Exit codes: 0 the ablation ran and its report was written — **whichever way it
read** — and 1 it could not be run at all, which includes every arm refusing.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.ablation import (  # noqa: E402
    ABLATION_ARMS,
    ABLATION_DIRNAME,
    ABLATION_REPORT_FILENAME,
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
from src.sensitivity import carry_forward_contrasts  # noqa: E402


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
        help="recompute every fold of every ablation arm, discarding what is on disk",
    )
    return parser.parse_args(argv)


def _previous_report(directory: Path) -> dict | None:
    """The report already at this path, if one is there and parses.

    Unreadable is treated as absent rather than fatal: a half-written file from
    a killed run should not stop the run that replaces it.
    """
    path = Path(directory) / ABLATION_REPORT_FILENAME
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    configured = cfg["data"]["dataset_version"]
    version = args.version or configured

    # Refused rather than written back. `run_arm` does its own `load_config` and
    # its own `load_folds_for_config`, reading `dataset_version` from the file,
    # so a `--version` this script merely holds reaches the output path and
    # nothing else: the arms would load the configured version's folds and file
    # them under the requested version's name. The refusal names the flag, where
    # the one that eventually came out of the loader named a manifest digest.
    if version != configured:
        print(
            f"--version {version!r} disagrees with the configured dataset_version "
            f"{configured!r}, and the arms read theirs from the configuration "
            f"rather than from this flag. Change `data.dataset_version` in "
            f"config.yaml, or pass --config for a configuration that carries "
            f"{version!r}",
            file=sys.stderr,
        )
        return 1

    evaluation = cfg["evaluation"]

    try:
        fold_manifest = load_folds_for_config(cfg, cfg["data"]["splits_dir"])
    except (ValueError, FileNotFoundError) as error:
        print(f"cannot ablate over {version}: {error}", file=sys.stderr)
        return 1

    output_dir = Path(cfg["export"]["output_dir"]) / version
    ablation_arms = [ablation_arm_name(group) for group in args.groups]

    absent_reasons: dict[str, str] = {
        arm: "this run did not ask for it; pass --groups to include it"
        for arm in ABLATION_ARMS
        if arm not in ablation_arms
    }

    started = time.monotonic()
    for arm in [BASE_ARM, *ablation_arms]:
        print(f"\n=== {arm} over {version} ===")
        try:
            # `--force` never reaches the base arm. It is one of SPEC 0044's four
            # pre-registered gate arms, and recomputing it here would discard
            # finished folds and the `metrics.json` the gate's own contrast was
            # computed from — which SPEC 0065's Scope excludes by name.
            run_arm(version, arm, args.config, force=args.force and arm != BASE_ARM)
        except Exception as refusal:  # noqa: BLE001
            # Every exception and not `ValueError` alone: SPEC 0065's rule is
            # that a variant which did not run is recorded rather than raised,
            # and a `FileNotFoundError` from a deleted image or a `MemoryError`
            # from the refit would otherwise abort a four-hour diagnostic after
            # three of them had finished. The base arm is still fatal — without
            # it there is no pair to read.
            print(refusal, file=sys.stderr)
            if arm == BASE_ARM:
                return 1
            absent_reasons[arm] = f"the run refused: {refusal}"
            print(f"{arm} did not run; it will be recorded as not executed")
    print(f"\nall arms finished in {time.monotonic() - started:.1f}s")

    correctness = {}
    runtimes: dict[str, dict | None] = {}
    costs: dict[str, dict] = {}
    for arm in [BASE_ARM, *ablation_arms]:
        if arm in absent_reasons:
            continue
        arm_dir = arm_directory(output_dir, arm)
        try:
            # Both halves of the check the pairing rests on: the folds belong to
            # this manifest, and the arm ran under one stack.
            require_uniform_runtime(arm_dir, fold_manifest)
            predictions, fold_costs = load_arm_predictions(arm_dir, fold_manifest)
        except (ValueError, FileNotFoundError) as refusal:
            if arm == BASE_ARM:
                print(refusal, file=sys.stderr)
                return 1
            print(f"{arm}: {refusal}", file=sys.stderr)
            absent_reasons[arm] = f"its folds were refused: {refusal}"
            continue
        runtimes[arm] = first_runtime(arm_dir, fold_manifest)
        correctness[arm] = pooled_group_correctness(predictions)
        costs[arm] = {
            "trainings": sum(cost["trainings"] for cost in fold_costs.values()),
            "wall_clock_seconds_total": sum(
                sum(cost["wall_clock_seconds"]) for cost in fold_costs.values()
            ),
            "folds": len(fold_costs),
        }

    try:
        computed = ablation_contrasts(
            correctness,
            alpha=evaluation["alpha"],
            power=evaluation["power"],
            absent_reasons=absent_reasons,
        )
    except ValueError as refusal:
        print(refusal, file=sys.stderr)
        return 1

    directory = output_dir / ABLATION_DIRNAME

    # A partial run must not erase what a previous one measured. `--groups lbp`
    # here and `--groups glcm` tomorrow is the workflow the flag exists for, and
    # it only works if the second run keeps the first's contrasts — after
    # checking the two were computed over one partition.
    previous = _previous_report(directory)
    try:
        carried = carry_forward_contrasts(
            previous,
            computed_now=[entry["name"] for entry in computed["contrasts"]],
            version=version,
            manifest_digest=fold_manifest["manifest_digest"],
            seeds=fold_manifest["seeds"],
        )
    except ValueError as refusal:
        print(refusal, file=sys.stderr)
        return 1
    if carried:
        print(
            f"carrying forward {len(carried)} contrast(s) from the report "
            f"already here: {', '.join(entry['name'] for entry in carried)}"
        )
        for arm, runtime in (previous.get("runtimes") or {}).items():
            runtimes.setdefault(arm, runtime)
        for arm, cost in (previous.get("costs") or {}).items():
            costs.setdefault(arm, cost)

    carried_names = {entry["name"] for entry in carried}
    report = write_ablation_report(
        directory,
        version=version,
        manifest_digest=fold_manifest["manifest_digest"],
        contrasts=[*carried, *computed["contrasts"]],
        not_executed=[
            entry
            for entry in computed["not_executed"]
            if f"without_{entry['group']}" not in carried_names
        ],
        seeds=fold_manifest["seeds"],
        runtimes=runtimes,
        costs=costs,
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
        print(f"\n{entry['arm']}: not executed — {entry['note']}")

    carrying = report["carries_signal"]
    print(
        f"\ngroups whose removal cost the arm at least the minimum detectable "
        f"effect: {', '.join(carrying) if carrying else 'none'}"
    )
    print(f"\n{report['licence']}")
    print(f"\nwritten to {directory}")

    # Nothing measured is not a null result. Every arm refusing leaves a report
    # whose honest reading is "this did not run", and an exit code of 0 beside
    # the printed "none" above would read as "it ran and found nothing".
    if not report["contrasts"]:
        print(
            "\nno contrast was computed: every ablation arm is recorded as not "
            "executed, so this diagnostic measured nothing rather than finding "
            "nothing",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
