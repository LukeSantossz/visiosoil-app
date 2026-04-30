"""Training CLI: trains the soil texture classifier and saves checkpoints."""

import argparse
import json
import sys
from pathlib import Path

import tensorflow as tf

from .config import load_config, resolve_paths
from .dataset import scan_dataset, create_splits, load_splits, build_dataset
from .model import build_model


def train(version: str, config_path: str | None = None) -> None:
    """Run the full training pipeline.

    Steps:
    1. Load and validate config.
    2. Scan dataset and create/load splits.
    3. Build tf.data pipelines (train with augmentation, val without).
    4. Build model.
    5. Train with callbacks (EarlyStopping, ReduceLROnPlateau).
    6. Save Keras checkpoint (.h5) and config snapshot.

    Args:
        version: Model version string (e.g., "v1").
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

    # Build model
    model = build_model(cfg)
    model.summary()

    # Callbacks
    training_cfg = cfg["training"]
    callbacks = [
        tf.keras.callbacks.EarlyStopping(
            monitor="val_loss",
            patience=training_cfg.get("early_stopping_patience", 10),
            restore_best_weights=True,
            verbose=1,
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_loss",
            patience=training_cfg.get("reduce_lr_patience", 5),
            factor=training_cfg.get("reduce_lr_factor", 0.5),
            min_lr=1e-7,
            verbose=1,
        ),
    ]

    # Train
    history = model.fit(
        train_ds,
        validation_data=val_ds,
        epochs=training_cfg["epochs"],
        callbacks=callbacks,
    )

    # Save checkpoint
    h5_path = output_dir / "model.h5"
    model.save(h5_path)
    print(f"Model saved to {h5_path}")

    # Save training history
    history_data = {k: [float(v) for v in vals] for k, vals in history.history.items()}
    with open(output_dir / "history.json", "w") as f:
        json.dump(history_data, f, indent=2)

    print(f"Training complete. Artifacts in {output_dir}")


def main():
    parser = argparse.ArgumentParser(description="Train soil texture classifier")
    parser.add_argument("--version", type=str, default="v1", help="Model version (e.g., v1)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    train(args.version, args.config)


if __name__ == "__main__":
    main()
