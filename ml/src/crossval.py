"""Orchestrator for one arm of the k-fold protocol (SPEC 0042, ADR 0020).

Runs every outer fold of every repeat, pools the predictions, and writes the
arm's ``metrics.json``. The training stack is imported inside :func:`run_arm`
rather than at module import, so the artifact layout, the loader and the pooling
can be read and tested on a machine with no TensorFlow — which is where the
protocol's own tests run.

The on-disk layout is::

    models/<version>/<arm>/
        metrics.json
        repeat-<r>/fold-<i>/
            model.keras
            config.json
            runtime.json
            fine_tune.json
            selection_audit.json
            predictions.json
            cost.json

Every artifact of a fold lives under that fold, including the audit of what
selection read, so a result and the evidence that it was produced honestly
cannot be separated by moving a file.
"""

from __future__ import annotations

import argparse
import json
import time
import warnings
from enum import Enum
from pathlib import Path
from typing import Mapping, Sequence

from .config import load_config, resolve_paths
from .dataset import (
    FOLD_MANIFEST_FILENAME,
    create_folds_for_config,
    load_folds_for_config,
)
from .evaluate import METRICS_FILENAME, arm_metrics

CONFIG_FILENAME = "config.json"
PREDICTIONS_FILENAME = "predictions.json"
COST_FILENAME = "cost.json"
SELECTION_AUDIT_FILENAME = "selection_audit.json"
RUNTIME_FILENAME = "runtime.json"
FINE_TUNE_FILENAME = "fine_tune.json"

#: Default arm names. The real arm is named for what it is rather than for the
#: run, so two experiments comparing the same thing land in the same directory
#: and can be contrasted; the control is named separately so a control run
#: cannot silently overwrite the arm it is the control for.
DEFAULT_ARM = "cnn"
SHUFFLED_CONTROL_ARM = "shuffled_control"

#: The classical-descriptor arm and the frozen-encoder arm SPEC 0044 compares
#: against the incumbent, added by SPEC 0054.
DESCRIPTOR_ARM = "descriptors"
ENCODER_PROBE_ARM = "encoder_probe"


def _cnn_fold_trainer():
    from .train import train_fold

    return train_fold


def _descriptor_fold_trainer():
    from .arms.descriptors import descriptor_fold

    return descriptor_fold


def _encoder_probe_fold_trainer():
    from .arms.encoder import encoder_probe_fold

    return encoder_probe_fold


#: Arm name to the fold trainer that implements it. Behind thunks because each
#: import pulls in a different stack — the incumbent needs TensorFlow, the
#: descriptor arm does not — and naming one arm should not pay for the others.
#:
#: The control resolves to the incumbent's trainer on purpose. SPEC 0044
#: registers three primary contrasts against **one** control, not one control
#: per arm: the control reports what the class priors and the capture artefacts
#: alone permit, and the most capable arm is the strongest floor to hold every
#: other arm against.
ARM_TRAINERS = {
    DEFAULT_ARM: _cnn_fold_trainer,
    SHUFFLED_CONTROL_ARM: _cnn_fold_trainer,
    DESCRIPTOR_ARM: _descriptor_fold_trainer,
    ENCODER_PROBE_ARM: _encoder_probe_fold_trainer,
}


def fold_trainer_for(arm: str):
    """The fold trainer one arm name runs, or a refusal naming the arms.

    Refused rather than defaulted. The arm name is what a result is filed under
    and contrasted by, so a misspelling that fell back to the incumbent would
    produce a directory whose name says one method and whose numbers came from
    another — and nothing downstream could tell.
    """
    try:
        return ARM_TRAINERS[arm]()
    except KeyError:
        raise ValueError(
            f"no arm named {arm!r} is implemented; the arms are "
            f"{', '.join(sorted(ARM_TRAINERS))}"
        ) from None


def require_control_matches_arm(arm: str, shuffled_control: bool) -> None:
    """Refuse an arm name and a control flag that disagree.

    The two travel independently into both entry points, and either mismatch
    writes a result the artifacts cannot correct. Unpermuted labels under
    `shuffled_control` is a control that is not one, and every primary contrast
    is read against it. Permuted labels under a real arm's name is that arm
    recorded as having scored what chance scores.

    SPEC 0044 warns about the first in prose — "`--shuffled-control` and not
    `--arm shuffled_control`" — and prose is not a guard.
    """
    if (arm == SHUFFLED_CONTROL_ARM) != bool(shuffled_control):
        raise ValueError(
            f"arm {arm!r} and shuffled_control={bool(shuffled_control)} "
            f"disagree: only {SHUFFLED_CONTROL_ARM!r} permutes its labels, and "
            f"it always does. Run the control with --shuffled-control and let "
            f"the arm name follow from it"
        )


