"""Dataset scanning, fold generation, tf.data pipeline, and class weights.

The evaluation protocol is repeated stratified group k-fold with nested
selection (ADR 0020, SPEC 0042): the unit is the physical sample group, every
splittable group is tested exactly once per repeat, and the choice made for an
outer fold is made on inner folds of that fold's own training side. There is no
single ``train``/``val``/``test`` partition here and no code path that produces
one.

TensorFlow, and the preprocessing layer built on it, are imported on first use
rather than at module import. Validating a dataset — the manifest, the folds,
and their provenance — has to be possible for a collector who has not installed
the training stack, and ``scripts/validate_dataset.py`` reaches this module for
its fold generation. The import is cached by Python after the first call, so the
pipeline pays nothing for it. ``tests/test_manifest_splits.py`` asserts the
property holds.
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import TYPE_CHECKING, Collection, Mapping

import numpy as np
from sklearn.model_selection import StratifiedGroupKFold

if TYPE_CHECKING:  # Annotations only; the runtime import is in _tensorflow().
    import tensorflow as tf

from .manifest import (
    FOLD_COMPOSITION_AXES,
    IMAGE_SUFFIXES,
    check_class_coverage,
    class_images as manifest_class_images,
    dataset_root,
    format_composition,
    read_manifest_or_none,
    sample_ids_by_image,
    split_composition,
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
            "create_folds must appear in the manifest it was listed from"
        )
    return declared


#: Schema of the fold manifest. Version 1 was SPEC 0033's single
#: `train`/`val`/`test` partition; version 2 is the repeated group k-fold
#: assignment of ADR 0020. The version is refused rather than migrated, because
#: a version-1 file records a design that no longer produces a valid number.
FOLD_SCHEMA_VERSION = 2

#: The fold manifest keeps the path and the name the split manifest had, so
#: every tool, ignore rule and provenance guard that names it keeps working.
FOLD_MANIFEST_FILENAME = "splits.json"

#: How a repeat's seed is derived, recorded in the manifest so a reader can
#: reproduce a repeat without reading this file.
SEED_STRIDE_PER_REPEAT = 1000
SEED_DERIVATION = "seed_r = data.seed + 1000 * r"

#: Offset that separates an inner-selection seed from any repeat seed. The
#: inner loop must not draw the same permutation the outer loop drew, and a
#: stride of one would collide with the next repeat's seed at k >= 1000.
INNER_SEED_OFFSET = 1

#: What an operator is told to run when the fold manifest cannot be used. Named
#: in the refusal rather than described, because the file is git-ignored and
#: regenerating it is the only remedy.
REGENERATE_FOLDS_COMMAND = (
    "python scripts/validate_dataset.py --version <version> "
    "--splits-dir data/splits"
)


def derive_repeat_seed(seed: int, repeat: int) -> int:
    """The seed repeat ``repeat`` draws its folds from.

    Derived rather than drawn so that a repeat is reproducible from the config
    alone, and strided by 1000 so two repeats of one experiment cannot collide
    with each other or with a neighbouring configured seed.
    """
    return seed + SEED_STRIDE_PER_REPEAT * repeat


def derive_inner_seed(seed: int, repeat: int, fold: int) -> int:
    """The seed the inner selection folds of one outer fold are drawn from."""
    return derive_repeat_seed(seed, repeat) + INNER_SEED_OFFSET + fold


def create_folds(
    class_images: dict[str, list[str]],
    *,
    k: int,
    repeats: int,
    seed: int,
    splits_dir: str,
    sample_ids: Mapping[str, str] | None = None,
    dataset_version: str | None = None,
    manifest_digest: str | None = None,
    train_only_samples: Collection[str] | None = None,
) -> dict:
    """Assign every splittable sample group a fold index, once per repeat.

    Photographs are grouped by the sample they photograph, and the group — never
    the photograph — is what a fold holds, so no physical sample is ever both
    trained on and scored. Stratification is by class at the group level, which
    is the level every interval and every contrast is computed at (ADR 0020).

    Groups named by ``train_only_samples`` are kept out of the partition
    entirely and appended to every fold's training side. They are excluded
    before stratification rather than filtered out afterwards: a restricted
    group left in would shift the class proportions the folds are trying to
    preserve, and the correction would then be invisible in the counts.

    Args:
        class_images: Class name to image paths, from ``manifest.class_images``.
        k: Number of outer folds. Each class needs at least this many
            splittable groups, so that every fold's test side holds one.
        repeats: Number of times the whole partition is redrawn.
        seed: Base seed; repeat r uses :func:`derive_repeat_seed`.
        splits_dir: Directory the fold manifest is written to.
        sample_ids: Image path to declared sample id. Given, the group is what
            the collector declared; omitted, it is inferred from the filename.
        dataset_version: The immutable version the images came from.
        manifest_digest: Digest of the manifest they were listed in, so a result
            can be shown to belong to the data it claims.
        train_only_samples: Sample ids that may train and never be scored. See
            ``manifest.TRAIN_ONLY_SOURCE_GROUPS`` and SPEC 0040 D6.

    Returns:
        The fold manifest, which is also written to
        ``<splits_dir>/splits.json``.

    Raises:
        ValueError: If ``k`` or ``repeats`` is out of range, or if any class
            holds fewer than ``k`` splittable groups.
    """
    if k < 2:
        raise ValueError(f"k must be at least 2, got {k}")
    if repeats < 1:
        raise ValueError(f"repeats must be at least 1, got {repeats}")

    classes = list(class_images.keys())
    class_to_idx = {name: index for index, name in enumerate(classes)}
    groups = _group_records(class_images, sample_ids, train_only_samples)

    splittable = [
        group_id for group_id, record in groups.items() if not record["train_only"]
    ]
    if not splittable:
        raise ValueError(
            "every sample group is restricted to training, so no fold has a "
            "test side. Check train_only_samples against the manifest's "
            "source_group column"
        )
    _refuse_a_class_below_the_fold_count(groups, splittable, classes, k)

    labels = np.array([groups[group_id]["label"] for group_id in splittable])
    assignments = {
        str(repeat): _assign_folds(splittable, labels, k, derive_repeat_seed(seed, repeat))
        for repeat in range(repeats)
    }
    # Train-only groups carry a null index rather than being omitted: "in no
    # test side" is a fact about them, and a reader who finds the key missing
    # cannot tell it from a group the generator forgot.
    for repeat_folds in assignments.values():
        for group_id, record in groups.items():
            if record["train_only"]:
                repeat_folds[group_id] = None

    fold_manifest = {
        "schema_version": FOLD_SCHEMA_VERSION,
        "dataset_version": dataset_version,
        "manifest_digest": manifest_digest,
        "classes": classes,
        "class_to_idx": class_to_idx,
        "k": k,
        "repeats": repeats,
        "seed": seed,
        "seed_derivation": SEED_DERIVATION,
        "seeds": {
            str(repeat): derive_repeat_seed(seed, repeat) for repeat in range(repeats)
        },
        "train_only_samples": sorted(set(train_only_samples or ())),
        "groups": groups,
        "folds": assignments,
        "counts": {
            "groups": len(groups),
            "splittable_groups": len(splittable),
            "train_only_groups": len(groups) - len(splittable),
            "photographs": sum(len(r["images"]) for r in groups.values()),
        },
    }

    destination = Path(splits_dir)
    destination.mkdir(parents=True, exist_ok=True)
    with open(destination / FOLD_MANIFEST_FILENAME, "w") as handle:
        json.dump(fold_manifest, handle, indent=2)

    return fold_manifest


def create_folds_for_config(cfg: Mapping, splits_dir: str) -> dict:
    """Generate the fold manifest for ``cfg``, from the dataset's own manifest.

    The manifest is required rather than preferred. The folder scan that
    predates it cannot say which physical sample a photograph belongs to, and
    grouping is what every guarantee in this protocol rests on: without the
    declared ids the group would be inferred from a filename pattern, and a
    pattern that happens to fit is the worst case, because nothing reports that
    it was used.
    """
    data = cfg["data"]
    evaluation = cfg["evaluation"]
    root = dataset_root(data["datasets_dir"], data["dataset_version"])
    manifest = read_manifest_or_none(root, cfg["classes"])

    if manifest is None:
        raise FileNotFoundError(
            f"no manifest at {root}. The evaluation protocol groups by the "
            "declared sample_id, so a dataset version without a manifest "
            "cannot be partitioned into folds"
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
            f"their source group; they will be in every fold's training side "
            f"and in no fold's test side."
        )

    return create_folds(
        manifest_class_images(manifest, cfg["classes"]),
        k=evaluation["k"],
        repeats=evaluation["repeats"],
        seed=data["seed"],
        splits_dir=splits_dir,
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        train_only_samples=restricted,
    )


def load_folds(splits_dir: str, manifest_digest: str | None = None) -> dict:
    """Load the fold manifest, refusing one that cannot produce a valid number.

    Args:
        splits_dir: Directory holding ``splits.json``.
        manifest_digest: Digest of the dataset manifest the caller intends to
            use. Given, a manifest that does not belong to it is refused rather
            than silently scoring a different set of images.

    Returns:
        The fold manifest dict.

    Raises:
        FileNotFoundError: If the file does not exist.
        ValueError: If its schema is not :data:`FOLD_SCHEMA_VERSION`, or if it
            does not belong to ``manifest_digest``.
    """
    path = Path(splits_dir) / FOLD_MANIFEST_FILENAME
    if not path.exists():
        raise FileNotFoundError(
            f"fold manifest not found: {path}. Generate it with: "
            f"{REGENERATE_FOLDS_COMMAND}"
        )

    with open(path, "r") as handle:
        fold_manifest = json.load(handle)

    recorded = fold_manifest.get("schema_version")
    if recorded != FOLD_SCHEMA_VERSION:
        # Named, not migrated. A version-1 file records one train/val/test
        # partition, and reinterpreting it as folds would produce a number that
        # looks like a cross-validated one and is not.
        described = (
            "a SPEC 0033 train/val/test split"
            if recorded is None
            else f"schema_version {recorded}"
        )
        raise ValueError(
            f"{path} is {described}, not schema_version {FOLD_SCHEMA_VERSION}. "
            f"The evaluation protocol is repeated group k-fold (ADR 0020) and "
            f"cannot read it. Regenerate the fold manifest with: "
            f"{REGENERATE_FOLDS_COMMAND}"
        )

    if manifest_digest is not None:
        verify_split_digest(fold_manifest, manifest_digest)

    return fold_manifest


def fold_split(fold_manifest: Mapping, repeat: int, fold: int) -> dict[str, list[dict]]:
    """Return the training and test entries of one outer fold.

    The training side is every group not in this fold's test side, which is
    every other splittable group plus every train-only group. That is the set
    the refit is fitted on, and it is built here so no caller can assemble a
    training side that differs from the one the audit was written against.
    """
    assignments = _repeat_assignments(fold_manifest, repeat)
    _require_fold_in_range(fold_manifest, fold)

    train: list[dict] = []
    test: list[dict] = []
    for group_id, index in assignments.items():
        side = test if index == fold else train
        side.extend(_entries_of(fold_manifest, group_id))
    return {"train": train, "test": test}


def inner_folds(
    fold_manifest: Mapping, repeat: int, fold: int, inner_k: int
) -> list[dict[str, list[dict]]]:
    """Split one outer fold's training side into nested selection folds.

    Every choice made for an outer fold — checkpoint, hyper-parameter, encoder,
    threshold — is made on these, and never on the outer fold's own test side.
    Un-nested selection is the optimistic bias Vabalas et al. (2019) measure as
    dominant at this sample size, and it is what ADR 0020 exists to remove.

    Train-only groups are in every inner training side and in no inner
    validation side, for the same reason they are in no outer test side: they
    are not representative of deployment and a score computed on them is not a
    score of the model's task.
    """
    if inner_k < 2:
        raise ValueError(f"inner_k must be at least 2, got {inner_k}")

    assignments = _repeat_assignments(fold_manifest, repeat)
    _require_fold_in_range(fold_manifest, fold)

    selectable = [
        group_id
        for group_id, index in assignments.items()
        if index is not None and index != fold
    ]
    always_train = [
        group_id for group_id, index in assignments.items() if index is None
    ]
    labels = np.array(
        [fold_manifest["groups"][group_id]["label"] for group_id in selectable]
    )
    seed = derive_inner_seed(fold_manifest["seed"], repeat, fold)
    inner_assignment = _assign_folds(selectable, labels, inner_k, seed)

    splits = []
    for inner in range(inner_k):
        validation_groups = [
            group_id
            for group_id in selectable
            if inner_assignment[group_id] == inner
        ]
        training_groups = [
            group_id
            for group_id in selectable
            if inner_assignment[group_id] != inner
        ] + always_train
        splits.append(
            {
                "train": _entries_for(fold_manifest, training_groups),
                "val": _entries_for(fold_manifest, validation_groups),
            }
        )
    return splits


def selection_groups(
    fold_manifest: Mapping, repeat: int, fold: int, inner_k: int
) -> set[str]:
    """Every sample group read while selecting a setting for one outer fold.

    Derived from the inner splits themselves rather than restated, so a defect
    in :func:`inner_folds` shows up here instead of being papered over by an
    audit that describes what the code was supposed to do.
    """
    read: set[str] = set()
    for split in inner_folds(fold_manifest, repeat, fold, inner_k):
        for side in ("train", "val"):
            read.update(entry["group"] for entry in split[side])
    return read


def permute_labels_by_group(entries: list[dict], seed: int) -> list[dict]:
    """Permute class labels across sample groups, for the shuffled control.

    Across groups and not across photographs: permuting photographs would leave
    each group carrying a mixture of labels, so a model could still learn "these
    two photographs belong together" and score above chance on a control that is
    supposed to have no signal left in it.

    The entries are returned as new dicts; the caller's list is untouched, which
    is what keeps a fold's test side out of reach of this function by
    construction.
    """
    labels_by_group: dict[str, int] = {}
    for entry in entries:
        existing = labels_by_group.setdefault(entry["group"], entry["label"])
        if existing != entry["label"]:
            raise ValueError(
                f"group {entry['group']!r} carries more than one label, so it "
                "is not a sample group"
            )

    group_ids = sorted(labels_by_group)
    generator = np.random.default_rng(seed)
    permuted = [
        int(label)
        for label in generator.permutation([labels_by_group[g] for g in group_ids])
    ]
    reassigned = dict(zip(group_ids, permuted))

    index_to_class = _index_to_class(entries)
    return [
        {
            **entry,
            "label": reassigned[entry["group"]],
            "class": index_to_class[reassigned[entry["group"]]],
        }
        for entry in entries
    ]


def format_fold_composition(fold_manifest: Mapping, manifest) -> str:
    """Render every fold's training and test composition, per repeat.

    Reported rather than held out, so the two rules that govern a fold can be
    checked by eye as well as by test: every class appears in every test side,
    and the transported population (source group B, SPEC 0040 D6) appears only
    on training sides.
    """
    blocks = []
    for repeat in range(fold_manifest["repeats"]):
        for fold in range(fold_manifest["k"]):
            split = fold_split(fold_manifest, repeat, fold)
            blocks.append(
                f"repeat {repeat} fold {fold}:\n"
                + format_composition(
                    split_composition(split, manifest),
                    axes=FOLD_COMPOSITION_AXES,
                    indent="  ",
                )
            )
    return "\n".join(blocks)


def _index_to_class(entries: list[dict]) -> dict[int, str]:
    """The label-to-name map the entries themselves carry."""
    mapping: dict[int, str] = {}
    for entry in entries:
        mapping.setdefault(entry["label"], entry["class"])
    return mapping


def _group_records(
    class_images: Mapping[str, list[str]],
    sample_ids: Mapping[str, str] | None,
    train_only_samples: Collection[str] | None,
) -> dict[str, dict]:
    """Build the group table the fold manifest carries, in a stable order."""
    restricted = set(train_only_samples or ())
    groups: dict[str, dict] = {}

    for label, (class_name, paths) in enumerate(class_images.items()):
        by_sample: dict[str, list[str]] = {}
        for path in paths:
            by_sample.setdefault(_sample_id_of(path, sample_ids), []).append(path)
        for sample_id in sorted(by_sample):
            groups[_group_id(class_name, sample_id)] = {
                "sample_id": sample_id,
                "class": class_name,
                "label": label,
                "images": sorted(str(path) for path in by_sample[sample_id]),
                "train_only": sample_id in restricted,
            }

    if not groups:
        raise ValueError(
            "no sample group was found in the class images passed to "
            "create_folds. Check the manifest against the configured classes"
        )
    return groups


def _refuse_a_class_below_the_fold_count(
    groups: Mapping[str, dict],
    splittable: list[str],
    classes: list[str],
    k: int,
) -> None:
    """Refuse a class that cannot put a group in every fold's test side.

    Over every configured class, not over the classes that happen to have a
    splittable group: a class restricted entirely to training leaves no entry to
    iterate at all, and the model would keep an output for a class no fold ever
    scores.
    """
    counts = Counter(groups[group_id]["class"] for group_id in splittable)
    for class_name in classes:
        count = counts.get(class_name, 0)
        if count < k:
            raise ValueError(
                f"class {class_name!r} has only {count} splittable sample "
                f"group(s), but k = {k} folds need at least {k} so that every "
                f"fold's test side holds one. Lower evaluation.k, or drop the "
                f"class from config.yaml as ADR 0016 drops Siltosa"
            )


def _assign_folds(
    group_ids: list[str], labels: np.ndarray, splits: int, seed: int
) -> dict[str, int]:
    """Assign each group a fold index with StratifiedGroupKFold.

    One row per group, so the stratification the generator balances is the
    group-level one every interval is computed at. Passing one row per
    photograph would balance photograph counts instead, and a class whose
    samples carry uneven numbers of photographs would then land unevenly at the
    level that matters.
    """
    splitter = StratifiedGroupKFold(
        n_splits=splits, shuffle=True, random_state=seed
    )
    features = np.zeros((len(group_ids), 1))
    assignment: dict[str, int] = {}
    for index, (_, held_out) in enumerate(
        splitter.split(features, labels, groups=np.array(group_ids))
    ):
        for position in held_out:
            assignment[group_ids[position]] = index
    return assignment


def _repeat_assignments(fold_manifest: Mapping, repeat: int) -> Mapping[str, int | None]:
    """The group-to-fold map of one repeat, named if the repeat does not exist."""
    assignments = fold_manifest["folds"].get(str(repeat))
    if assignments is None:
        raise ValueError(
            f"repeat {repeat} is not in the fold manifest, which records "
            f"{fold_manifest['repeats']} repeat(s)"
        )
    return assignments


def _require_fold_in_range(fold_manifest: Mapping, fold: int) -> None:
    if not 0 <= fold < fold_manifest["k"]:
        raise ValueError(
            f"fold {fold} is outside the {fold_manifest['k']} folds the "
            "manifest records"
        )


def _entries_of(fold_manifest: Mapping, group_id: str) -> list[dict]:
    """The training entries for one group, carrying the group they came from."""
    record = fold_manifest["groups"][group_id]
    return [
        {
            "path": path,
            "label": record["label"],
            "class": record["class"],
            "group": group_id,
        }
        for path in record["images"]
    ]


def _entries_for(fold_manifest: Mapping, group_ids: list[str]) -> list[dict]:
    entries: list[dict] = []
    for group_id in group_ids:
        entries.extend(_entries_of(fold_manifest, group_id))
    return entries


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
