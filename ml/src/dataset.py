"""Dataset scanning, fold generation, tf.data pipeline, and class weights.

The evaluation protocol is repeated stratified group k-fold with nested
selection (ADR 0020, SPEC 0042): the unit is the physical sample group, every
splittable group is tested exactly once per repeat, and the choice made for an
outer fold is made on inner folds of that fold's own training side. There is no
single ``train``/``val``/``test`` partition here and no code path that produces
one.

What the pipeline yields is a **patch**, not a photograph (SPEC 0053). Each
photograph is resampled to the canonical millimetres per pixel the manifest was
measured against and cut into a grid of greyscale squares inside its dish, and
every one of those is an element. A photograph is still the unit of a
prediction — ``train.py`` averages its patches' distributions back into one —
and it is still the unit of a fold, because grouping is on ``sample_id`` and
patches never leave the photograph they were cut from.

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
import warnings
from collections import Counter
from pathlib import Path
from typing import TYPE_CHECKING, Collection, Mapping

import numpy as np
import sklearn
from PIL import Image
from sklearn.model_selection import StratifiedGroupKFold

if TYPE_CHECKING:  # Annotations only; the runtime import is in _tensorflow().
    import tensorflow as tf

from .manifest import (
    Manifest,
    FOLD_COMPOSITION_AXES,
    IMAGE_SUFFIXES,
    check_class_coverage,
    check_scale_columns,
    class_images as manifest_class_images,
    dataset_root,
    format_composition,
    manifest_digest,
    manifest_path,
    ARCHIVE_CLASSES,
    read_manifest,
    read_manifest_or_none,
    sample_ids_by_image,
    split_composition,
    train_only_sample_ids,
    verify_split_digest,
)
from .patches import (
    PatchGeometry,
    PatchRefusal,
    cut_patches,
    patch_geometry,
    resample_to_canonical,
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
                # Verifying with a different decoder than training uses is
                # worse than not verifying at all: it reports success for files
                # that will fail mid-epoch. Pillow was used here first and
                # reads `.webp`, which `scan_dataset` admits and
                # `tf.io.decode_image` cannot read, so every `.webp` in a
                # dataset passed verification and then broke training.
                #
                # SPEC 0053 moved training's own decode to Pillow, so this is
                # now the stricter of the two: `tf.io.decode_image` reads a
                # subset of what Pillow reads, and a file it rejects is refused
                # here even though the patch grid could have cut it. Strict in
                # the safe direction, and left alone rather than loosened,
                # because which decoder the dataset contract admits is a
                # decision of its own and not this spec's.
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


def library_versions() -> dict[str, str]:
    """The libraries whose version decides which groups land in which fold.

    `StratifiedGroupKFold` is a greedy balancing heuristic, not a specification,
    and it has changed between scikit-learn releases: 1.5.2 and 1.8.0 partition
    the same 40 groups differently under the same seed. The seed alone therefore
    does not reproduce a fold set, and a manifest that records only the seed
    promises more than it can deliver.
    """
    return {"scikit_learn": sklearn.__version__, "numpy": np.__version__}


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
    refused: Mapping[str, str] | None = None,
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
        refused: Photographs the patch grid cannot cut, path to the reason,
            recorded so the manifest says which images left and why rather than
            being one short of the version it names.

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
        # Recorded beside the seeds because it is the other half of what
        # reproduces this partition. See `library_versions`.
        "library_versions": library_versions(),
        "train_only_samples": sorted(set(train_only_samples or ())),
        # Recorded rather than merely absent. A photograph the patch grid
        # refuses is one the model never sees, and a manifest that listed 221
        # photographs for a version of 221 while training on 210 would be
        # describing a run that did not happen.
        "refused": dict(refused or {}),
        "groups": groups,
        "folds": assignments,
        "counts": {
            "groups": len(groups),
            "splittable_groups": len(splittable),
            "train_only_groups": len(groups) - len(splittable),
            "photographs": sum(len(r["images"]) for r in groups.values()),
            "refused_photographs": len(refused or {}),
        },
    }

    destination = Path(splits_dir)
    destination.mkdir(parents=True, exist_ok=True)
    with open(destination / FOLD_MANIFEST_FILENAME, "w") as handle:
        json.dump(fold_manifest, handle, indent=2)

    return fold_manifest


def create_folds_for_config(
    cfg: Mapping, splits_dir: str, manifest: Manifest | None = None
) -> dict:
    """Generate the fold manifest for ``cfg``, from the dataset's own manifest.

    The manifest is required rather than preferred. The folder scan that
    predates it cannot say which physical sample a photograph belongs to, and
    grouping is what every guarantee in this protocol rests on: without the
    declared ids the group would be inferred from a filename pattern, and a
    pattern that happens to fit is the worst case, because nothing reports that
    it was used.

    Args:
        cfg: The configuration, which names the version, the classes and the
            evaluation parameters.
        splits_dir: Where the fold manifest is written.
        manifest: The parsed manifest, for a caller that already holds one — or
            that reads a version the config does not name, which is what
            `validate_dataset.py --root` does. Given, no version is re-read.
            **The only supported way to partition a version other than the
            configured one**: the filtering, the restriction and the refusal
            record below all live here, and a caller that reached for
            `create_folds` to get a different root would silently get none of
            them.
    """
    data = cfg["data"]
    evaluation = cfg["evaluation"]
    if manifest is None:
        root = dataset_root(data["datasets_dir"], data["dataset_version"])
        # The archive's vocabulary and not the model's: the manifest holds every
        # class SPEC 0040 ingested, and reading it against the four classes the
        # model emits would reject the Siltosa rows ADR 0016 keeps in the version
        # while excluding from the first model.
        manifest = read_manifest_or_none(root, ARCHIVE_CLASSES)

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

    images = manifest_class_images(manifest, cfg["classes"])
    # Refused before the partition rather than after it. A photograph the patch
    # grid cannot cut is one no fold can score, so leaving it in would stratify
    # over images that never reach the model and put a group's whole weight on
    # photographs that do not exist for training. SPEC 0053's eleven coarse
    # archive photographs leave here and nowhere else.
    _, refused = drop_refused_photographs(
        [{"path": path} for paths in images.values() for path in paths],
        cfg,
        scale=photograph_scale_of(manifest),
    )
    if refused:
        print(
            f"{len(refused)} photograph(s) are refused by the patch grid and are "
            f"in no fold; the first is {next(iter(refused.values()))}"
        )
        images = {
            texture_class: [path for path in paths if path not in refused]
            for texture_class, paths in images.items()
        }

    restricted = train_only_sample_ids(manifest)
    if restricted:
        print(
            f"{len(restricted)} sample group(s) are restricted to training by "
            f"their source group; they will be in every fold's training side "
            f"and in no fold's test side."
        )

    return create_folds(
        images,
        k=evaluation["k"],
        repeats=evaluation["repeats"],
        seed=data["seed"],
        splits_dir=splits_dir,
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        train_only_samples=restricted,
        refused=refused,
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

    _warn_on_a_library_mismatch(path, fold_manifest)

    if manifest_digest is not None:
        verify_split_digest(fold_manifest, manifest_digest)

    return fold_manifest


def load_folds_for_config(cfg: Mapping, splits_dir: str) -> dict:
    """Load the fold manifest and refuse one that does not describe this run.

    Every production entry point goes through here rather than through
    :func:`load_folds` directly, because the two checks below are worthless if
    a caller can skip them — and for one release every caller did.

    Two things are checked, and they fail differently:

    - **Provenance.** The digest of the dataset's own `manifest.csv` must match
      the one the folds were drawn from, or the run is scoring photographs that
      are not the ones the partition was built over.
    - **Agreement.** The class list, seed, k and repeat count must match the
      active configuration. The class list is the sharp one: it is the model's
      output order, so a fold manifest drawn under five classes and used under
      four does not fail — it relabels every result, silently.

    An unreadable dataset manifest is refused rather than skipped. "Could not
    be checked" and "checked and matched" are different facts, and treating the
    first as the second is the defect this function exists to close.
    """
    data = cfg["data"]
    root = dataset_root(data["datasets_dir"], data["dataset_version"])
    path = manifest_path(root)
    if not path.exists():
        raise FileNotFoundError(
            f"no manifest at {path}, so the folds in {splits_dir} cannot be "
            f"checked against the dataset they claim. Check out the dataset "
            f"version they were drawn from, or regenerate them with: "
            f"{REGENERATE_FOLDS_COMMAND}"
        )

    fold_manifest = load_folds(splits_dir, manifest_digest=manifest_digest(root))
    _require_config_agreement(fold_manifest, cfg, splits_dir)
    return fold_manifest


def _require_config_agreement(
    fold_manifest: Mapping, cfg: Mapping, splits_dir: str
) -> None:
    """Refuse a fold manifest the active configuration no longer describes.

    Every disagreement is reported in one message, because the reader is
    editing a configuration file and one list is the difference between one
    correction and four.
    """
    expected = (
        ("classes", fold_manifest["classes"], list(cfg["classes"])),
        ("data.seed", fold_manifest["seed"], cfg["data"]["seed"]),
        ("evaluation.k", fold_manifest["k"], cfg["evaluation"]["k"]),
        (
            "evaluation.repeats",
            fold_manifest["repeats"],
            cfg["evaluation"]["repeats"],
        ),
    )
    disagreements = [
        f"  - {name}: the folds were drawn under {recorded!r}, the config says "
        f"{configured!r}"
        for name, recorded, configured in expected
        if recorded != configured
    ]
    if disagreements:
        raise ValueError(
            f"{Path(splits_dir) / FOLD_MANIFEST_FILENAME} does not describe this "
            f"run:\n"
            + "\n".join(disagreements)
            + f"\nThe class list is the model's output order, so using folds "
            f"drawn under another one relabels every result rather than "
            f"failing. Regenerate them with: {REGENERATE_FOLDS_COMMAND}"
        )


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

    The generator's own balancing is approximate and version-dependent, so its
    result is rebalanced deterministically before it is used. That is what makes
    "every class in every fold's test side" a property of the code rather than
    of the scikit-learn release that happens to be installed.
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

    labels_by_group = {
        group_id: int(label) for group_id, label in zip(group_ids, labels)
    }
    assignment = rebalance_fold_assignment(assignment, labels_by_group, splits)
    _require_balanced_classes(assignment, labels_by_group, splits)
    return assignment


def rebalance_fold_assignment(
    assignment: Mapping[str, int], labels_by_group: Mapping[str, int], splits: int
) -> dict[str, int]:
    """Even out each class across the folds, moving whole groups and nothing else.

    `StratifiedGroupKFold` minimises the spread of the whole class-count matrix
    greedily, which balances well and guarantees nothing: a class can miss a
    fold's test side entirely, and scikit-learn 1.5.2 does exactly that on a
    40-group fixture where 1.8.0 does not. A fold that tests no group of a class
    contributes an undefined per-class F1 to a macro average, silently, so the
    property has to be established rather than assumed.

    The repair takes one group at a time from the fold holding most of a class
    and gives it to the fold holding fewest, until no two folds differ by more
    than one. That terminates — the sum of squared counts strictly falls by at
    least two on every move — and it leaves every class with either
    ``floor(n / k)`` or ``ceil(n / k)`` groups per fold. Where a class has at
    least ``k`` groups, which :func:`create_folds` requires, the floor is at
    least one and every class therefore reaches every fold.

    Every choice is by lowest index and then by lowest group id, so the result
    is a function of the input alone; the seed still decides the assignment the
    repair starts from, and an already balanced assignment is returned unchanged.

    Args:
        assignment: Group id to fold index.
        labels_by_group: Group id to class label.
        splits: Number of folds.

    Returns:
        A new assignment, balanced per class.
    """
    balanced = dict(assignment)
    for label in sorted(set(labels_by_group.values())):
        members = sorted(
            group_id for group_id in balanced if labels_by_group[group_id] == label
        )
        while True:
            held: dict[int, list[str]] = {fold: [] for fold in range(splits)}
            for group_id in members:
                held[balanced[group_id]].append(group_id)
            counts = {fold: len(group_ids) for fold, group_ids in held.items()}
            fullest = min(counts, key=lambda fold: (-counts[fold], fold))
            emptiest = min(counts, key=lambda fold: (counts[fold], fold))
            if counts[fullest] - counts[emptiest] <= 1:
                break
            balanced[sorted(held[fullest])[0]] = emptiest
    return balanced


def _require_balanced_classes(
    assignment: Mapping[str, int], labels_by_group: Mapping[str, int], splits: int
) -> None:
    """Post-condition of :func:`rebalance_fold_assignment`.

    It cannot fire while the repair is correct, and it is here because the thing
    it protects — a macro average over a class no fold tested — fails silently
    at report time rather than loudly at generation time. A future change to the
    generator that skipped the repair would be caught here instead of producing
    a number nobody could interpret.
    """
    for label in sorted(set(labels_by_group.values())):
        counts = Counter(
            assignment[group_id]
            for group_id in assignment
            if labels_by_group[group_id] == label
        )
        held = [counts.get(fold, 0) for fold in range(splits)]
        if max(held) - min(held) > 1:
            raise ValueError(
                f"class label {label} is spread {held} over {splits} fold(s), "
                "which no balanced assignment allows. The fold generator did "
                "not rebalance; a fold missing a class makes its macro-F1 "
                "undefined for that class"
            )


def _warn_on_a_library_mismatch(path: Path, fold_manifest: Mapping) -> None:
    """Say when a fold manifest was generated under another stack.

    A warning and not a refusal, because loading reads the stored assignment and
    never recomputes it: the folds in the file are the folds that were used,
    whatever version reads them. Refusing would make a valid partition unusable
    after a dependency bump, and the only remedy — regenerating — would move the
    folds, which is the one thing a reader comparing against an existing result
    must not do without noticing.
    """
    recorded = fold_manifest.get("library_versions")
    current = library_versions()
    if recorded is None:
        warnings.warn(
            f"{path} records no library versions, so the stack that generated "
            f"its folds is unknown; it cannot be shown to match this one "
            f"({current}). Regenerate it to record them",
            UserWarning,
            stacklevel=3,
        )
        return
    if recorded != current:
        warnings.warn(
            f"{path} was generated under {recorded} and is being read under "
            f"{current}. The stored fold assignment is used as it stands, but "
            "regenerating it here would produce different folds: "
            "StratifiedGroupKFold partitions differently across scikit-learn "
            "versions",
            UserWarning,
            stacklevel=3,
        )


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


#: Every photograph's dish measurement, keyed by the manifest it was read from.
#: An arm builds a dataset and asks for its patch counts on every side of every
#: fold of every repeat, so at k = 5 and R = 5 this is asked for well over a
#: hundred times — of a file that cannot have changed in between. Keyed by the
#: digest as well as the root, so a second manifest — another version, or a
#: test's — is a new entry rather than a stale hit.
_SCALE_BY_MANIFEST: dict[tuple[str, str], dict[str, dict[str, float]]] = {}


def photograph_scale(cfg: Mapping) -> dict[str, dict[str, float]]:
    """What the dish-rim reader measured for each photograph of this version.

    Keyed by the resolved image path, which is the string
    :func:`manifest.class_images` puts in a fold manifest's entries, so a caller
    joins on the path it already holds instead of re-deriving one.

    Returns:
        Path to the four :data:`manifest.SCALE_COLUMNS` values.

    Raises:
        FileNotFoundError: If the dataset version holds no manifest.
        ValueError: If any row has not been measured. Every unmeasured row is
            named in one message, and the message names the command that fixes
            all of them, because the remedy is one run of ``measure_scale.py``
            over the version rather than a repair per photograph.
    """
    data = cfg["data"]
    root = dataset_root(data["datasets_dir"], data["dataset_version"])
    path = manifest_path(root)
    if not path.exists():
        raise FileNotFoundError(
            f"no manifest at {path}. The patch grid is cut around the dish the "
            f"manifest measured, so a version without one cannot be trained on"
        )

    key = (str(root), manifest_digest(root))
    memoised = _SCALE_BY_MANIFEST.get(key)
    if memoised is not None:
        return memoised

    # The archive's vocabulary and not the model's, for the reason
    # `create_folds_for_config` gives: the manifest holds the Siltosa rows
    # ADR 0016 keeps in the version and excludes from the first model.
    measured = photograph_scale_of(read_manifest(root, ARCHIVE_CLASSES))
    _SCALE_BY_MANIFEST[key] = measured
    return measured


def photograph_scale_of(manifest: Manifest) -> dict[str, dict[str, float]]:
    """The same mapping, for a caller that already holds the manifest.

    `validate_dataset.py --root` reads a version the config does not name, so
    reaching the measurement through the config would hand it the configured
    version's scales for another version's photographs: every path a miss, or
    worse, a hit on a path that happens to match.

    Raises:
        ValueError: If any row has not been measured.
    """
    unmeasured = check_scale_columns(manifest)
    if unmeasured:
        raise ValueError(
            f"{len(unmeasured)} photograph(s) in {manifest.version} carry no "
            f"measured scale, so no patch can be cut from them:\n  - "
            + "\n  - ".join(unmeasured)
        )

    return {
        # Exactly the join `class_images` performs. Anything else here — a
        # `resolve()`, a `str(Path(...))` round trip — produces a key an entry's
        # `path` does not match, and the miss would look like a missing row.
        str(manifest.root / row.image): dict(row.scale)
        for row in manifest.rows
    }


def photograph_patch_counts(split_entries: list[dict], cfg: Mapping) -> list[int]:
    """How many patches each entry yields, in entry order.

    Arithmetic over the measured dish and nothing else: it opens no image.
    ``train.py`` needs these to slice a model's patch-level output back into one
    distribution per photograph (SPEC 0053), and paying a decode of the whole
    fold for a number the manifest already implies would put a second pass over
    the data into every epoch's bookkeeping.

    The count agrees with what :func:`build_dataset` yields for the same
    entries, including when it refuses: both reach the geometry through
    :func:`_patch_geometry_of`, so a photograph refused here is refused there.

    Raises:
        ValueError: If a photograph is coarser than the canonical, if its dish
            is too small for the patch floor, or if it is not in the manifest.
    """
    scale = photograph_scale(cfg)
    return [
        _patch_geometry_of(entry["path"], _measurement_of(entry, scale), cfg).count
        for entry in split_entries
    ]


def drop_refused_photographs(
    split_entries: list[dict],
    cfg: Mapping,
    scale: Mapping[str, Mapping[str, float]] | None = None,
) -> tuple[list[dict], dict[str, str]]:
    """The entries the patch grid accepts, and why it refuses the rest.

    The one place a refused photograph may leave a split. :func:`build_dataset`
    and :func:`photograph_patch_counts` raise instead, and deliberately: a
    pipeline that skipped a photograph on its own would shorten an epoch by an
    amount nothing records, and SPEC 0053's eleven archive photographs coarser
    than the canonical would leave training with nobody told. Dropping them is a
    decision the caller assembling a training side takes, out loud, with the
    refusals in hand to report.

    A photograph the manifest does not hold is **not** refused here. That is a
    fold manifest and a dataset version disagreeing about which images exist,
    which no filter should absorb.

    Args:
        split_entries: The entries to filter.
        cfg: The configuration, read for the canonical scale and the geometry.
        scale: The measurement, for a caller partitioning a version the config
            does not name. Omitted, it is read from the configured version.

    Returns:
        The accepted entries in their original order, and a mapping of each
        refused entry's path to the refusal, which names a
        :class:`patches.PatchRefusal`.
    """
    scale = photograph_scale(cfg) if scale is None else scale
    accepted: list[dict] = []
    refused: dict[str, str] = {}
    for entry in split_entries:
        measurement = _measurement_of(entry, scale)
        try:
            _patch_geometry_of(entry["path"], measurement, cfg)
        except ValueError as refusal:
            refused[entry["path"]] = str(refusal)
        else:
            accepted.append(entry)
    return accepted, refused


def _measurement_of(
    entry: Mapping, scale: Mapping[str, Mapping[str, float]]
) -> Mapping[str, float]:
    """The dish measurement of one entry's photograph."""
    measurement = scale.get(entry["path"])
    if measurement is None:
        raise ValueError(
            f"{entry['path']} is not in the dataset manifest the scale was read "
            f"from, so no dish was measured for it. The fold manifest and the "
            f"dataset version disagree about which photographs exist; "
            f"regenerate the folds with: {REGENERATE_FOLDS_COMMAND}"
        )
    return measurement