def arm_directory(output_dir: Path | str, arm: str) -> Path:
    """Where one arm's folds and metrics live."""
    return Path(output_dir) / arm


def fold_directory(arm_dir: Path | str, repeat: int, fold: int) -> Path:
    """Where one outer fold's artifacts live."""
    return Path(arm_dir) / f"repeat-{repeat}" / f"fold-{fold}"


def write_fold_predictions(
    arm_dir: Path | str,
    *,
    repeat: int,
    fold: int,
    arm: str,
    classes: Sequence[str],
    records: Sequence[Mapping],
    shuffled_control: bool,
    manifest_digest: str,
    forced: bool = False,
) -> Path:
    """Write one fold's test-side predictions.

    The full distribution is stored, not the argmax, because the group-level
    prediction is the argmax of the *mean* of a group's distributions and cannot
    be recovered from per-photograph labels.

    Args:
        manifest_digest: The dataset manifest this fold was computed from,
            required rather than defaulted (SPEC 0056). Without it two runs over
            one ``dataset_version`` whose manifest changed underneath — which
            `measure_scale.py` does routinely — are indistinguishable, and
            :func:`fold_reuse_state` would reuse a fold computed from other data.
        forced: Whether ``--force`` recomputed this fold over artifacts that were
            already there, so a re-run is visible in the result rather than only
            in a shell history.
    """
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / PREDICTIONS_FILENAME
    with open(path, "w") as handle:
        json.dump(
            {
                "repeat": repeat,
                "fold": fold,
                "arm": arm,
                "shuffled_control": bool(shuffled_control),
                "manifest_digest": manifest_digest,
                "forced": bool(forced),
                "classes": list(classes),
                "predictions": list(records),
            },
            handle,
            indent=2,
        )
    return path


class FoldReuse(str, Enum):
    """What one fold directory's artifacts prove about themselves.

    A `str` enum so a state can be printed and recorded without a conversion
    that could disagree with the name.
    """

    #: Nothing was ever written here.
    ABSENT = "absent"
    #: Written, but not finished — killed part-way, or unreadable. It was never
    #: a result, so recomputing it destroys nothing.
    INCOMPLETE = "incomplete"
    #: Finished, and provably produced by this run's configuration, manifest,
    #: arm and control flag. Reused untouched.
    REUSABLE = "reusable"
    #: Finished, and produced by something else — or by a run too old to say.
    #: Recomputing it would overwrite the artifacts a published result names.
    STALE = "stale"


def fold_reuse_state(
    arm_dir: Path | str,
    repeat: int,
    fold: int,
    *,
    cfg: Mapping,
    manifest_digest: str,
    arm: str,
    shuffled_control: bool,
) -> tuple[FoldReuse, str]:
    """Classify one fold directory, and say why (SPEC 0056).

    Completeness is `cost.json` plus a parseable `predictions.json`: the cost is
    written after the predictions, so its presence is the fold's commit point.

    Provenance is the fold's recorded configuration, manifest digest, arm name
    and control flag. The library versions are deliberately **not** compared
    here — the runtime a fold would record now lives behind TensorFlow, and this
    module defers that import so a refusal costs nothing. They are checked
    afterwards by :func:`require_uniform_runtime`, which catches drift in a run
    that resumed nothing at all.

    Returns:
        The state, and a sentence naming what did not match. The reason is
        returned rather than logged because the caller assembles one refusal
        message over every stale fold.
    """
    directory = fold_directory(arm_dir, repeat, fold)
    predictions = directory / PREDICTIONS_FILENAME
    if not predictions.exists():
        return FoldReuse.ABSENT, "nothing was written here"

    if not (directory / COST_FILENAME).exists():
        return (
            FoldReuse.INCOMPLETE,
            f"no {COST_FILENAME}, so the fold did not finish",
        )

    try:
        with open(predictions) as handle:
            header = json.load(handle)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return (
            FoldReuse.INCOMPLETE,
            f"{PREDICTIONS_FILENAME} does not parse, so the write was cut short",
        )

    recorded_digest = header.get("manifest_digest")
    if recorded_digest is None:
        return (
            FoldReuse.STALE,
            "it records no manifest digest, so it predates this record and "
            "cannot be shown to belong to this run",
        )
    if recorded_digest != manifest_digest:
        return (
            FoldReuse.STALE,
            f"it was computed from manifest {recorded_digest[:12]} and this run "
            f"reads {manifest_digest[:12]}",
        )

    if header.get("arm") != arm:
        return FoldReuse.STALE, f"it was written by arm {header.get('arm')!r}"

    if bool(header.get("shuffled_control")) != bool(shuffled_control):
        return (
            FoldReuse.STALE,
            f"it was written with shuffled_control="
            f"{bool(header.get('shuffled_control'))}",
        )

    config_path = directory / CONFIG_FILENAME
    if not config_path.exists():
        return FoldReuse.STALE, f"it has no {CONFIG_FILENAME}"
    try:
        with open(config_path) as handle:
            recorded_config = json.load(handle)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return FoldReuse.STALE, f"its {CONFIG_FILENAME} does not parse"
    if recorded_config != json.loads(json.dumps(cfg)):
        return (
            FoldReuse.STALE,
            "it ran under a different configuration",
        )

    return FoldReuse.REUSABLE, "it matches this run"


