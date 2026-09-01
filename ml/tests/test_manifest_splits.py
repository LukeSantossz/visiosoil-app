"""Tests for folds generated from a manifest (SPEC 0033, revised by SPEC 0042).

Separate from ``test_dataset.py``, which covers the folder-scan path that
predates the manifest. What is asserted here is the manifest-backed contract:
grouping comes from the ``sample_id`` column rather than from a filename
pattern, and a fold manifest records which dataset version and which manifest it
was generated from.

SPEC 0042 replaced the single ``train``/``val``/``test`` partition with repeated
stratified group k-fold, so the same contract is now asserted against
``create_folds`` and ``load_folds``. The generator changed; what it has to
guarantee did not.
"""

import json
import subprocess
import sys
from pathlib import Path

import pytest

from src.dataset import FOLD_MANIFEST_FILENAME, create_folds, load_folds
from src.manifest import (
    class_images,
    manifest_digest,
    read_manifest,
    sample_ids_by_image,
)
from tests.support import CLASSES, SAMPLES_PER_CLASS, write_version

K = 5
REPEATS = 3


def generate(tmp_path, root, *, with_provenance=True):
    """Generate the fold manifest from the manifest at ``root``."""
    manifest = read_manifest(root, CLASSES)
    splits_dir = tmp_path / "splits"
    folds = create_folds(
        class_images(manifest, CLASSES),
        k=K,
        repeats=REPEATS,
        seed=42,
        splits_dir=str(splits_dir),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version if with_provenance else None,
        manifest_digest=manifest.digest if with_provenance else None,
    )
    return manifest, splits_dir, folds


def groups_holding(folds, stem_prefix):
    """Return the groups holding a sample's photographs, and how many rows."""
    holders = set()
    count = 0
    for group_id, record in folds["groups"].items():
        for path in record["images"]:
            if Path(path).name.startswith(stem_prefix):
                holders.add(group_id)
                count += 1
    return holders, count


def test_folds_group_by_sample_id(tmp_path):
    """Every photograph of one physical sample belongs to exactly one group."""
    root = write_version(tmp_path, extra_photographs=1)

    _, _, folds = generate(tmp_path, root)

    holders, count = groups_holding(folds, "Arenosa-0_")
    assert count == 3
    assert len(holders) == 1


def test_folds_group_on_the_column_not_the_filename(tmp_path):
    """Two files with unrelated names group together when the column says so."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    grouping = sample_ids_by_image(manifest)
    assert len(set(grouping.values())) == len(CLASSES) * SAMPLES_PER_CLASS

    _, _, folds = generate(tmp_path, root)

    holders, count = groups_holding(folds, "Media-3_")
    assert count == 2
    assert len(holders) == 1
    assert len(folds["groups"]) == len(CLASSES) * SAMPLES_PER_CLASS


def test_folds_record_the_dataset_version_and_manifest_hash(tmp_path):
    """A fold manifest carries the provenance that makes it checkable."""
    root = write_version(tmp_path)

    manifest, splits_dir, _ = generate(tmp_path, root)

    with open(splits_dir / FOLD_MANIFEST_FILENAME) as handle:
        written = json.load(handle)
    assert written["dataset_version"] == manifest.version == "v1"
    assert written["manifest_digest"] == manifest_digest(root)


def test_loading_a_fold_manifest_whose_hash_does_not_match_fails(tmp_path):
    """Folds generated before the manifest changed must not be reused."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root)

    with pytest.raises(ValueError, match="manifest_digest"):
        load_folds(str(splits_dir), manifest_digest="0" * 64)


def test_loading_a_fold_manifest_whose_hash_matches_succeeds(tmp_path):
    """The matching case loads, so the check is a guard rather than a wall."""
    root = write_version(tmp_path)
    manifest, splits_dir, _ = generate(tmp_path, root)

    loaded = load_folds(str(splits_dir), manifest_digest=manifest.digest)

    assert loaded["dataset_version"] == "v1"


def test_loading_a_fold_manifest_without_provenance_fails_when_a_hash_is_required(
    tmp_path,
):
    """A fold manifest carrying no digest cannot be shown to match anything."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root, with_provenance=False)

    with pytest.raises(ValueError, match="manifest_digest"):
        load_folds(str(splits_dir), manifest_digest=manifest_digest(root))


def test_loading_a_fold_manifest_without_a_required_hash_still_works(tmp_path):
    """A caller that passes no digest asks for no provenance check."""
    root = write_version(tmp_path)
    _, splits_dir, _ = generate(tmp_path, root, with_provenance=False)

    assert load_folds(str(splits_dir))["classes"] == CLASSES


def test_importing_dataset_does_not_load_tensorflow():
    """Validating a dataset must not require the training stack installed.

    The protocol is written so a collector can execute and check it without this
    terminal present, and ``scripts/validate_dataset.py`` imports this module.

    A subprocess is what makes this a real check: importing here would see
    whatever another test already loaded. ``stdin=DEVNULL`` is load-bearing on
    Windows, where pytest hands the test an stdin handle ``subprocess`` cannot
    duplicate — without it this fails intermittently with
    ``OSError: [WinError 6] invalid handle``, for a reason unrelated to its
    subject.
    """
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.dataset, sys; "
            "assert 'tensorflow' not in sys.modules, 'dataset imported tensorflow'",
        ],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr


def test_importing_the_reporting_layer_does_not_load_tensorflow():
    """Every criterion about what a result says has to be checkable without it.

    `src.evaluate` reads stored predictions and `src.crossval` reaches the
    training stack only inside `run_arm`, so the whole reporting layer imports
    clean. Without this the modules would drift back to a top-level import and
    the protocol's own tests would stop running anywhere but CI.
    """
    completed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import src.crossval, src.evaluate, src.stats, sys; "
            "assert 'tensorflow' not in sys.modules, 'reporting imported tensorflow'",
        ],
        cwd=Path(__file__).resolve().parents[1],
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr
