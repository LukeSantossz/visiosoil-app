"""Per-fold training for the k-fold protocol (SPEC 0042, ADR 0020).

One invocation trains one outer fold of one repeat: it selects on inner folds of
that fold's own training side, refits on the whole training side with the chosen
setting, and predicts the fold's test side. `src.crossval` runs the whole grid.

The two-phase transfer-learning recipe and the determinism record of SPEC 0032
are unchanged inside a fold. What changed is which data a training sees and how
the results are pooled — not how a model is fitted.
"""

import argparse
import json
import time
from pathlib import Path

import numpy as np
import tensorflow as tf

from .config import load_config, resolve_paths
from .dataset import (
    FOLD_MANIFEST_FILENAME,
    build_dataset,
    compute_class_weights,
    create_folds_for_config,
    derive_repeat_seed,
    fold_split,
    inner_folds,
    library_versions,
    load_folds_for_config,
    permute_labels_by_group,
    verify_images,
)
from .model import build_model, fine_tune_report, unfreeze_model
from .model_paths import CHECKPOINT_FILENAME

# Re-exported: the runtime record is part of the fold's artifact layout, which
# `src.crossval` owns, and reading one must not reach the training stack. Kept
# importable from here because this is the module that writes it.
from .crossval import (  # noqa: F401
    FINE_TUNE_FILENAME,
    RUNTIME_FILENAME,
    load_fine_tune,
    load_runtime,
)

#: Separates a control run's permutation seed from every fold and repeat seed,
#: so the permutation cannot coincide with the draw that produced the folds it
#: is permuting. Recorded in the fold's artifacts, so the control is
#: reproducible from the file rather than from this constant.
SHUFFLED_CONTROL_SEED_OFFSET = 500_000


def seed_everything(seed: int, deterministic_ops: bool = True) -> dict:
    """Seed Python, NumPy and TensorFlow, and pin operator determinism.

    Without seeding, weight initialization, dropout masks and augmentation draws
    are unseeded, so two runs of one config produce different metrics and no
    experiment can be compared against another. Experiment E0 in particular
    measures a difference against run-to-run variance, which has no meaning
    until that variance is controlled.

    Seeding alone is not enough on a GPU. `set_random_seed` seeds the
    generators; it does not make TensorFlow's kernels deterministic, and several
    reduce across threads in completion order, so float addition happens in a
    different order each run. On CPU this does not arise. Training here runs on
    whatever hardware is available, so relying on seeding alone would make
    reproducibility a property of where the run happened to land — and E0's
    denominator would silently inflate on GPU with nothing reporting it.

    `enable_op_determinism` is therefore on by default, reversing an earlier
    decision in this project to skip it for throughput on free Kaggle and Colab
    tiers. Set `training.deterministic_ops: false` to trade reproducibility for
    speed in an exploratory run.

    Returns the runtime record this run acted under, which `train_fold` persists
    as `runtime.json` beside the fold's artifacts so a comparison can tell
    whether two runs are comparable.

    Two costs are real and unmeasured here, because measuring them needs a
    dataset that does not exist yet: the throughput loss is workload-dependent,
    and a kernel with no deterministic implementation raises rather than falling
    back. The opt-out is the escape hatch for both.
    """
    tf.keras.utils.set_random_seed(seed)
    if deterministic_ops:
        tf.config.experimental.enable_op_determinism()
    return runtime_mode(deterministic_ops)