def begin_fold(arm_dir: Path | str, repeat: int, fold: int) -> None:
    """Clear a fold's completion marker before it is computed (SPEC 0056).

    Called immediately before every trainer call, and it is what stops a
    recomputation from leaving a fold that *looks* finished and is not. A
    trainer overwrites `config.json` and `runtime.json` before it writes any
    prediction; killed in between, the fold would keep the **old**
    `predictions.json` and the **old** `cost.json` beside the **new**
    `config.json`, and the next run would classify it reusable and pool
    predictions from one configuration under the record of another.

    Removing the marker first makes that state ``INCOMPLETE``, which is what it
    is. Nothing else is deleted: the predictions are what the next run would
    overwrite anyway, and removing them here would destroy a result before the
    replacement exists.
    """
    (fold_directory(arm_dir, repeat, fold) / COST_FILENAME).unlink(missing_ok=True)


def plan_arm_run(
    arm_dir: Path | str,
    fold_manifest: Mapping,
    *,
    cfg: Mapping,
    arm: str,
    shuffled_control: bool,
    force: bool = False,
    only: tuple[int, int] | None = None,
) -> dict:
    """Which folds this run reuses and which it computes (SPEC 0056).

    Every fold is classified before any is run, so a run that would overwrite a
    finished result is refused before it spends the first fold's time rather
    than after twenty-four of them.

    Args:
        only: A single ``(repeat, fold)`` to plan, for the per-fold entry point
            `src.train.train` — the one CI dispatches a job per fold to, and
            therefore the path a published result comes from. It asks this
            planner rather than carrying a second copy of the rule, because two
            implementations of one refusal are how the two come to disagree.

    Raises:
        ValueError: If any fold is finished but cannot be shown to belong to
            this run. The message names **every** such directory, not the first:
            an operator deciding whether to pass ``--force`` needs the whole cost
            of that decision in one message. ``force`` recomputes them instead.
    """
    reuse: list[tuple[int, int]] = []
    run: list[tuple[int, int]] = []
    stale: list[str] = []

    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            if only is not None and (repeat, fold) != only:
                continue
            if force:
                run.append((repeat, fold))
                continue
            state, reason = fold_reuse_state(
                arm_dir,
                repeat,
                fold,
                cfg=cfg,
                manifest_digest=fold_manifest["manifest_digest"],
                arm=arm,
                shuffled_control=shuffled_control,
            )
            if state is FoldReuse.REUSABLE:
                reuse.append((repeat, fold))
            elif state is FoldReuse.STALE:
                stale.append(f"{fold_directory(arm_dir, repeat, fold)} — {reason}")
            else:
                run.append((repeat, fold))

    if stale:
        raise ValueError(
            f"{len(stale)} fold(s) of {Path(arm_dir).name} are finished and did "
            f"not come from this run, so running would overwrite the artifacts a "
            f"published result names:\n  - "
            + "\n  - ".join(stale)
            + "\nPass --force to recompute them, which discards what is there."
        )

    return {"reuse": reuse, "run": run}


