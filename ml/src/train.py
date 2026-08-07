"""Training CLI: trains the soil texture classifier with 2-phase transfer learning."""

import argparse
import json
import sys
from pathlib import Path

import tensorflow as tf

from .config import load_config, resolve_paths
from .dataset import (
    scan_dataset, create_splits, load_splits, build_dataset,
    compute_class_weights, validate_splits_against_config, verify_images,
)
from .model import build_model, unfreeze_model


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

    Returns the runtime record this run acted under, which `train` persists as
    `runtime.json` beside the artifact so a comparison can tell whether two runs
    are comparable.

    Two costs are real and unmeasured here, because measuring them needs a
    dataset that does not exist yet: the throughput loss is workload-dependent,
    and a kernel with no deterministic implementation raises rather than falling
    back. The opt-out is the escape hatch for both.
    """
    tf.keras.utils.set_random_seed(seed)
    if deterministic_ops:
        tf.config.experimental.enable_op_determinism()
    return runtime_mode(deterministic_ops)


RUNTIME_FILENAME = "runtime.json"


def runtime_mode(deterministic_ops: bool) -> dict:
    """What a later comparison needs in order to know if two runs are comparable.

    Two runs are only comparable when both were produced under operator
    determinism. Recording the flag and the device makes an invalid comparison
    detectable instead of silent; nothing compares runs yet, so the check that
    refuses one lands with whatever implements E0's comparison.

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
    }


def load_runtime(output_dir: Path) -> dict | None:
    """The recorded runtime of the training run that produced `output_dir`.

    `None` when the directory predates this record, which is honest: absent is
    not the same as deterministic, and a comparison must be able to tell them
    apart rather than assuming the safe value.
    """
    path = Path(output_dir) / RUNTIME_FILENAME
    if not path.exists():
        return None
    with open(path) as handle:
        return json.load(handle)