def runtime_mode(deterministic_ops: bool) -> dict:
    """What a later comparison needs in order to know if two runs are comparable.

    Two runs are only comparable when both were produced under operator
    determinism. Recording the flag and the device makes an invalid comparison
    detectable instead of silent.

    Takes the effective flag rather than the config, and is called from
    `seed_everything` at the moment the decision is acted on. Deriving it from a
    config later would describe whichever host did the deriving: `evaluate` runs
    on a different machine from training often enough that a field claiming to
    describe the training run would have quietly described the evaluation one.
    """
    gpus = tf.config.list_physical_devices("GPU")
    return {
        "deterministic_ops": bool(deterministic_ops),
        "device": "GPU" if gpus else "CPU",
        "gpu_count": len(gpus),
        # The stack the fold ran under, recorded for the same reason the fold
        # manifest records it: the partition a result was computed on is a
        # function of the scikit-learn version as well as of the seed, and two
        # runs under different versions are not comparable however identically
        # they were seeded.
        # `getattr` with a fallback rather than an attribute access: this runs
        # at the head of every training, and a provenance field is not worth
        # crashing a run over if a future Keras stops exposing it. "unknown" is
        # recorded rather than the key omitted, so absent cannot read as matching.
        "library_versions": {
            **library_versions(),
            "tensorflow": getattr(tf, "__version__", "unknown"),
            "keras": getattr(tf.keras, "__version__", "unknown"),
        },
    }


def control_seed(seed: int, repeat: int, fold: int) -> int:
    """The seed the shuffled control permutes this fold's labels with."""
    return derive_repeat_seed(seed, repeat) + SHUFFLED_CONTROL_SEED_OFFSET + fold


def train_fold(
    cfg: dict,
    fold_manifest: dict,
    *,
    arm_dir: Path | str,
    arm: str,
    repeat: int,
    fold: int,
    shuffled_control: bool = False,
    verify: bool = True,
) -> dict:
    """Select, refit and predict one outer fold, writing its artifacts.

    Args:
        cfg: The resolved configuration.
        fold_manifest: The fold manifest the run is scored against.
        arm_dir: ``models/<version>/<arm>``.
        arm: Name of the experimental arm.
        repeat: Repeat index.
        fold: Outer fold index.
        shuffled_control: Permute ``texture_class`` across groups within this
            fold's training side, leaving the test side untouched.
        verify: Decode every referenced image before building anything. The
            orchestrator verifies once for the whole run and passes ``False``.

    Returns:
        The runtime record this fold trained under.
    """
    from .crossval import (
        assert_selection_is_nested,
        fold_directory,
        write_fold_cost,
        write_fold_predictions,
        write_selection_audit,
    )

    # Before any dataset or model is built, or nothing below is reproducible.
    # Indexed, not `.get`: `load_config` always sets this, so a missing key is a
    # broken invariant and should say so rather than quietly training in the
    # non-reproducible mode.
    runtime = seed_everything(
        derive_repeat_seed(cfg["data"]["seed"], repeat),
        deterministic_ops=cfg["training"]["deterministic_ops"],
    )

    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / "config.json", "w") as handle:
        json.dump(cfg, handle, indent=2)
    # Persisted here rather than recomputed later because evaluation frequently
    # runs on another machine: a value derived at evaluation time would describe
    # that host and silently claim to describe this one.
    with open(directory / RUNTIME_FILENAME, "w") as handle:
        json.dump(runtime, handle, indent=2)

    split = fold_split(fold_manifest, repeat, fold)
    inner = inner_folds(
        fold_manifest, repeat, fold, cfg["evaluation"]["inner_k"]
    )

    permutation_seed = None
    if shuffled_control:
        permutation_seed = control_seed(cfg["data"]["seed"], repeat, fold)
        # The training side only. The test side is never passed to the
        # permutation, which is what makes "the test side is untouched" a
        # property of the call graph rather than of a comment.
        permuted = permute_labels_by_group(split["train"], permutation_seed)
        labels_by_group = {entry["group"]: entry["label"] for entry in permuted}
        classes_by_group = {entry["group"]: entry["class"] for entry in permuted}
        split["train"] = permuted
        inner = [
            {
                side: _relabel(entries, labels_by_group, classes_by_group)
                for side, entries in inner_split.items()
            }
            for inner_split in inner
        ]

    if verify:
        verify_images(_by_class(split["train"] + split["test"]))

    print(
        f"repeat {repeat} fold {fold}: "
        f"{len(split['train'])} training and {len(split['test'])} test "
        f"photograph(s) over "
        f"{len({e['group'] for e in split['train']})} training and "
        f"{len({e['group'] for e in split['test']})} test group(s)"
    )

    selection_group_ids = [
        entry["group"]
        for inner_split in inner
        for side in ("train", "val")
        for entry in inner_split[side]
    ]
    test_group_ids = [entry["group"] for entry in split["test"]]
    # Before the first inner training, not after the last: a leak found at write
    # time has already cost the whole selection budget.
    assert_selection_is_nested(selection_group_ids, test_group_ids, repeat, fold)

    seconds: list[float] = []
    chosen_epochs = []
    for index, inner_split in enumerate(inner):
        started = time.monotonic()
        print(f"  inner fold {index + 1}/{len(inner)} — selecting the epoch count")
        _, history = _fit_two_phase(
            cfg, inner_split["train"], inner_split["val"]
        )
        seconds.append(time.monotonic() - started)
        chosen_epochs.append(_best_epoch(history))

    selected = max(1, int(round(float(np.mean(chosen_epochs)))))
    write_selection_audit(
        arm_dir,
        repeat,
        fold,
        selection_group_ids=selection_group_ids,
        test_group_ids=test_group_ids,
        inner_k=cfg["evaluation"]["inner_k"],
        chosen={
            "epochs": selected,
            "epochs_per_inner_fold": chosen_epochs,
            "criterion": "epoch of best inner validation accuracy, averaged",
            "shuffled_control": bool(shuffled_control),
            "permutation_seed": permutation_seed,
        },
        refit_group_count=len({entry["group"] for entry in split["train"]}),
    )

    print(f"  refitting on the whole training side for {selected} epoch(s)")
    started = time.monotonic()
    model, _ = _fit_two_phase(cfg, split["train"], None, total_epochs=selected)
    seconds.append(time.monotonic() - started)

    # Written from the refit model, which is the one whose predictions are
    # scored. Recorded in the artifact rather than left implicit in the code so
    # that a later change to `unfreeze_model` is visible in every fold produced
    # after it, instead of only in a diff nobody reads beside a stored result.
    with open(directory / FINE_TUNE_FILENAME, "w") as handle:
        json.dump(fine_tune_report(model), handle, indent=2)

    model.save(directory / CHECKPOINT_FILENAME)
    write_fold_predictions(
        arm_dir,
        repeat=repeat,
        fold=fold,
        arm=arm,
        classes=cfg["classes"],
        records=_predict(model, split["test"], cfg),
        shuffled_control=shuffled_control,
    )
    write_fold_cost(arm_dir, repeat, fold, len(seconds), seconds)
    return runtime


