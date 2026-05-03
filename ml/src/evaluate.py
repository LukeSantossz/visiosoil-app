"""Evaluation CLI: generates metrics, confusion matrix, and classification report."""

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
)

from .config import load_config, resolve_paths
from .dataset import load_splits, build_dataset


def evaluate(version: str, config_path: str | None = None) -> dict:
    """Evaluate a trained model on the test split.

    Args:
        version: Model version string (e.g., "v2").
        config_path: Optional path to config.yaml.

    Returns:
        Dict with accuracy, f1, per-class metrics.
    """
    cfg = load_config(config_path)
    cfg = resolve_paths(cfg)

    output_dir = Path(cfg["export"]["output_dir"]) / version

    # Try .keras first, then .h5 for backward compatibility
    keras_path = output_dir / "model.keras"
    h5_path = output_dir / "model.h5"

    if keras_path.exists():
        model_path = keras_path
    elif h5_path.exists():
        model_path = h5_path
    else:
        raise FileNotFoundError(
            f"Model checkpoint not found: tried {keras_path} and {h5_path}"
        )

    model = tf.keras.models.load_model(model_path)

    # Load splits and build test dataset
    manifest = load_splits(cfg["data"]["splits_dir"])
    splits = manifest["splits"]
    test_entries = splits["test"]
    test_ds = build_dataset(test_entries, cfg, augment=False, shuffle=False)

    # Predict
    y_pred_probs = model.predict(test_ds)
    y_pred = np.argmax(y_pred_probs, axis=1)
    y_true = np.array([e["label"] for e in test_entries])

    classes = cfg["classes"]

    # Metrics
    acc = float(accuracy_score(y_true, y_pred))
    f1_macro = float(f1_score(y_true, y_pred, average="macro"))
    f1_weighted = float(f1_score(y_true, y_pred, average="weighted"))

    report = classification_report(y_true, y_pred, target_names=classes, output_dict=True)
    cm = confusion_matrix(y_true, y_pred).tolist()

    metrics = {
        "version": version,
        "accuracy": acc,
        "f1_macro": f1_macro,
        "f1_weighted": f1_weighted,
        "per_class": {
            name: {
                "precision": report[name]["precision"],
                "recall": report[name]["recall"],
                "f1": report[name]["f1-score"],
                "support": report[name]["support"],
            }
            for name in classes
        },
        "confusion_matrix": cm,
        "test_size": len(test_entries),
    }

    # Save metrics
    with open(output_dir / "metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    # Save confusion matrix plot
    _save_confusion_matrix_plot(cm, classes, output_dir / "confusion_matrix.png")

    # Print summary
    print(f"\n{'='*50}")
    print(f"Evaluation Results — {version}")
    print(f"{'='*50}")
    print(f"Accuracy:    {acc:.4f}")
    print(f"F1 (macro):  {f1_macro:.4f}")
    print(f"F1 (weighted): {f1_weighted:.4f}")
    print(f"\nPer-class:")
    for name in classes:
        m = metrics["per_class"][name]
        print(f"  {name:20s}  P={m['precision']:.3f}  R={m['recall']:.3f}  F1={m['f1']:.3f}  N={m['support']}")
    print(f"\nMetrics saved to {output_dir / 'metrics.json'}")

    return metrics


def _save_confusion_matrix_plot(cm: list, classes: list[str], path: Path) -> None:
    """Save confusion matrix heatmap as PNG."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import seaborn as sns

        fig, ax = plt.subplots(figsize=(8, 6))
        sns.heatmap(
            np.array(cm),
            annot=True,
            fmt="d",
            cmap="Blues",
            xticklabels=classes,
            yticklabels=classes,
            ax=ax,
        )
        ax.set_xlabel("Predicted")
        ax.set_ylabel("True")
        ax.set_title("Confusion Matrix")
        plt.tight_layout()
        fig.savefig(path, dpi=150)
        plt.close(fig)
        print(f"Confusion matrix saved to {path}")
    except ImportError:
        print("matplotlib/seaborn not available, skipping confusion matrix plot")


def main():
    parser = argparse.ArgumentParser(description="Evaluate soil texture classifier")
    parser.add_argument("--version", type=str, default="v1", help="Model version (e.g., v2)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    evaluate(args.version, args.config)


if __name__ == "__main__":
    main()