def _canonical_region(
    path: str, measurement: Mapping[str, float], cfg: Mapping
) -> tuple[float, float, float]:
    """The dish's centre and diameter after the resample, in canonical pixels.

    The manifest measures the dish in the photograph's own pixels and
    `resample_to_canonical` scales the photograph by `measured / canonical`, so
    the circle has to travel by the same ratio. A grid cut around an unscaled
    centre still produces patches — of the wrong soil, or of the bench — which
    is why this is arithmetic in one place rather than at each call site.

    The too-coarse refusal is repeated here rather than left to
    `resample_to_canonical` so that :func:`photograph_patch_counts` reaches the
    same verdict as :func:`build_dataset` without opening a file. It is one
    comparison, and the name it raises comes from the enum that owns it.

    Returns:
        ``(centre_y, centre_x, diameter)``, all in canonical pixels.
    """
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    measured = measurement["mm_per_px"]
    if measured > canonical:
        raise ValueError(
            f"{path}: {PatchRefusal.TOO_COARSE.value}: the photograph measures "
            f"{measured:.4f} mm/px and the canonical is {canonical:.4f}, so "
            f"reaching it would upsample by {measured / canonical:.2f}x"
        )

    ratio = measured / canonical
    return (
        measurement["disc_centre_y_px"] * ratio,
        measurement["disc_centre_x_px"] * ratio,
        measurement["disc_diameter_px"] * ratio,
    )