def _relabel(entries, labels_by_group, classes_by_group):
    """Apply a group-level label map to entries built from the manifest."""
    return [
        {
            **entry,
            "label": labels_by_group[entry["group"]],
            "class": classes_by_group[entry["group"]],
        }
        for entry in entries
    ]


def _by_class(entries):
    """Group entry paths by class, the shape `verify_images` reads."""
    grouped: dict[str, list[str]] = {}
    for entry in entries:
        grouped.setdefault(entry["class"], []).append(entry["path"])
    return grouped


def _best_epoch(history: dict) -> int:
    """The epoch the inner validation accuracy peaked at, one-based.

    Falls back to the epoch count when no validation accuracy was recorded,
    which is the honest reading of "nothing to select on" — not epoch one.
    """
    accuracies = history.get("val_accuracy") or []
    if not accuracies:
        return max(1, len(history.get("loss", [1])))
    return int(np.argmax(accuracies)) + 1


def _fit_two_phase(cfg, train_entries, val_entries, total_epochs=None):
    """Train one model on ``train_entries``, the SPEC 0032 recipe unchanged.

    ``val_entries`` is ``None`` for the refit, which has nothing to select on by
    design: the setting was already chosen on the inner folds, and re-selecting
    here on any held-out slice of the training side would be a second selection
    nobody audited.
    """
    training_cfg = cfg["training"]
    total_epochs = total_epochs or training_cfg["epochs"]

    train_ds = build_dataset(train_entries, cfg, augment=True, shuffle=True)
    val_ds = (
        build_dataset(val_entries, cfg, augment=False, shuffle=False)
        if val_entries
        else None
    )

    class_weights = None
    if training_cfg.get("class_weights", "none") == "balanced":
        class_weights = compute_class_weights(train_entries, len(cfg["classes"]))

    model = build_model(cfg)
    monitored_loss = "val_loss" if val_ds is not None else "loss"

    phase1_epochs = min(
        cfg["model"].get("unfreeze_at_epoch", total_epochs), total_epochs
    )
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=phase1_epochs,
        callbacks=[
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor=monitored_loss,
                patience=training_cfg.get("reduce_lr_patience", 5),
                factor=training_cfg.get("reduce_lr_factor", 0.5),
                min_lr=1e-7,
                verbose=0,
            )
        ],
        class_weight=class_weights,
        verbose=2,
    ).history
    merged = {key: [float(v) for v in values] for key, values in history.items()}

    if phase1_epochs < total_epochs:
        model = unfreeze_model(model, cfg)
        callbacks = [
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor=monitored_loss,
                patience=training_cfg.get("reduce_lr_patience", 5),
                factor=training_cfg.get("reduce_lr_factor", 0.5),
                min_lr=1e-8,
                verbose=0,
            )
        ]
        if val_ds is not None:
            callbacks.append(
                tf.keras.callbacks.EarlyStopping(
                    monitor="val_accuracy",
                    patience=training_cfg.get("early_stopping_patience", 10),
                    restore_best_weights=True,
                    verbose=0,
                )
            )
        second = model.fit(
            train_ds,
            validation_data=val_ds,
            initial_epoch=phase1_epochs,
            epochs=total_epochs,
            callbacks=callbacks,
            class_weight=class_weights,
            verbose=2,
        ).history
        for key, values in second.items():
            merged.setdefault(key, []).extend(float(v) for v in values)

    return model, merged


