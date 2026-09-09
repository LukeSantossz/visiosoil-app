"""How the fold manifest stores an image path (SPEC 0061).

One test per acceptance criterion, named after the criterion. None of them
reaches the ingested archive: the property under test is serialisation, and a
synthetic version written twice under two roots exercises it exactly, so these
run in CI rather than skipping there.

The move this module exists for is Windows to Linux. Two of the criteria are
about that move specifically — the separator and the re-rooting — and neither
can be observed on one machine unless the test writes under one root and reads
under another, which is what `two_roots` does.
"""

import json
import os
from pathlib import Path

import pytest

from src.dataset import (
    FOLD_MANIFEST_FILENAME,
    FOLD_SCHEMA_VERSION,
    REGENERATE_FOLDS_COMMAND,
    create_folds,
    load_folds,
)
from src.manifest import class_images, read_manifest, sample_ids_by_image
from tests.support import CLASSES, write_version

K = 5
REPEATS = 2
SEED = 42


def build(root, splits_dir, *, refused=None, class_images_override=None,
          sample_ids_override=None):
    """Draw the partition for the version at ``root`` into ``splits_dir``."""
    manifest = read_manifest(root, CLASSES)
    images = (
        class_images(manifest, CLASSES)
        if class_images_override is None
        else class_images_override
    )
    sample_ids = (
        sample_ids_by_image(manifest)
        if sample_ids_override is None
        else sample_ids_override
    )
    folds = create_folds(
        images,
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(splits_dir),
        dataset_root=str(root),
        sample_ids=sample_ids,
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        refused=refused,
    )
    return manifest, folds


def two_roots(tmp_path):
    """The same dataset version written under two different roots.

    Byte-identical content, so the two manifests carry one digest and a fold
    manifest drawn under the first is one the second is entitled to read.
    """
    return (
        write_version(tmp_path / "written-here"),
        write_version(tmp_path / "read-there"),
    )


def stored_paths(folds):
    """Every path a written fold manifest carries, in one list."""
    paths = [
        path for record in folds["groups"].values() for path in record["images"]
    ]
    paths += list(folds["refused"])
    return paths


def a_refusal(images):
    """One photograph refused, in the shape `drop_refused_photographs` returns.

    The message repeats the path, because that is how `_canonical_region`
    builds it, and repeating it here is what makes the message half of
    `the_fold_manifest_holds_no_absolute_path` a real assertion.
    """
    path = sorted(images[CLASSES[0]])[0]
    return path, {path: f"{path}: too_coarse_to_normalise: measured 0.14 mm/px"}


# --- the_fold_manifest_holds_no_absolute_path ------------------------------