def _patch_geometry_of(
    path: str, measurement: Mapping[str, float], cfg: Mapping
) -> PatchGeometry:
    """The grid one photograph carries, named by the photograph when refused."""
    _, _, diameter = _canonical_region(path, measurement, cfg)
    try:
        return patch_geometry(
            region_diameter_px=diameter,
            input_size=cfg["data"]["image_size"],
            canonical_mm_per_px=cfg["preprocessing"]["canonical_mm_per_px"],
            min_patches=cfg["preprocessing"]["min_patches"],
            stride_fraction=cfg["preprocessing"]["patch_stride_fraction"],
        )
    except ValueError as refusal:
        # `patch_geometry` knows the geometry and not the file. An operator
        # reading a refusal over 221 photographs needs to be told which one.
        raise ValueError(f"{path}: {refusal}") from refusal


def _photograph_patches(
    entry: Mapping, measurement: Mapping[str, float], cfg: Mapping
) -> list[np.ndarray]:
    """Decode one photograph once and cut its whole grid from it.

    Resample first, cut second. The other order would cut a grid in the
    photograph's own pixels — a patch covering 5.5 mm of soil in the finest
    archive photograph and 21 mm in the coarsest — which is the mixture ADR 0018
    exists to remove.
    """
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    centre_y, centre_x, diameter = _canonical_region(entry["path"], measurement, cfg)

    with Image.open(entry["path"]) as handle:
        # `convert` reads the file, so the decode happens while the handle is
        # open and nothing downstream depends on it staying open.
        photograph = handle.convert("RGB")
    resampled, _ = resample_to_canonical(
        photograph, measurement["mm_per_px"], canonical
    )

    try:
        return cut_patches(
            resampled,
            centre_y=centre_y,
            centre_x=centre_x,
            region_diameter_px=diameter,
            input_size=cfg["data"]["image_size"],
            canonical_mm_per_px=canonical,
            min_patches=cfg["preprocessing"]["min_patches"],
            stride_fraction=cfg["preprocessing"]["patch_stride_fraction"],
        )
    except ValueError as refusal:
        raise ValueError(f"{entry['path']}: {refusal}") from refusal


