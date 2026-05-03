"""Dataset scanning, stratified splitting, tf.data pipeline, and class weights."""

import json
import os
import re
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


def _extract_sample_id(filepath: str) -> str:
    """Extract sample ID from filename for group-aware splitting.

    Handles patterns like "100147,21 (6).JPG" -> "100147,21"
    and "sample_name.jpg" -> "sample_name" (single-image samples).

    Args:
        filepath: Full path to an image file.

    Returns:
        Sample group identifier.
    """
    stem = Path(filepath).stem
    # Match pattern: "name (N)" where N is a number
    match = re.match(r"^(.+?)\s*\(\d+\)$", stem)
    if match:
        return match.group(1).strip()
    return stem


def create_splits(
    class_images: dict[str, list[str]],
    val_split: float,
    test_split: float,
    seed: int,
    splits_dir: str,
) -> dict[str, list[dict]]:
    """Create group-aware stratified train/val/test splits and save manifests.

    Groups images by sample ID so all photos of the same soil sample
    stay in the same split, preventing data leakage.

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
    classes = list(class_images.keys())
    class_to_idx = {c: i for i, c in enumerate(classes)}
    idx_to_class = {i: c for c, i in class_to_idx.items()}

    # Build groups: each group = (sample_id, class_label, [file_paths])
    group_ids = []
    group_labels = []
    group_files: list[list[str]] = []

    for class_name, paths in class_images.items():
        label = class_to_idx[class_name]
        # Group files by sample ID within this class
        sample_groups: dict[str, list[str]] = {}
        for p in paths:
            sid = _extract_sample_id(p)
            sample_groups.setdefault(sid, []).append(p)

        for sid, files in sample_groups.items():
            group_ids.append(f"{class_name}::{sid}")
            group_labels.append(label)
            group_files.append(files)

    group_ids = np.array(group_ids)
    group_labels = np.array(group_labels)

    # Validate minimum groups per class for stratified splitting
    # Each class needs at least 3 groups to have >=1 in train, val, and test
    from collections import Counter
    label_counts = Counter(group_labels.tolist())
    min_groups = 3
    for label_idx, count in label_counts.items():
        if count < min_groups:
            cls_name = idx_to_class[label_idx]
            raise ValueError(
                f"Class '{cls_name}' has only {count} sample group(s), "
                f"but at least {min_groups} are required for stratified "
                f"train/val/test splitting."
            )

    # Split at the group level (stratified by class)
    train_val_idx, test_idx = train_test_split(
        np.arange(len(group_ids)),
        test_size=test_split,
        stratify=group_labels,
        random_state=seed,
    )

    relative_val = val_split / (1 - test_split)
    train_idx, val_idx = train_test_split(
        train_val_idx,
        test_size=relative_val,
        stratify=group_labels[train_val_idx],
        random_state=seed,
    )

    def _build_manifest(indices):
        entries = []
        for i in indices:
            label = int(group_labels[i])
            for p in group_files[i]:
                entries.append({
                    "path": str(p),
                    "label": label,
                    "class": idx_to_class[label],
                })
        return entries

    splits = {
        "train": _build_manifest(train_idx),
        "val": _build_manifest(val_idx),
        "test": _build_manifest(test_idx),
    }

    # Save manifests
    splits_path = Path(splits_dir)
    splits_path.mkdir(parents=True, exist_ok=True)

    manifest = {
        "seed": seed,
        "val_split": val_split,
        "test_split": test_split,
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


def validate_splits_against_config(manifest: dict, cfg: dict) -> None:
    """Validate that splits.json is compatible with the active config.

    Args:
        manifest: Loaded splits manifest dict.
        cfg: Configuration dictionary.

    Raises:
        ValueError: If classes, seed, or split fractions diverge.
    """
    if manifest["classes"] != cfg["classes"]:
        raise ValueError(
            f"splits.json classes {manifest['classes']} != "
            f"config classes {cfg['classes']}. "
            "Delete splits.json and re-run to regenerate."
        )
    if manifest.get("seed") != cfg["data"]["seed"]:
        raise ValueError(
            f"splits.json seed {manifest.get('seed')} != "
            f"config seed {cfg['data']['seed']}. "
            "Delete splits.json and re-run to regenerate."
        )
    if "val_split" in manifest:
        if manifest["val_split"] != cfg["data"]["val_split"]:
            raise ValueError(
                f"splits.json val_split {manifest['val_split']} != "
                f"config val_split {cfg['data']['val_split']}. "
                "Delete splits.json and re-run to regenerate."
            )
    if "test_split" in manifest:
        if manifest["test_split"] != cfg["data"]["test_split"]:
            raise ValueError(
                f"splits.json test_split {manifest['test_split']} != "
                f"config test_split {cfg['data']['test_split']}. "
                "Delete splits.json and re-run to regenerate."
            )


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