def train(version: str, config_path: str | None = None) -> None:
    """Run the full 2-phase training pipeline.

    Phase 1 — Head only (backbone frozen):
        Trains classification head with high LR for N epochs.
    Phase 2 — Fine-tuning (top backbone layers unfrozen):
        Unfreezes top layers and trains with low LR until EarlyStopping.

    Args:
        version: Model version string (e.g., "v2").
        config_path: Optional path to config.yaml.
    """
    cfg = load_config(config_path)
    cfg = resolve_paths(cfg)

    # Before any dataset or model is built, or nothing below is reproducible.
    # Indexed, not `.get`: `load_config` always sets this, so a missing key is a
    # broken invariant and should say so rather than quietly training in the
    # non-reproducible mode.
    runtime = seed_everything(
        cfg["data"]["seed"],
        deterministic_ops=cfg["training"]["deterministic_ops"],
    )

    output_dir = Path(cfg["export"]["output_dir"]) / version
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save config snapshot
    with open(output_dir / "config.json", "w") as f:
        json.dump(cfg, f, indent=2)

    # Persist the runtime this run actually used, next to the artifact it
    # produced. Written here rather than recomputed later because evaluation
    # frequently runs on another machine: a value derived at evaluation time
    # would describe that host and silently claim to describe this one.
    with open(output_dir / RUNTIME_FILENAME, "w") as f:
        json.dump(runtime, f, indent=2)

    # Dataset splits
    splits_dir = cfg["data"]["splits_dir"]
    splits_file = Path(splits_dir) / "splits.json"

    if splits_file.exists():
        print(f"Loading existing splits from {splits_file}")
        manifest = load_splits(splits_dir)
        validate_splits_against_config(manifest, cfg)
        splits = manifest["splits"]
    else:
        print("Scanning dataset and creating splits...")
        class_images = scan_dataset(cfg["data"]["raw_dir"], cfg["classes"])
        splits = create_splits(
            class_images,
            val_split=cfg["data"]["val_split"],
            test_split=cfg["data"]["test_split"],
            seed=cfg["data"]["seed"],
            splits_dir=splits_dir,
        )

    # Verify what will actually be read, on BOTH paths. Verifying only the
    # freshly scanned set left the far more common path unchecked: a manifest
    # written by an earlier run, whose files may since have been deleted,
    # truncated, or replaced. That is exactly when a dataset rots, and the
    # failure then surfaced partway through an epoch rather than before the
    # model was built.
    referenced: dict[str, list[str]] = {}
    for split in splits.values():
        for entry in split:
            referenced.setdefault(entry["class"], []).append(entry["path"])
    verify_images(referenced)

    print(f"Train: {len(splits['train'])}, Val: {len(splits['val'])}, Test: {len(splits['test'])}")

    # Build datasets
    train_ds = build_dataset(splits["train"], cfg, augment=True, shuffle=True)
    val_ds = build_dataset(splits["val"], cfg, augment=False, shuffle=False)

    # Compute class weights
    num_classes = len(cfg["classes"])
    class_weights_mode = cfg["training"].get("class_weights", "none")
    class_weights = None
    if class_weights_mode == "balanced":
        class_weights = compute_class_weights(splits["train"], num_classes)
        print(f"Class weights: {class_weights}")

    # Build model (backbone frozen)
    model = build_model(cfg)
    model.summary()

    training_cfg = cfg["training"]
    total_epochs = training_cfg["epochs"]
    unfreeze_at_epoch = cfg["model"].get("unfreeze_at_epoch", total_epochs)

    # Phase 1: Head-only training
    phase1_epochs = min(unfreeze_at_epoch, total_epochs)
    print(f"\n{'='*50}")
    print(f"Phase 1: Head-only training (epochs 1-{phase1_epochs})")
    print(f"{'='*50}")

    callbacks_phase1 = [
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            patience=training_cfg.get("reduce_lr_patience", 5),
            factor=training_cfg.get("reduce_lr_factor", 0.5),
            min_lr=1e-7,
            verbose=1,
        ),
    ]

    history1 = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=phase1_epochs,
        callbacks=callbacks_phase1,
        class_weight=class_weights,
    )

    # Phase 2: Fine-tuning (if epochs remain)
    if phase1_epochs < total_epochs:
        print(f"\n{'='*50}")
        print(f"Phase 2: Fine-tuning (epochs {phase1_epochs + 1}-{total_epochs})")
        print(f"{'='*50}")

        model = unfreeze_model(model, cfg)

        checkpoint_path = output_dir / "best_model.keras"
        callbacks_phase2 = [
            tf.keras.callbacks.EarlyStopping(
                monitor="val_accuracy",
                patience=training_cfg.get("early_stopping_patience", 10),
                restore_best_weights=True,
                verbose=1,
            ),
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor="val_loss",
                patience=training_cfg.get("reduce_lr_patience", 5),
                factor=training_cfg.get("reduce_lr_factor", 0.5),
                min_lr=1e-8,
                verbose=1,
            ),
            tf.keras.callbacks.ModelCheckpoint(
                filepath=str(checkpoint_path),
                monitor="val_accuracy",
                save_best_only=True,
                verbose=1,
            ),
        ]

        history2 = model.fit(
            train_ds,
            validation_data=val_ds,
            initial_epoch=phase1_epochs,
            epochs=total_epochs,
            callbacks=callbacks_phase2,
            class_weight=class_weights,
        )

        # Merge histories
        history_data = {}
        for key in history1.history:
            history_data[key] = [float(v) for v in history1.history[key]]
            if key in history2.history:
                history_data[key].extend([float(v) for v in history2.history[key]])
    else:
        history_data = {k: [float(v) for v in vals] for k, vals in history1.history.items()}

    # Save final model
    keras_path = output_dir / "model.keras"
    model.save(keras_path)
    print(f"Model saved to {keras_path}")

    # Save training history
    with open(output_dir / "history.json", "w") as f:
        json.dump(history_data, f, indent=2)

    print(f"Training complete. Artifacts in {output_dir}")


def main():
    parser = argparse.ArgumentParser(description="Train soil texture classifier")
    parser.add_argument("--version", type=str, default="v1", help="Model version (e.g., v2)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    train(args.version, args.config)


if __name__ == "__main__":
    main()