def require_uniform_runtime(arm_dir: Path | str, fold_manifest: Mapping) -> None:
    """Refuse an arm whose folds did not all run under the same libraries.

    Checked over the artifacts after the loop rather than inside the reuse
    predicate, for the reason SPEC 0056 records: the runtime a fold would write
    now is produced behind TensorFlow, and this module refuses before paying for
    that import. Reading it here costs nothing and catches more — a run that
    resumed nothing can still have been assembled from two library versions,
    which `StratifiedGroupKFold` alone is enough to make matter.

    Raises:
        ValueError: If two folds disagree, naming the folds that differ; or if
            any fold records no runtime at all, because absent is not the same
            as matching.
    """
    baseline: dict | None = None
    baseline_at: str | None = None
    unrecorded: list[str] = []
    differing: list[str] = []

    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            directory = fold_directory(arm_dir, repeat, fold)
            runtime = load_runtime(directory)
            if runtime is None:
                unrecorded.append(str(directory))
                continue
            if baseline is None:
                baseline, baseline_at = runtime, str(directory)
            elif runtime != baseline:
                differing.append(str(directory))

    if unrecorded:
        raise ValueError(
            f"{len(unrecorded)} fold(s) of {Path(arm_dir).name} have no recorded "
            f"runtime, so it cannot be shown that this arm ran under one stack:"
            f"\n  - " + "\n  - ".join(unrecorded)
        )
    if differing:
        raise ValueError(
            f"{len(differing)} fold(s) of {Path(arm_dir).name} ran under "
            f"different libraries from {baseline_at}, so pooling them would "
            f"report one arm over two stacks:\n  - " + "\n  - ".join(differing)
        )


def write_fold_cost(
    arm_dir: Path | str, repeat: int, fold: int, trainings: int, seconds: Sequence[float]
) -> Path:
    """Record what one outer fold cost, so k and R are auditable against it."""
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / COST_FILENAME
    with open(path, "w") as handle:
        json.dump(
            {"trainings": int(trainings), "wall_clock_seconds": list(seconds)},
            handle,
            indent=2,
        )
    return path


def assert_selection_is_nested(
    selection_group_ids: Sequence[str],
    test_group_ids: Sequence[str],
    repeat: int,
    fold: int,
) -> None:
    """Refuse before a leaked fold is trained, not after.

    Called before the inner loop runs as well as when the audit is written: a
    check that only fires at write time would have spent the whole selection
    budget training on the groups it is about to refuse, and an operator who
    interrupts the run would be left with no record of why.
    """
    leaked = sorted(set(selection_group_ids) & set(test_group_ids))
    if leaked:
        raise ValueError(
            f"selection for repeat {repeat} fold {fold} reads {len(leaked)} of "
            f"its own test groups: {', '.join(leaked)}. Nested selection is "
            "what makes the fold's number honest (ADR 0020)"
        )


def write_selection_audit(
    arm_dir: Path | str,
    repeat: int,
    fold: int,
    *,
    selection_group_ids: Sequence[str],
    test_group_ids: Sequence[str],
    inner_k: int,
    chosen: Mapping,
    refit_group_count: int,
) -> Path:
    """Record every group read while selecting a setting for this fold.

    Written beside the fold's own artifacts, and asserted against the fold's
    test groups by `tests/test_folds.py`. An audit that lived somewhere central
    could be regenerated from the code that produced the leak; this one is
    produced by the same call that built the inner folds.
    """
    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / SELECTION_AUDIT_FILENAME
    leaked = sorted(set(selection_group_ids) & set(test_group_ids))
    with open(path, "w") as handle:
        json.dump(
            {
                "repeat": repeat,
                "fold": fold,
                "inner_k": inner_k,
                "groups_read_during_selection": sorted(set(selection_group_ids)),
                "test_groups": sorted(set(test_group_ids)),
                "leaked_groups": leaked,
                "chosen": dict(chosen),
                "refit_groups": refit_group_count,
            },
            handle,
            indent=2,
        )
    assert_selection_is_nested(selection_group_ids, test_group_ids, repeat, fold)
    return path


def load_runtime(fold_dir: Path | str) -> dict | None:
    """The recorded runtime of the training run that produced ``fold_dir``.

    ``None`` when the directory predates this record, which is honest: absent is
    not the same as deterministic, and a comparison must be able to tell them
    apart rather than assuming the safe value.

    It lives here rather than in `src.train` so that reading a result never
    reaches the training stack: `src.train` imports TensorFlow at module scope,
    and reporting has to run where TensorFlow cannot be installed.
    """
    path = Path(fold_dir) / RUNTIME_FILENAME
    if not path.exists():
        return None
    with open(path) as handle:
        return json.load(handle)


