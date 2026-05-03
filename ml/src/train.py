"""Training CLI: trains the soil texture classifier with 2-phase transfer learning."""

import argparse
import json
import sys
from pathlib import Path

import tensorflow as tf

from .config import load_config, resolve_paths
from .dataset import scan_dataset, create_splits, load_splits, build_dataset, compute_class_weights
from .model import build_model, unfreeze_model


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

    output_dir = Path(cfg["export"]["output_dir"]) / version
    output_dir.mkdir(parents=True, exist_ok=True)

    # Save config snapshot
    with open(output_dir / "config.json", "w") as f:
        json.dump(cfg, f, indent=2)

    # Dataset splits
    splits_dir = cfg["data"]["splits_dir"]
    splits_file = Path(splits_dir) / "splits.json"

    if splits_file.exists():
        print(f"Loading existing splits from {splits_file}")
        manifest = load_splits(splits_dir)
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
