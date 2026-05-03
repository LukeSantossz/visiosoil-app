"""Dataset scanning, stratified splitting, tf.data pipeline, and class weights."""

import json
import os
from pathlib import Path

import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split

from .preprocess import preprocess, build_augmentation_layer


def scan_dataset(raw_dir: str, classes: list[str]) -> dict[str, list[str]]:
    """Scan raw_dir for images organized by class folders.

    Folder names use underscores for spaces (e.g., Muito_Argilosa -> "Muito Argilosa").

    Args:
        raw_dir: Path to data/raw/ directory.
        classes: List of class names from config.

    Returns:
        Dict mapping class name to list of image file paths.

    Raises:
        FileNotFoundError: If raw_dir does not exist.
        ValueError: If a class folder is missing or empty.
    """
    raw_path = Path(raw_dir)
    if not raw_path.exists():
        raise FileNotFoundError(f"Raw data directory not found: {raw_dir}")

    class_to_folder = {c: c.replace(" ", "_") for c in classes}
    result = {}

    for class_name, folder_name in class_to_folder.items():
        folder_path = raw_path / folder_name
        if not folder_path.exists():
            raise ValueError(f"Class folder not found: {folder_path}")

        images = sorted([
            str(f) for f in folder_path.iterdir()
            if f.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
        ])

        if not images:
            raise ValueError(f"No images found in {folder_path}")

        result[class_name] = images

    return result


def create_splits(
    class_images: dict[str, list[str]],
    val_split: float,
    test_split: float,
    seed: int,
    splits_dir: str,
) -> dict[str, list[dict]]:
    """Create stratified train/val/test splits and save manifests.

    Args:
        class_images: Dict from scan_dataset.
        val_split: Fraction for validation.
        test_split: Fraction for test.
        seed: Random seed.
        splits_dir: Directory to save split manifests.

    Returns:
        Dict with "train", "val", "test" keys, each a list of
        {"path": str, "label": int, "class": str}.
    """
    all_paths = []
    all_labels = []
    classes = sorted(class_images.keys())
    class_to_idx = {c: i for i, c in enumerate(classes)}

    for class_name, paths in class_images.items():
        label = class_to_idx[class_name]
        all_paths.extend(paths)
        all_labels.extend([label] * len(paths))

    all_paths = np.array(all_paths)
    all_labels = np.array(all_labels)

    # First split: separate test set
    train_val_paths, test_paths, train_val_labels, test_labels = train_test_split(
        all_paths, all_labels,
        test_size=test_split,
        stratify=all_labels,
        random_state=seed,
    )

    # Second split: separate validation from training
    relative_val = val_split / (1 - test_split)
    train_paths, val_paths, train_labels, val_labels = train_test_split(
        train_val_paths, train_val_labels,
        test_size=relative_val,
        stratify=train_val_labels,
        random_state=seed,
    )

    idx_to_class = {i: c for c, i in class_to_idx.items()}

    def _build_manifest(paths, labels):
        return [
            {"path": str(p), "label": int(l), "class": idx_to_class[int(l)]}
            for p, l in zip(paths, labels)
        ]

    splits = {
        "train": _build_manifest(train_paths, train_labels),
        "val": _build_manifest(val_paths, val_labels),
        "test": _build_manifest(test_paths, test_labels),
    }

    # Save manifests
    splits_path = Path(splits_dir)
    splits_path.mkdir(parents=True, exist_ok=True)

    manifest = {
        "seed": seed,
        "classes": classes,
        "class_to_idx": class_to_idx,
        "counts": {
            "train": len(splits["train"]),
            "val": len(splits["val"]),
            "test": len(splits["test"]),
        },
        "splits": splits,
    }

    with open(splits_path / "splits.json", "w") as f:
        json.dump(manifest, f, indent=2)

    return splits


def load_splits(splits_dir: str) -> dict:
    """Load existing split manifest from disk.

    Args:
        splits_dir: Path to data/splits/ directory.

    Returns:
        Full manifest dict with splits, classes, counts.

    Raises:
        FileNotFoundError: If splits.json does not exist.
    """
    splits_path = Path(splits_dir) / "splits.json"
    if not splits_path.exists():
        raise FileNotFoundError(f"Split manifest not found: {splits_path}")

    with open(splits_path, "r") as f:
        return json.load(f)


def _parse_image(path: str, label: int, cfg: dict) -> tuple[tf.Tensor, tf.Tensor]:
    """Load and preprocess a single image."""
    raw = tf.io.read_file(path)
    image = tf.io.decode_image(raw, channels=3, expand_animations=False)
    image.set_shape([None, None, 3])
    image = preprocess(image, cfg)
    return image, tf.one_hot(label, len(cfg["classes"]))


def build_dataset(
    split_entries: list[dict],
    cfg: dict,
    augment: bool = False,
    shuffle: bool = False,
) -> tf.data.Dataset:
    """Build a tf.data.Dataset from split manifest entries.

    Args:
        split_entries: List of {"path", "label", "class"} dicts.
        cfg: Configuration dictionary.
        augment: Whether to apply augmentation.
        shuffle: Whether to shuffle the dataset.

    Returns:
        Batched tf.data.Dataset yielding (images, one_hot_labels).
    """
    paths = [e["path"] for e in split_entries]
    labels = [e["label"] for e in split_entries]

    ds = tf.data.Dataset.from_tensor_slices((paths, labels))

    if shuffle:
        ds = ds.shuffle(buffer_size=len(paths), seed=cfg["data"]["seed"])

    ds = ds.map(
        lambda p, l: _parse_image(p, l, cfg),
        num_parallel_calls=tf.data.AUTOTUNE,
    )

    if augment:
        aug_layer = build_augmentation_layer(cfg)
        ds = ds.map(
            lambda img, lbl: (aug_layer(img, training=True), lbl),
            num_parallel_calls=tf.data.AUTOTUNE,
        )

    batch_size = cfg["training"]["batch_size"]
    ds = ds.batch(batch_size).prefetch(tf.data.AUTOTUNE)

    return ds


def compute_class_weights(split_entries: list[dict], num_classes: int) -> dict[int, float]:
    """Compute balanced class weights for imbalanced datasets.

    Formula: weight_i = n_samples / (n_classes * n_samples_i)

    Args:
        split_entries: List of {"path", "label", "class"} dicts (training split).
        num_classes: Total number of classes.

    Returns:
        Dict mapping class index to weight, e.g. {0: 1.2, 1: 0.8, ...}.
    """
    labels = [e["label"] for e in split_entries]
    n_samples = len(labels)
    counts = np.bincount(labels, minlength=num_classes)

    weights = {}
    for i in range(num_classes):
        if counts[i] > 0:
            weights[i] = n_samples / (num_classes * counts[i])
        else:
            weights[i] = 1.0

    return weights