def _patch_stream(split_entries: list[dict], cfg: Mapping) -> tf.data.Dataset:
    """One **uint8** patch per element, in entry order, decoding once each.

    Cut in Python rather than in the graph: the grid needs Pillow's resample and
    a circle the manifest measured, neither of which is a tensor operation, and
    `from_generator` keeps one photograph's decode paying for all of its patches
    instead of re-reading the file per patch.
    """
    tf = _tensorflow()
    scale = photograph_scale(cfg)
    input_size = cfg["data"]["image_size"]
    class_count = len(cfg["classes"])

    def patches():
        for entry in split_entries:
            label = np.zeros(class_count, dtype=np.float32)
            label[entry["label"]] = 1.0
            measurement = _measurement_of(entry, scale)
            for patch in _photograph_patches(entry, measurement, cfg):
                yield patch, label

    return tf.data.Dataset.from_generator(
        patches,
        output_signature=(
            tf.TensorSpec(shape=(input_size, input_size, 3), dtype=tf.uint8),
            tf.TensorSpec(shape=(class_count,), dtype=tf.float32),
        ),
    )


def build_dataset(
    split_entries: list[dict],
    cfg: dict,
    augment: bool = False,
    shuffle: bool = False,
) -> tf.data.Dataset:
    """Build a tf.data.Dataset of patches from split manifest entries.

    One tensor per **patch** and not per photograph (SPEC 0053): each entry's
    photograph is resampled to the canonical scale and cut into the grid
    :func:`photograph_patch_counts` reports for it. A photograph is still the
    unit of a prediction — ``train.py`` averages a photograph's patch
    distributions back into one — so grouping, folds and class weights are
    untouched by this.

    Args:
        split_entries: List of {"path", "label", "class"} dicts.
        cfg: Configuration dictionary.
        augment: Whether to apply augmentation.
        shuffle: Whether to shuffle the dataset.

    Returns:
        Batched tf.data.Dataset yielding (patches, one_hot_labels).

    Raises:
        ValueError: If any entry's photograph is refused by the patch grid.
            Refusals are raised here, before a tensor exists, rather than from
            inside the generator where tf.data would surface them mid-epoch
            wrapped in an operation error. See :func:`drop_refused_photographs`
            for the one place a refused photograph may be dropped instead.
    """
    from .preprocess import build_augmentation_layer, normalize_mobilenet_v2

    tf = _tensorflow()

    # Computed whether or not the shuffle needs it, because it is also the gate:
    # it reaches every entry's geometry without decoding anything, so a coarse
    # photograph fails the build in a second rather than partway through epoch
    # one. It is the same count `train.py` slices predictions by.
    counts = photograph_patch_counts(split_entries, cfg)

    normalization = cfg["preprocessing"]["normalization"]
    if normalization != "mobilenet_v2":
        # `preprocess.preprocess` is not on this path — it resizes, and a patch
        # is already `data.image_size` across, so resizing it would resample the
        # soil a second time at a scale nobody measured. Its normalization
        # contract still holds, refused by the same name rather than skipped.
        raise ValueError(f"Unknown normalization: {normalization}")

    ds = _patch_stream(split_entries, cfg)

    # Decode once per fit rather than once per epoch (SPEC 0050). Measured at
    # 5.47 s per epoch over one fold's 179 photographs, and it did not fall on
    # repeat, which is about nine hours of redundant decoding per arm at
    # k = 5, R = 5. The patch grid made that decode more expensive, not less:
    # it now carries a resample and 25 crops.
    #
    # The position is forced from both sides. It is **after** the decode and the
    # cut, which are deterministic, expensive, repeated, and a pure function of
    # the photograph and its measured scale. It is **before** the augmentation,
    # which must draw again every epoch: a cache below it would freeze one set
    # of augmented patches for the whole fit while the config still declared
    # augmentation.
    ds = ds.cache()

    # Shuffled **after** the cache, and not before it as this pipeline used to
    # be. `cache()` records the order of what passes through it, so a shuffle
    # upstream would have its first epoch's order replayed by every epoch after
    # — a shuffle that looks configured, appears to work in epoch one, and is
    # inert from epoch two.
    #
    # The buffer is sized in **patches**. Sizing it by photographs would shuffle
    # a twenty-fifth of an epoch: a buffer of size B can never emit an element
    # earlier than B - 1 positions before where it arrived, so whole
    # photographs would stay contiguous and the batches would be nearly sorted.
    if shuffle:
        ds = ds.shuffle(buffer_size=sum(counts), seed=cfg["data"]["seed"])

    # Normalised **after** the cache and the shuffle, which is why the stream
    # above is uint8. Both of those hold their contents in memory: a fold's
    # training side is roughly 4500 patches, so float32 is about 1.7 GB in the
    # cache and as much again in the buffer, against 340 MB each as uint8.
    ds = ds.map(
        lambda patch, label: (normalize_mobilenet_v2(patch), label),
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