def _predict(model, test_entries, cfg) -> list[dict]:
    """Predict the fold's test side, keeping the full distribution per photograph.

    The distribution and not the argmax: a group's prediction is the argmax of
    the mean of its photographs' distributions, and that cannot be recovered
    from per-photograph labels.
    """
    dataset = build_dataset(test_entries, cfg, augment=False, shuffle=False)
    probabilities = model.predict(dataset, verbose=0)
    return [
        {
            "path": entry["path"],
            "group": entry["group"],
            "label": int(entry["label"]),
            "probabilities": [float(value) for value in row],
        }
        for entry, row in zip(test_entries, probabilities)
    ]


def train(
    version: str,
    repeat: int,
    fold: int,
    arm: str,
    config_path: str | None = None,
    shuffled_control: bool = False,
) -> dict:
    """Train one outer fold from the command line."""
    from .crossval import arm_directory

    cfg = resolve_paths(load_config(config_path))
    splits_dir = cfg["data"]["splits_dir"]
    if (Path(splits_dir) / FOLD_MANIFEST_FILENAME).exists():
        fold_manifest = load_folds_for_config(cfg, splits_dir)
    else:
        print(f"No fold manifest at {splits_dir}; generating it.")
        fold_manifest = create_folds_for_config(cfg, splits_dir)

    arm_dir = arm_directory(Path(cfg["export"]["output_dir"]) / version, arm)
    return train_fold(
        cfg,
        fold_manifest,
        arm_dir=arm_dir,
        arm=arm,
        repeat=repeat,
        fold=fold,
        shuffled_control=shuffled_control,
    )


def main():
    from .crossval import default_arm_name

    parser = argparse.ArgumentParser(
        description="Train one outer fold of one repeat"
    )
    parser.add_argument("--version", type=str, default="v1", help="Dataset version")
    parser.add_argument("--repeat", type=int, required=True, help="Repeat index")
    parser.add_argument("--fold", type=int, required=True, help="Outer fold index")
    parser.add_argument("--arm", type=str, default=None, help="Experimental arm")
    parser.add_argument(
        "--shuffled-control",
        action="store_true",
        help="Permute texture_class across groups within this fold's training side",
    )
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    train(
        args.version,
        args.repeat,
        args.fold,
        default_arm_name(args.arm, args.shuffled_control),
        args.config,
        shuffled_control=args.shuffled_control,
    )


if __name__ == "__main__":
    main()