def load_fine_tune(fold_dir: Path | str) -> dict | None:
    """What unfreezing did to the model that produced ``fold_dir``.

    ``None`` when the directory predates this record. Absent is not the same as
    a backbone whose BatchNormalization layers stayed in inference mode, and a
    reader comparing two folds has to be able to tell them apart rather than
    assuming the safe value — the same reasoning as `load_runtime`.

    It lives here, beside the rest of the artifact layout, so that reading a
    stored result never reaches the training stack.
    """
    path = Path(fold_dir) / FINE_TUNE_FILENAME
    if not path.exists():
        return None
    with open(path) as handle:
        return json.load(handle)


def read_fold_metadata(arm_dir: Path | str, repeat: int, fold: int) -> dict:
    """The header of one fold's predictions file, without its records.

    Lets a reporting run recover what the arm was — a control or a real arm —
    from the artifacts rather than from a flag the operator has to repeat, so a
    control's `metrics.json` cannot claim to describe a real arm.
    """
    path = fold_directory(arm_dir, repeat, fold) / PREDICTIONS_FILENAME
    with open(path) as handle:
        record = json.load(handle)
    return {key: value for key, value in record.items() if key != "predictions"}


def first_runtime(arm_dir: Path | str, fold_manifest: Mapping) -> dict | None:
    """The runtime the folds of one arm ran under, or ``None`` if none recorded.

    One source for both `src.crossval` and `src.evaluate`, read from the
    artifacts. `crossval` used to report whichever fold happened to run last
    while `evaluate` reported the first, so the same run described itself two
    ways depending on which tool was asked.

    A run whose folds disagree — resumed on another machine, or under another
    library stack — warns rather than picking one silently, because "these runs
    are comparable" is exactly what this record is consulted for.
    """
    recorded: dict | None = None
    disagreeing: list[str] = []
    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            found = load_runtime(fold_directory(arm_dir, repeat, fold))
            if found is None:
                continue
            if recorded is None:
                recorded = found
            elif found != recorded:
                disagreeing.append(f"repeat {repeat} fold {fold}")

    if disagreeing:
        warnings.warn(
            f"{len(disagreeing)} fold(s) of {Path(arm_dir).name} ran under a "
            f"different runtime from the first: {', '.join(disagreeing)}. The "
            "first is reported; folds of one arm that ran under different "
            "stacks are not comparable with each other",
            UserWarning,
            stacklevel=2,
        )
    return recorded


def load_arm_predictions(
    arm_dir: Path | str, fold_manifest: Mapping
) -> tuple[dict[tuple[int, int], list[dict]], dict[tuple[int, int], dict]]:
    """Read every fold's predictions and cost record for one arm.

    A missing fold is named rather than skipped: a pooled figure computed over
    twenty-four of twenty-five folds is not the figure the protocol defines, and
    silently producing it is worse than producing nothing.
    """
    arm_path = Path(arm_dir)
    predictions: dict[tuple[int, int], list[dict]] = {}
    costs: dict[tuple[int, int], dict] = {}

    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            directory = fold_directory(arm_path, repeat, fold)
            path = directory / PREDICTIONS_FILENAME
            if not path.exists():
                raise FileNotFoundError(
                    f"repeat {repeat} fold {fold} of {arm_path.name} has no "
                    f"{PREDICTIONS_FILENAME} at {path}. Run the arm with: "
                    f"python -m src.crossval --arm {arm_path.name}"
                )
            with open(path) as handle:
                predictions[(repeat, fold)] = json.load(handle)["predictions"]

            cost_path = directory / COST_FILENAME
            if cost_path.exists():
                with open(cost_path) as handle:
                    costs[(repeat, fold)] = json.load(handle)

    return predictions, costs


