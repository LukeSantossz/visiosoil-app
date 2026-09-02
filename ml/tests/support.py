"""Builders for synthetic dataset versions, shared by the SPEC 0033 tests.

Not a test module. It exists so the manifest, split, and CLI suites describe one
dataset layout rather than three that can drift apart.
"""

import importlib.util
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

#: TensorFlow is pinned to Python 3.12 in `ml/requirements.txt` and has no wheel
#: for every interpreter this repository is developed on. A test that needs it
#: skips rather than failing, so the suite still reports on what it did check;
#: CI installs the pinned stack and runs every one of them.
requires_tensorflow = pytest.mark.skipif(
    importlib.util.find_spec("tensorflow") is None,
    reason="TensorFlow is not installed; CI runs these on Python 3.12",
)

#: The five Embrapa groups the delivered archive contains — the vocabulary a
#: manifest row may use, and what a fixture manifest is built from.
#:
#: Not the model's class list. Since SPEC 0046 `ml/config.yaml` declares four,
#: and these two are different questions: this is what the archive holds, that
#: is what the model emits. Mirrors `src.manifest.ARCHIVE_CLASSES`, and
#: `test_manifest.py` asserts the two agree so a fixture cannot drift from the
#: contract it is meant to exercise.
CLASSES = ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"]

MANIFEST_COLUMNS = (
    "sample_id",
    "texture_class",
    "image",
    "setting",
    "site",
    "device",
    "captured_at",
)

#: Nothing that only checks the manifest against the directory decodes an image,
#: so a marker byte string is enough to make the file exist.
PLACEHOLDER_IMAGE_BYTES = b"dataset fixture image"

#: Eight paired samples per class. Both stratified cuts then hold at least one
#: group of every class, which is what scikit-learn requires of each side.
SAMPLES_PER_CLASS = 8

#: Above the 512 px effective-resolution floor, so a generated image never picks
#: up a resolution failure it was not testing for.
FIXTURE_SIDE_PX = 600

#: Uniform noise of this amplitude gives a luma standard deviation near 27,
#: clearing the contrast floor of 20. Luma is a weighted sum of the three
#: channels, which shrinks the spread by a factor of about 0.67, so a smaller
#: amplitude picks up a contrast advisory.
NOISE_AMPLITUDE = 70.0


def noise_image(side=FIXTURE_SIDE_PX, means=(120, 120, 120), amplitude=NOISE_AMPLITUDE, seed=7):
    """A textured image with the given per-channel means."""
    generator = np.random.default_rng(seed)
    noise = generator.uniform(-amplitude, amplitude, size=(side, side, 3))
    pixels = np.clip(noise + np.asarray(means, dtype=np.float64), 0.0, 255.0)
    return Image.fromarray(pixels.astype(np.uint8), mode="RGB")


def flat_image(side=FIXTURE_SIDE_PX, level=128):
    """A featureless image: zero Laplacian variance, so blur blocks it."""
    return Image.fromarray(np.full((side, side, 3), level, dtype=np.uint8), mode="RGB")


def write_manifest_rows(root, rows):
    """Write ``rows`` as a collector-authored manifest at ``root``."""
    lines = [",".join(MANIFEST_COLUMNS)]
    lines += [
        ",".join(str(row[column]) for column in MANIFEST_COLUMNS) for row in rows
    ]
    (root / "manifest.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_version(
    tmp_path, extra_photographs=0, version="v1", samples_per_class=SAMPLES_PER_CLASS
):
    """Write a full manifest-backed dataset version and return its root.

    Every sample is paired across both settings, so the version satisfies the
    protocol as written and a test that wants a gap has to create one.
    """
    root = tmp_path / "datasets" / version
    (root / "images").mkdir(parents=True)
    rows = []

    def add(sample_id, texture_class, suffix, setting, site):
        relative = "images/{}_{}.jpg".format(sample_id, suffix)
        (root / relative).write_bytes(PLACEHOLDER_IMAGE_BYTES)
        rows.append(
            {
                "sample_id": sample_id,
                "texture_class": texture_class,
                "image": relative,
                "setting": setting,
                "site": site,
                "device": "Pixel 8",
                "captured_at": "2026-08-12",
            }
        )

    for texture_class in CLASSES:
        prefix = texture_class.replace(" ", "_")
        for index in range(samples_per_class):
            sample_id = "{}-{}".format(prefix, index)
            site = "Fazenda {}".format(index % 2)
            add(sample_id, texture_class, "dish", "dish", site)
            add(sample_id, texture_class, "paper", "paper", site)

    for extra in range(extra_photographs):
        add("Arenosa-0", "Arenosa", "dish{}".format(extra + 2), "dish", "Fazenda 0")

    write_manifest_rows(root, rows)
    return root


def write_image_version(tmp_path, images, version="v1"):
    """Write a version whose images are real files, for admission tests.

    ``images`` maps a sample id to ``(setting, PIL image or raw bytes)`` pairs.
    """
    root = tmp_path / "datasets" / version
    (root / "images").mkdir(parents=True)
    rows = []

    for sample_id, entries in images.items():
        for setting, content in entries:
            relative = "images/{}_{}.png".format(sample_id, setting)
            target = root / relative
            if isinstance(content, bytes):
                target.write_bytes(content)
            else:
                content.save(target)
            rows.append(
                {
                    "sample_id": sample_id,
                    "texture_class": "Arenosa",
                    "image": relative,
                    "setting": setting,
                    "site": "Fazenda Um",
                    "device": "Pixel 8",
                    "captured_at": "2026-08-12",
                }
            )

    write_manifest_rows(root, rows)
    return root


#: The ingested archive, which is git-ignored (ADR 0019) and therefore absent in
#: CI. Tests that read it skip rather than fail, so a criterion asserted over the
#: real data is checked wherever the data exists and never blocks a machine that
#: has none.
REAL_DATASET_ROOT = (
    Path(__file__).resolve().parents[1] / "data" / "datasets" / "v1"
)

def configured_classes():
    """The classes the model emits, read from `ml/config.yaml` as production does.

    This was a literal, `V1_EVALUATION_CLASSES`, and it was a legitimate second
    list while the config declared five and the protocol evaluated four. SPEC
    0046 made those the same four, at which point the literal was an unasserted
    duplicate of `cfg["classes"]` — a copy that could drift from the file the
    training actually reads. SPEC 0048 removes it.

    The four are still pinned to a literal, once, by
    `test_config_declares_four_classes_without_siltosa`.
    """
    from src.config import load_config

    return list(load_config()["classes"])


def real_manifest_or_skip(classes=None):
    """Return the ingested v1 manifest, skipping the test when it is absent.

    Read against the archive's five classes, because `read_manifest` rejects a
    row whose class is not in the vocabulary it is given and the archive holds
    six Siltosa rows. Narrowing to the four classes the model emits is
    `class_images`' job, at the point the pool is built.
    """
    from src.manifest import read_manifest

    if not (REAL_DATASET_ROOT / "manifest.csv").exists():
        pytest.skip(
            f"no ingested dataset at {REAL_DATASET_ROOT}; it is git-ignored "
            "per ADR 0019 and absent in CI"
        )
    return read_manifest(REAL_DATASET_ROOT, classes or CLASSES)