def test_the_fold_manifest_holds_no_absolute_path(tmp_path):
    """No path in the written file is absolute — messages included.

    The refusal message is checked separately from the keys because it is a
    third place a path lives and the one a fix aimed at the other two would
    miss: it would still write the developer's home directory once per refused
    photograph.
    """
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    _, refused = a_refusal(class_images(manifest, CLASSES))
    _, folds = build(root, tmp_path / "splits", refused=refused)

    written = json.loads(
        (tmp_path / "splits" / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
    )

    for path in stored_paths(written):
        assert not os.path.isabs(path), f"{path} is absolute"
        assert ":" not in path, f"{path} carries a drive letter"

    for message in written["refused"].values():
        assert str(root) not in message, f"the refusal message names {root}"


# --- stored_paths_are_posix_separated --------------------------------------


def test_stored_paths_are_posix_separated(tmp_path):
    """No stored path carries a backslash.

    A backslash is a legal filename character on Linux, so a Windows-separated
    relative path does not resolve there — it becomes one long filename, and
    the failure is a missing file rather than a parse error.
    """
    root = write_version(tmp_path)
    _, folds = build(root, tmp_path / "splits")

    written = json.loads(
        (tmp_path / "splits" / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
    )

    for path in stored_paths(written):
        assert "\\" not in path, f"{path} is separated for one platform only"


# --- load_folds_re_roots_against_the_reading_root --------------------------


def test_load_folds_re_roots_against_the_reading_root(tmp_path):
    """Written under one root, read under a second, and the files are there."""
    written_root, reading_root = two_roots(tmp_path)
    splits_dir = tmp_path / "splits"
    build(written_root, splits_dir)

    loaded = load_folds(str(splits_dir), dataset_root=str(reading_root))

    for record in loaded["groups"].values():
        for path in record["images"]:
            assert os.path.isabs(path), f"{path} was not re-rooted"
            assert Path(path).is_relative_to(reading_root)
            assert Path(path).exists(), f"{path} does not resolve"


# --- re_rooted_paths_match_the_manifest_construction -----------------------


def test_re_rooted_paths_match_the_manifest_construction(tmp_path):
    """The re-rooted path is the string `class_images` builds, exactly.

    Not merely a path pointing at the same file. `photograph_scale` and
    `sample_ids_by_image` are dictionaries keyed by this string, so a path that
    resolves to the right file under a different spelling is a lookup miss and
    an unmeasured photograph.
    """
    written_root, reading_root = two_roots(tmp_path)
    splits_dir = tmp_path / "splits"
    build(written_root, splits_dir)

    loaded = load_folds(str(splits_dir), dataset_root=str(reading_root))
    reading_manifest = read_manifest(reading_root, CLASSES)
    expected = {
        path
        for paths in class_images(reading_manifest, CLASSES).values()
        for path in paths
    }

    re_rooted = {
        path for record in loaded["groups"].values() for path in record["images"]
    }
    assert re_rooted == expected


# --- the_partition_is_invariant_to_the_dataset_root ------------------------


def test_the_partition_is_invariant_to_the_dataset_root(tmp_path):
    """Two roots, one partition. Relativising cannot move a group.

    Grouping reads `sample_ids`, which is keyed by the absolute path, so this
    is the property that fails if the paths are relativised before the folds
    are drawn instead of after.

    Compared over the written files rather than the returned dicts. The return
    is re-rooted back to absolute so no caller has to know which side of the
    boundary it is on, which necessarily makes two returns differ by their two
    roots; the files are what the criterion is about, and there the stored paths
    are identical too, so this compares more than "paths aside" and not less.
    """
    first_root, second_root = two_roots(tmp_path)
    build(first_root, tmp_path / "first-splits")
    build(second_root, tmp_path / "second-splits")

    first, second = (
        json.loads(
            (tmp_path / name / FOLD_MANIFEST_FILENAME).read_text(encoding="utf-8")
        )
        for name in ("first-splits", "second-splits")
    )

    assert first["folds"] == second["folds"]
    assert first["counts"] == second["counts"]
    assert first["groups"] == second["groups"]


# --- a_path_outside_the_dataset_root_is_refused_by_name --------------------


def test_a_path_outside_the_dataset_root_is_refused_by_name(tmp_path):
    """An image that is not under the root is named, not silently prefixed.

    `Path.relative_to` raises a bare ValueError that names neither operand
    usefully, and `os.path.relpath` would happily return a `..`-prefixed path
    that resolves to nothing once the manifest moves.
    """
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    images = class_images(manifest, CLASSES)
    sample_ids = dict(sample_ids_by_image(manifest))

    stray = str(tmp_path / "elsewhere" / "stray.jpg")
    images[CLASSES[0]] = sorted(images[CLASSES[0]] + [stray])
    sample_ids[stray] = "stray-sample"

    with pytest.raises(ValueError) as error:
        build(
            root,
            tmp_path / "splits",
            class_images_override=images,
            sample_ids_override=sample_ids,
        )

    message = str(error.value)
    assert stray in message
    assert str(root) in message


# --- a_version_two_fold_manifest_is_refused_by_name ------------------------


def test_a_version_two_fold_manifest_is_refused_by_name(tmp_path):
    """A schema-2 file is refused by that number, and is not re-rooted.

    Its paths are absolute and the file does not record the root they were
    written under, so there is nothing to re-root them against.
    """
    root = write_version(tmp_path)
    splits_dir = tmp_path / "splits"
    build(root, splits_dir)

    path = splits_dir / FOLD_MANIFEST_FILENAME
    stale = json.loads(path.read_text(encoding="utf-8"))
    stale["schema_version"] = 2
    path.write_text(json.dumps(stale), encoding="utf-8")

    with pytest.raises(ValueError) as error:
        load_folds(str(splits_dir), dataset_root=str(root))

    message = str(error.value)
    assert "schema_version 2" in message
    assert str(FOLD_SCHEMA_VERSION) in message
    assert REGENERATE_FOLDS_COMMAND in message


# --- refused_photographs_survive_the_round_trip ----------------------------


def test_refused_photographs_survive_the_round_trip(tmp_path):
    """A refused photograph is stored relative and read back absolute.

    The refusal record is what keeps the manifest from being eleven
    photographs short of the version it names, so it has to make the move the
    groups make.
    """
    written_root, reading_root = two_roots(tmp_path)
    manifest = read_manifest(written_root, CLASSES)
    refused_path, refused = a_refusal(class_images(manifest, CLASSES))
    splits_dir = tmp_path / "splits"
    build(written_root, splits_dir, refused=refused)

    loaded = load_folds(str(splits_dir), dataset_root=str(reading_root))

    expected = str(reading_root / Path(refused_path).relative_to(written_root))
    assert list(loaded["refused"]) == [expected]
    assert "too_coarse_to_normalise" in loaded["refused"][expected]
