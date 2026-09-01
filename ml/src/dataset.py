"""Dataset scanning, stratified splitting, tf.data pipeline, and class weights.

TensorFlow, and the preprocessing layer built on it, are imported on first use
rather than at module import. Validating a
dataset — the manifest, the splits, and their provenance — has to be possible
for a collector who has not installed the training stack, and
``scripts/validate_dataset.py`` reaches this module for its split generation.
The import is cached by Python after the first call, so the pipeline pays nothing
for it. ``tests/test_manifest_splits.py`` asserts the property holds.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import TYPE_CHECKING, Collection, Mapping

import numpy as np
from sklearn.model_selection import train_test_split

if TYPE_CHECKING:  # Annotations only; the runtime import is in _tensorflow().
    import tensorflow as tf

from .manifest import (
    IMAGE_SUFFIXES,
    check_class_coverage,
    class_images as manifest_class_images,
    dataset_root,
    read_manifest_or_none,
    sample_ids_by_image,
    train_only_sample_ids,
    verify_split_digest,
)


def _tensorflow():
    """Return the TensorFlow module, importing it on first use."""
    import tensorflow as tf

    return tf


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
            if f.suffix.lower() in IMAGE_SUFFIXES
        ])

        if not images:
            raise ValueError(f"No images found in {folder_path}")

        result[class_name] = images

    return result


def verify_images(class_images: dict[str, list[str]]) -> None:
    """Open every listed image and raise if any cannot be decoded.

    Called before training builds anything, so an unreadable file is a refusal
    to start rather than a crash partway through an epoch. Every bad file is
    named in one message: the operator fixes the dataset in one pass instead of
    discovering the next broken file on the next attempt.

    Skipping bad files with a warning was considered and rejected. It would make
    the effective dataset differ between runs of one configuration without
    changing `splits.json`, which is exactly the reproducibility this pipeline
    is supposed to have.

    Args:
        class_images: Mapping of class name to image file paths.

    Raises:
        ValueError: If any file is missing or cannot be decoded.
    """
    tf = _tensorflow()
    failures: list[str] = []

    for class_name in sorted(class_images):
        for path in class_images[class_name]:
            try:
                # Decode through the SAME path `_parse_image` uses at training
                # time. Verifying with a different decoder is worse than not
                # verifying at all: it reports success for files that will fail
                # mid-epoch. Pillow was used here first and reads `.webp`, which
                # `scan_dataset` admits and `tf.io.decode_image` cannot read, so
                # every `.webp` in a dataset passed verification and then broke
                # training.
                raw = tf.io.read_file(path)
                image = tf.io.decode_image(raw, channels=3, expand_animations=False)
                image.shape.assert_has_rank(3)
            except Exception as error:
                failures.append(f"  {path}: {type(error).__name__}: {error}")

    if failures:
        raise ValueError(
            f"{len(failures)} image(s) could not be read:\n" + "\n".join(failures)
        )


def _group_id(class_name: str, sample_id: str) -> str:
    """The key splits are grouped by.

    Scoped to the class because one soil sample carries one laboratory texture
    class and therefore lives in exactly one class folder. Two files sharing a
    stem across folders are different physical samples whose names collided.
    """
    return f"{class_name}::{sample_id}"


def sample_id_from_filename(filepath: str) -> str:
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


def _sample_id_of(path: str, sample_ids: Mapping[str, str] | None) -> str:
    """Return the sample a file belongs to.

    Prefers the manifest's declared identifier: a filename pattern can silently
    regroup a dataset when a collector renames a file, and the group is what
    keeps one physical sample out of two splits.
    """
    if sample_ids is None:
        return sample_id_from_filename(path)
    declared = sample_ids.get(path)
    if declared is None:
        raise ValueError(
            f"no sample_id declared for {path!r}. Every image passed to "
            "create_splits must appear in the manifest it was listed from"
        )
    return declared


def create_splits(
    class_images: dict[str, list[str]],
    val_split: float,
    test_split: float,
    seed: int,
    splits_dir: str,
    sample_ids: Mapping[str, str] | None = None,
    dataset_version: str | None = None,
    manifest_digest: str | None = None,
    train_only_samples: Collection[str] | None = None,
) -> dict[str, list[dict]]:
    """Create group-aware stratified train/val/test splits and save manifests.

    Groups images by sample ID so all photos of the same soil sample
    stay in the same split, preventing data leakage.

    Args:
        class_images: Dict from scan_dataset or `manifest.class_images`.
        val_split: Fraction for validation.
        test_split: Fraction for test.
        seed: Random seed.
        splits_dir: Directory to save split manifests.
        sample_ids: Image path to sample id, from the manifest's `sample_id`
            column. Given, the group is what the collector declared; omitted,
            the id is inferred from the filename, which is the folder-scan path
            that predates the manifest.
        dataset_version: The immutable version directory the images came from.
        manifest_digest: Digest of the manifest they were listed in, so a split
            can be shown to belong to the data it claims.
        train_only_samples: Sample ids that may enter training and never
            validation or test. They are removed before the stratified split
            runs and appended to train afterwards, so they neither influence
            the stratification nor appear in a score. See
            `manifest.TRAIN_ONLY_SOURCE_GROUPS`.

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

    restricted = set(train_only_samples or ())
    # Kept separate from the splittable groups rather than filtered out of the
    # result afterwards: a restricted group left in the stratification would
    # shift the class proportions the split is trying to preserve, and the
    # correction would then be invisible in the counts.
    train_only_files: list[tuple[int, list[str]]] = []

    for class_name, paths in class_images.items():
        label = class_to_idx[class_name]
        # Group files by sample ID within this class
        sample_groups: dict[str, list[str]] = {}
        for p in paths:
            sid = _sample_id_of(p, sample_ids)
            sample_groups.setdefault(sid, []).append(p)

        for sid, files in sample_groups.items():
            if sid in restricted:
                train_only_files.append((label, files))
                continue
            group_ids.append(_group_id(class_name, sid))
            group_labels.append(label)
            group_files.append(files)

    if not group_ids:
        raise ValueError(
            "every sample group is restricted to training, so no validation or "
            "test split can be formed. Check train_only_samples against the "
            "manifest's source_group column"
        )

    group_ids = np.array(group_ids)
    group_labels = np.array(group_labels)

    # Validate minimum groups per class for stratified splitting
    # Each class needs at least 3 groups to have >=1 in train, val, and test
    from collections import Counter
    label_counts = Counter(group_labels.tolist())
    min_groups = 3
    # Over every class, not over the counter's keys: a class whose groups are
    # all restricted to training leaves no entry in the counter at all, so
    # iterating the counter would pass it silently — and validation and test
    # would then omit a class the model still has an output for.
    for label_idx in sorted(idx_to_class):
        count = label_counts.get(label_idx, 0)
        if count < min_groups:
            cls_name = idx_to_class[label_idx]
            raise ValueError(
                f"Class '{cls_name}' has only {count} splittable sample group(s), "
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

    train_entries = _build_manifest(train_idx)
    for label, files in train_only_files:
        train_entries.extend(
            {"path": str(p), "label": label, "class": idx_to_class[label]}
            for p in files
        )

    splits = {
        "train": train_entries,
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
        # Provenance, so "the model got worse" and "the dataset changed" stay
        # distinguishable. Absent on the folder-scan path, which has neither.
        "dataset_version": dataset_version,
        "manifest_digest": manifest_digest,
        "classes": classes,
        "class_to_idx": class_to_idx,
        "counts": {
            "train": len(splits["train"]),
            "val": len(splits["val"]),
            "test": len(splits["test"]),
        },
        "train_only_samples": sorted(restricted),
        "splits": splits,
    }

    with open(splits_path / "splits.json", "w") as f:
        json.dump(manifest, f, indent=2)

    return splits


def create_splits_for_config(cfg: Mapping, splits_dir: str) -> dict[str, list[dict]]:
    """Create splits for ``cfg``, preferring the manifest over a folder scan.

    The manifest is preferred because it declares three things a directory
    cannot: which physical sample each photograph belongs to, which dataset
    version and manifest the split was generated from, and which capture
    population a row came from. Grouping in particular stops being a guess —
    without the declared ids `_sample_id_of` falls back to a filename pattern,
    and a pattern that happens to fit is the worst case, because nothing reports
    that it was used.

    The folder scan remains for a version that has no manifest yet, and says so
    rather than falling back quietly.
    """
    data = cfg["data"]
    root = dataset_root(data["datasets_dir"], data["dataset_version"])
    manifest = read_manifest_or_none(root, cfg["classes"])

    if manifest is None:
        print(
            f"No manifest at {root}; falling back to the folder scan of "
            f"{data['raw_dir']}. Sample grouping will be inferred from filenames "
            f"and the split will record no dataset version."
        )
        return create_splits(
            scan_dataset(data["raw_dir"], cfg["classes"]),
            val_split=data["val_split"],
            test_split=data["test_split"],
            seed=data["seed"],
            splits_dir=splits_dir,
        )

    absent = check_class_coverage(manifest, cfg["classes"])
    if absent:
        raise ValueError(
            "the dataset version does not cover every configured class:\n  - "
            + "\n  - ".join(absent)
        )

    restricted = train_only_sample_ids(manifest)
    if restricted:
        print(
            f"{len(restricted)} sample group(s) are restricted to training by "
            f"their source group; they will not appear in validation or test."
        )

    return create_splits(
        manifest_class_images(manifest, cfg["classes"]),
        val_split=data["val_split"],
        test_split=data["test_split"],
        seed=data["seed"],
        splits_dir=splits_dir,
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        train_only_samples=restricted,
    )


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


def load_splits(splits_dir: str, manifest_digest: str | None = None) -> dict:
    """Load existing split manifest from disk.

    Args:
        splits_dir: Path to data/splits/ directory.
        manifest_digest: Digest of the dataset manifest the caller intends to
            use. Given, a split that does not belong to it is refused rather
            than silently training on a different set of images.

    Returns:
        Full manifest dict with splits, classes, counts.

    Raises:
        FileNotFoundError: If splits.json does not exist.
        ValueError: If the split does not belong to `manifest_digest`.
    """
    splits_path = Path(splits_dir) / "splits.json"
    if not splits_path.exists():
        raise FileNotFoundError(f"Split manifest not found: {splits_path}")

    with open(splits_path, "r") as f:
        manifest = json.load(f)

    if manifest_digest is not None:
        verify_split_digest(manifest, manifest_digest)

    return manifest


def _parse_image(path: str, label: int, cfg: dict) -> tuple[tf.Tensor, tf.Tensor]:
    """Load and preprocess a single image."""
    from .preprocess import preprocess

    tf = _tensorflow()
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
    from .preprocess import build_augmentation_layer

    tf = _tensorflow()
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