def run_arm(
    version: str,
    arm: str = DEFAULT_ARM,
    config_path: str | None = None,
    shuffled_control: bool = False,
    force: bool = False,
) -> dict:
    """Train, predict and pool every fold of every repeat for one arm.

    The per-fold training recipe is unchanged (SPEC 0032): what changes here is
    which data a training sees and how the results are pooled.

    Args:
        force: Recompute every fold, discarding artifacts that are already
            there. Off by default: a finished fold this run cannot account for
            refuses the run instead of being overwritten (SPEC 0056).
    """
    cfg = resolve_paths(load_config(config_path))
    splits_dir = cfg["data"]["splits_dir"]
    if not (Path(splits_dir) / FOLD_MANIFEST_FILENAME).exists():
        print(f"No fold manifest at {splits_dir}; generating it.")
        fold_manifest = create_folds_for_config(cfg, splits_dir)
    else:
        fold_manifest = load_folds_for_config(cfg, splits_dir)

    # Imported after the configuration and the folds have been checked, and not
    # at module scope: everything above this line is readable and testable
    # without the training stack, and a run that is going to be refused should
    # be refused before it spends half a minute importing TensorFlow.
    from .dataset import verify_images

    # Resolved before the first fold, so an arm nothing implements is refused in
    # a second rather than after the images have been verified.
    require_control_matches_arm(arm, shuffled_control)
    train_fold = fold_trainer_for(arm)

    output_dir = Path(cfg["export"]["output_dir"]) / version
    arm_dir = arm_directory(output_dir, arm)
    arm_dir.mkdir(parents=True, exist_ok=True)

    # Once for the run, not once per fold: every fold reads the same images, and
    # an unreadable file has to stop the run before the first training rather
    # than twenty-four folds later. `train_fold` verifies when called directly.
    verify_images(_images_by_class(fold_manifest))

    # Every fold is classified before any is run, so a run that would overwrite
    # a finished result is refused before it spends the first fold's time rather
    # than after twenty-four of them.
    plan = plan_arm_run(
        arm_dir,
        fold_manifest,
        cfg=cfg,
        arm=arm,
        shuffled_control=shuffled_control,
        force=force,
    )
    if plan["reuse"]:
        print(
            f"{len(plan['reuse'])} fold(s) already computed under this "
            f"configuration and manifest; reusing them untouched."
        )
    if not plan["run"]:
        print("every fold is already computed; nothing to train.")

    for repeat, fold in plan["run"]:
        started = time.monotonic()
        print(
            f"\n=== {arm}: repeat {repeat + 1}/{fold_manifest['repeats']}, "
            f"fold {fold + 1}/{fold_manifest['k']} ==="
        )
        begin_fold(arm_dir, repeat, fold)
        train_fold(
            cfg,
            fold_manifest,
            arm_dir=arm_dir,
            arm=arm,
            repeat=repeat,
            fold=fold,
            shuffled_control=shuffled_control,
            verify=False,
            forced=force,
        )
        print(f"fold finished in {time.monotonic() - started:.1f}s")

    # After the loop and before anything is pooled: an arm assembled from two
    # library versions is one arm in name only, and resuming is not what makes
    # that possible — a single uninterrupted run across an upgrade would do it.
    require_uniform_runtime(arm_dir, fold_manifest)

    predictions, costs = load_arm_predictions(arm_dir, fold_manifest)
    metrics = arm_metrics(
        fold_manifest,
        arm=arm,
        version=version,
        predictions=predictions,
        costs=costs,
        shuffled_control=shuffled_control,
        # Read back from the folds rather than kept from the last iteration:
        # `evaluate` reports what the artifacts say, and two tools describing
        # one run differently is worse than either description alone.
        runtime=first_runtime(arm_dir, fold_manifest),
    )
    with open(arm_dir / METRICS_FILENAME, "w") as handle:
        json.dump(metrics, handle, indent=2)
    print(f"\nmetrics saved to {arm_dir / METRICS_FILENAME}")
    return metrics


def _images_by_class(fold_manifest: Mapping) -> dict[str, list[str]]:
    """Every image the folds reference, grouped by class for verification."""
    grouped: dict[str, list[str]] = {}
    for record in fold_manifest["groups"].values():
        grouped.setdefault(record["class"], []).extend(record["images"])
    return grouped


def default_arm_name(arm: str | None, shuffled_control: bool) -> str:
    """The arm a run writes to when none was named.

    A control run defaults to its own directory, so running the control without
    naming an arm cannot overwrite the arm it is the control for.
    """
    if arm is not None:
        return arm
    return SHUFFLED_CONTROL_ARM if shuffled_control else DEFAULT_ARM


def main():
    parser = argparse.ArgumentParser(
        description="Run one arm across every repeat and outer fold"
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument(
        "--arm",
        type=str,
        default=None,
        help=f"Experimental arm (default: {DEFAULT_ARM}, "
        f"or {SHUFFLED_CONTROL_ARM} with --shuffled-control)",
    )
    parser.add_argument(
        "--shuffled-control",
        action="store_true",
        help="Permute texture_class across groups within each fold's training side",
    )
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    parser.add_argument(
        "--force",
        action="store_true",
        help="Recompute every fold, discarding artifacts already on disk",
    )
    args = parser.parse_args()

    run_arm(
        args.version,
        default_arm_name(args.arm, args.shuffled_control),
        args.config,
        shuffled_control=args.shuffled_control,
        force=args.force,
    )


if __name__ == "__main__":
    main()
