"""The frozen-encoder featuriser and the cache that makes the arm affordable.

Two things are asserted here and they fail in opposite ways. The **arithmetic**
— one row per patch, in patch order, over pixels scaled the way MobileNetV2's
weights were trained — fails silently: a patch handed to the backbone in [0, 1]
instead of [-1, 1] produces embeddings of exactly the right shape that mean
nothing, and no test that only counted rows would notice. The **cache** fails
loudly or not at all: it either serves the embedding the pixels imply or it
serves one from another dataset version, and the second is a result attributed
to data that did not produce it.

Almost everything here runs without TensorFlow, on a fake encoder injected into
the featuriser. That is not a convenience: the encoder is the one part of this
module that cannot be installed on every machine the suite runs on, and a cache
test that skipped wherever TensorFlow is absent would be a cache test that never
ran in CI's own reading of the criteria. The three tests that genuinely need the
backbone — its output width, its once-per-process construction, and one
end-to-end pass — are gated and say so.

The fixture works at its own canonical scale and its own patch size, borrowed
from `test_patch_dataset.py`: the grid is arithmetic, so a 16 px patch on a
48 px dish exercises every property a 160 px patch on a 697 px dish does.
"""

import json
import subprocess
import sys
import types
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

from src.arms.encoder import (
    CACHE_SCHEMA_VERSION,
    CACHE_SIDECAR_FILENAME,
    ENCODER_EMBEDDING_DIM,
    PREPROCESSING_CONVENTION,
    encoder_featuriser,
    encoder_probe_fold,
    feature_cache_directory,
    feature_cache_path,
    prepare_for_mobilenet_v2,
)
from src.dataset import _photograph_patches, photograph_scale
from src.manifest import ManifestRow, write_manifest
from tests.support import requires_tensorflow

#: The fixture's scales. Measured is half the canonical, so every photograph is
#: downsampled by two and a mistake in the ratio moves the grid visibly rather
#: than by a rounding error.
CANONICAL = 0.5
MEASURED = 0.25

#: A photograph, and the dish inside it, in the photograph's own pixels.
SIDE_PX = 200
CENTRE_PX = 100.0
DISC_DIAMETER_PX = 96.0

#: 16 px patches on the 48 px dish the resample leaves: the half-diagonal inset
#: is 11.3 px, which leaves 12.7 px of room at a stride of 8, so the grid is the
#: 3 x 3 the floor asks for.
INPUT_SIZE = 16
PATCHES_PER_PHOTOGRAPH = 9

#: The grid at the production patch size, for the tests that run the real
#: backbone. Measured at the canonical, so nothing is resampled: a 160 px patch
#: has a half-diagonal inset of 113.1 px, which leaves 116.9 px of room at a
#: stride of 80 px on a 460 px dish, so this grid is also the 3 x 3 floor.
FULL_SIDE_PX = 700
FULL_CENTRE_PX = 350.0
FULL_DISC_DIAMETER_PX = 460.0
FULL_INPUT_SIZE = 160

#: Soil levels far enough apart that a patch names the photograph it came from.
SOIL_LEVELS = (60, 110, 160)
TEXTURE_AMPLITUDE = 12.0

#: A dish this close to the left edge leaves the grid hanging off the
#: photograph, which is the refusal the featuriser must propagate rather than
#: absorb into a short feature matrix.
EDGE_CENTRE_PX = 20.0


class RecordingEncoder:
    """A stand-in for the frozen backbone that records what it was handed.

    The embedding it returns is a function of the patch that produced it — the
    mean, the spread and the first pixel of the prepared batch — so a row in the
    featuriser's output names the patch it came from. That is what lets a test
    assert the *order* of the rows and not merely their number, which is the
    property a shape check cannot see.
    """

    #: Three columns, not 1280. The width is the encoder's business and the
    #: store records whatever it is told, so a fake need not carry MobileNetV2's.
    width = 3

    def __init__(self):
        self.batches: list[np.ndarray] = []

    @property
    def calls(self) -> int:
        return len(self.batches)

    @property
    def patches_seen(self) -> int:
        return sum(len(batch) for batch in self.batches)

    def __call__(self, batch):
        recorded = np.array(batch, dtype=np.float32)
        self.batches.append(recorded)
        return _signature(recorded)


class FailingEncoder:
    """An encoder that refuses, for the paths that must leave nothing behind."""

    def __init__(self):
        self.calls = 0

    def __call__(self, batch):
        self.calls += 1
        raise RuntimeError("the encoder refused this batch")


def _signature(prepared: np.ndarray) -> np.ndarray:
    """The embedding :class:`RecordingEncoder` gives a prepared batch."""
    flat = np.asarray(prepared, dtype=np.float32).reshape(len(prepared), -1)
    return np.stack([flat.mean(axis=1), flat.std(axis=1), flat[:, 0]], axis=1)


def _prepared(patches) -> np.ndarray:
    """The batch these raw patches must reach the weights as.

    The arithmetic is written out here rather than borrowed from
    `prepare_for_mobilenet_v2`: an assertion made with the function it is
    checking passes whatever that function does, and this is the one convention
    that can be wrong without changing a single shape.
    """
    return np.stack(patches).astype(np.float64) / 255.0 * 2.0 - 1.0


def _expected_rows(patches) -> np.ndarray:
    """What the featuriser must return for these raw patches, in this order."""
    return _signature(_prepared(patches))


def _photograph(
    level,
    seed,
    side=SIDE_PX,
    centre=CENTRE_PX,
    diameter=DISC_DIAMETER_PX,
):
    """A dish of textured soil on a bright bench, in the photograph's pixels."""
    generator = np.random.default_rng(seed)
    rows, columns = np.mgrid[0:side, 0:side]
    radius = np.hypot(rows - centre, columns - centre)
    noise = generator.uniform(-TEXTURE_AMPLITUDE, TEXTURE_AMPLITUDE, size=radius.shape)
    plane = np.where(radius <= diameter / 2.0, level + noise, 235.0)
    # Grey, so the BT.601 luma of a pixel is the pixel and a patch's mean is the
    # soil level it was painted with.
    stacked = np.dstack([plane, plane, plane]).clip(0.0, 255.0)
    return Image.fromarray(stacked.astype(np.uint8), mode="RGB")


def _write_measured_version(tmp_path, photographs, version="v1"):
    """Write a dataset version whose manifest carries the dish measurement."""
    root = tmp_path / "datasets" / version
    (root / "images").mkdir(parents=True)

    rows = []
    for index, photograph in enumerate(photographs):
        relative = f"images/photograph_{index}.png"
        photograph["image"].save(root / relative)
        rows.append(
            ManifestRow(
                sample_id=photograph.get("sample_id", f"sample-{index}"),
                texture_class=photograph["class"],
                image=relative,
                setting="dish",
                site=photograph.get("site", "Fazenda Um"),
                device="Pixel 8",
                captured_at="2026-08-12",
                source_width=photograph["image"].width,
                source_height=photograph["image"].height,
                scale={
                    "mm_per_px": photograph.get("mm_per_px", MEASURED),
                    "disc_diameter_px": photograph.get("diameter", DISC_DIAMETER_PX),
                    "disc_centre_x_px": photograph.get("centre_x", CENTRE_PX),
                    "disc_centre_y_px": photograph.get("centre_y", CENTRE_PX),
                    "frame_width_px": float(photograph["image"].width),
                    "frame_height_px": float(photograph["image"].height),
                },
            )
        )

    write_manifest(root, rows)
    return root


def _config(root, image_size=INPUT_SIZE, canonical=CANONICAL):
    return {
        "classes": ["Arenosa", "Media"],
        "data": {
            "datasets_dir": str(root.parent),
            "dataset_version": root.name,
            "image_size": image_size,
            "seed": 7,
        },
        "evaluation": {"k": 2, "repeats": 1, "inner_k": 2},
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
            "canonical_mm_per_px": canonical,
            "patch_stride_fraction": 0.5,
            "min_patches": PATCHES_PER_PHOTOGRAPH,
        },
        "augmentation": {},
        "training": {"batch_size": 4},
    }


def _entries(root, labels):
    """Fold entries for the version's photographs, in manifest order."""
    return [
        {
            "path": str(root / f"images/photograph_{index}.png"),
            "label": label,
            "class": f"C{label}",
            "group": f"C{label}::sample-{index}",
        }
        for index, label in enumerate(labels)
    ]


def _patches_of(entry, cfg):
    """The grid the pipeline cuts for one entry, straight from `src.dataset`."""
    return _photograph_patches(entry, photograph_scale(cfg)[entry["path"]], cfg)


@pytest.fixture
def dish_version(tmp_path):
    """Two measured photographs of two distinguishable soils."""
    return _write_measured_version(
        tmp_path,
        [
            {"class": "Arenosa", "image": _photograph(SOIL_LEVELS[0], seed=1)},
            {"class": "Media", "image": _photograph(SOIL_LEVELS[1], seed=2)},
        ],
    )


@pytest.fixture
def dish_entries(dish_version):
    return _entries(dish_version, [0, 1])


@pytest.fixture
def dish_config(dish_version):
    return _config(dish_version)


@pytest.fixture
def arm_dir(tmp_path):
    """Where one arm's folds live, and therefore where its cache lives."""
    directory = tmp_path / "models" / "v1" / "encoder_probe"
    directory.mkdir(parents=True)
    return directory


# --- the featuriser the fold trainer calls ---------------------------------


def test_the_featuriser_returns_one_row_per_patch_in_patch_order(
    arm_dir, dish_config, dish_entries
):
    """One row per patch, in the order the grid cuts them.

    The rows are compared against the patches `src.dataset` produces for the
    same entry, so this pins the correspondence and not only the count: a
    featuriser that embedded the grid in a different order would return the
    right shape and put every photograph's rows against the wrong patches.
    """
    entry = dish_entries[0]
    features = encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        entry, dish_config
    )

    assert isinstance(features, np.ndarray)
    assert features.dtype == np.float32
    assert features.shape == (PATCHES_PER_PHOTOGRAPH, RecordingEncoder.width)
    np.testing.assert_allclose(
        features, _expected_rows(_patches_of(entry, dish_config)), atol=1e-5
    )


def test_the_featuriser_takes_one_entry_and_the_config_and_nothing_else(
    arm_dir, dish_config, dish_entries
):
    """The shared fold trainer calls a two-argument featuriser."""
    featuriser = encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())

    features = featuriser(dish_entries[1], dish_config)

    assert features.shape[0] == PATCHES_PER_PHOTOGRAPH


def test_a_featuriser_built_for_one_patch_size_refuses_a_call_at_another(
    arm_dir, dish_version, dish_config, dish_entries
):
    """The backbone is built for one input size and the cache keyed to one grid.

    Named rather than left to fail as a shape error inside Keras: a 32 px patch
    reaching a 16 px backbone is a configuration that changed under a featuriser
    that was already bound, and the remedy is to bind a second one.
    """
    featuriser = encoder_featuriser(
        arm_dir, dish_config, encoder=RecordingEncoder()
    )

    with pytest.raises(ValueError, match="image_size"):
        featuriser(dish_entries[0], _config(dish_version, image_size=32))


def test_the_featuriser_refuses_a_photograph_the_patch_grid_refuses(
    tmp_path, arm_dir
):
    """A refusal is propagated, never absorbed into a short feature matrix.

    A photograph whose grid leaves the frame produces no patches at all. An arm
    that returned the rows it could cut would train on a photograph the protocol
    has no prediction for, and nothing in the fold artifacts would say so.
    """
    root = _write_measured_version(
        tmp_path,
        [
            {
                "class": "Arenosa",
                "image": _photograph(SOIL_LEVELS[0], seed=4),
                "centre_x": EDGE_CENTRE_PX,
            }
        ],
    )
    cfg = _config(root)
    encoder = RecordingEncoder()

    with pytest.raises(ValueError, match="region_not_wholly_photographed"):
        encoder_featuriser(arm_dir, cfg, encoder=encoder)(_entries(root, [0])[0], cfg)

    assert encoder.calls == 0


# --- the preprocessing convention, which no shape test can see --------------


def test_the_preprocessing_convention_maps_black_to_minus_one_and_white_to_one():
    """Divide by 255, then the Rescaling(2.0, -1.0) the model bakes in.

    This is `preprocess.normalize_mobilenet_v2` followed by the layer
    `model.build_model` places after the input, which is what makes a patch
    reach these frozen weights exactly as it reaches the fine-tuned ones. Get it
    wrong and the embeddings are still 1280 floats of the right shape.
    """
    prepared = prepare_for_mobilenet_v2(np.array([[0, 128, 255]], dtype=np.uint8))

    assert prepared.dtype == np.float32
    # Absolute rather than relative, because the middle value straddles zero and
    # the arithmetic is float32: a relative tolerance there measures the format,
    # not the convention.
    np.testing.assert_allclose(
        prepared, [[-1.0, 128.0 / 255.0 * 2.0 - 1.0, 1.0]], atol=1e-6
    )


def test_the_patches_reaching_the_encoder_carry_the_range_the_weights_expect(
    arm_dir, dish_config, dish_entries
):
    """Asserted on the batch the encoder was actually handed, not on a helper."""
    entry = dish_entries[0]
    encoder = RecordingEncoder()

    encoder_featuriser(arm_dir, dish_config, encoder=encoder)(entry, dish_config)

    handed = np.concatenate(encoder.batches, axis=0)
    assert handed.dtype == np.float32
    assert handed.shape == (
        PATCHES_PER_PHOTOGRAPH,
        INPUT_SIZE,
        INPUT_SIZE,
        3,
    )
    assert handed.min() >= -1.0 and handed.max() <= 1.0
    # A patch of soil at level 60 reaches the weights at -0.53, not at 0.24: the
    # range is the assertion, and it is made against the arithmetic rather than
    # against the module's own helper.
    np.testing.assert_allclose(
        handed, _prepared(_patches_of(entry, dish_config)), atol=1e-6
    )


def test_a_photographs_grid_reaches_the_encoder_in_one_forward_pass(
    arm_dir, dish_config, dish_entries
):
    """Batched, because one patch per call is dominated by the call overhead."""
    encoder = RecordingEncoder()

    encoder_featuriser(arm_dir, dish_config, encoder=encoder)(
        dish_entries[0], dish_config
    )

    assert encoder.calls == 1
    assert encoder.patches_seen == PATCHES_PER_PHOTOGRAPH


# --- the cache, which is an acceptance criterion and not an optimisation -----


def test_the_encoder_is_not_called_twice_for_one_photograph(
    arm_dir, dish_config, dish_entries
):
    """encoder_features_are_computed_once_per_patch, within one featuriser."""
    encoder = RecordingEncoder()
    featuriser = encoder_featuriser(arm_dir, dish_config, encoder=encoder)

    first = featuriser(dish_entries[0], dish_config)
    second = featuriser(dish_entries[0], dish_config)

    assert encoder.calls == 1
    np.testing.assert_array_equal(first, second)


def test_a_second_fold_over_the_same_photographs_reads_the_cache(
    arm_dir, dish_config, dish_entries
):
    """encoder_features_are_computed_once_per_patch, across folds.

    The arm is 25 folds over the same photographs, and each fold builds its own
    featuriser. Counting encoder calls rather than timing the two runs: a timing
    assertion passes on a fast machine that recomputed everything.
    """
    first_encoder = RecordingEncoder()
    for entry in dish_entries:
        encoder_featuriser(arm_dir, dish_config, encoder=first_encoder)(
            entry, dish_config
        )

    second_encoder = RecordingEncoder()
    second_fold = [
        encoder_featuriser(arm_dir, dish_config, encoder=second_encoder)(
            entry, dish_config
        )
        for entry in dish_entries
    ]

    assert first_encoder.patches_seen == 2 * PATCHES_PER_PHOTOGRAPH
    assert second_encoder.calls == 0
    for entry, features in zip(dish_entries, second_fold):
        np.testing.assert_allclose(
            features, _expected_rows(_patches_of(entry, dish_config)), atol=1e-5
        )


def test_each_photograph_gets_its_own_cache_entry(
    arm_dir, dish_config, dish_entries
):
    """Keyed by the photograph's path, so two photographs never share a file."""
    featuriser = encoder_featuriser(
        arm_dir, dish_config, encoder=RecordingEncoder()
    )
    for entry in dish_entries:
        featuriser(entry, dish_config)

    written = {feature_cache_path(arm_dir, entry["path"]) for entry in dish_entries}

    assert len(written) == len(dish_entries)
    assert all(path.exists() for path in written)


def test_the_cache_records_the_manifest_digest_it_was_written_under(
    arm_dir, dish_config, dish_entries
):
    """a_cached_feature_from_another_version_is_refused needs something to check."""
    from src.manifest import dataset_root, manifest_digest

    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )

    sidecar = json.loads(
        (feature_cache_directory(arm_dir) / CACHE_SIDECAR_FILENAME).read_text()
    )
    root = dataset_root(
        dish_config["data"]["datasets_dir"], dish_config["data"]["dataset_version"]
    )

    assert sidecar["schema_version"] == CACHE_SCHEMA_VERSION
    assert sidecar["manifest_digest"] == manifest_digest(root)
    assert sidecar["image_size"] == INPUT_SIZE
    assert sidecar["canonical_mm_per_px"] == CANONICAL
    assert sidecar["patch_stride_fraction"] == 0.5
    assert sidecar["preprocessing"] == PREPROCESSING_CONVENTION
    assert sidecar["feature_width"] == RecordingEncoder.width


def test_a_cached_feature_from_another_version_is_refused(
    arm_dir, dish_version, dish_config, dish_entries
):
    """The dataset changed under the cache; the cache is refused, not read.

    The manifest is edited the way a real change would edit it, so the digest
    moves for the reason it exists to move rather than because a test handed it
    a different string.
    """
    from dataclasses import replace

    from src.manifest import ARCHIVE_CLASSES, read_manifest

    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )

    rows = read_manifest(dish_version, ARCHIVE_CLASSES).rows
    write_manifest(dish_version, [replace(rows[0], site="Outra"), *rows[1:]])

    later_encoder = RecordingEncoder()
    with pytest.raises(ValueError, match="manifest_digest"):
        encoder_featuriser(arm_dir, dish_config, encoder=later_encoder)

    assert later_encoder.calls == 0


def test_a_cache_cut_at_another_patch_size_is_refused(
    arm_dir, dish_version, dish_config, dish_entries
):
    """A 16 px grid's embeddings cannot serve a 32 px run of the same data."""
    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )

    with pytest.raises(ValueError, match="image_size"):
        encoder_featuriser(
            arm_dir, _config(dish_version, image_size=32), encoder=RecordingEncoder()
        )


def test_a_cache_cut_under_another_patch_geometry_is_refused(
    arm_dir, dish_version, dish_config, dish_entries
):
    """The manifest digest cannot see `config.yaml`, and the grid lives there.

    A change to the canonical scale moves every patch over the same pixels
    without necessarily changing how many of them a dish carries, so the row
    count is not enough on its own: the store records the three values that
    decide where a patch is cut and refuses a run that changed one.
    """
    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )

    finer = _config(dish_version, canonical=CANONICAL * 2)
    with pytest.raises(ValueError, match="canonical_mm_per_px"):
        encoder_featuriser(arm_dir, finer, encoder=RecordingEncoder())


def test_a_cache_written_under_another_preprocessing_convention_is_refused(
    arm_dir, dish_config, dish_entries
):
    """The failure a shape check cannot see is the one the store names."""
    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )

    sidecar_path = feature_cache_directory(arm_dir) / CACHE_SIDECAR_FILENAME
    sidecar = json.loads(sidecar_path.read_text())
    sidecar["preprocessing"] = "divide_255"
    sidecar_path.write_text(json.dumps(sidecar), encoding="utf-8")

    with pytest.raises(ValueError, match="preprocessing"):
        encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())


def test_an_unreadable_sidecar_is_refused_rather_than_written_over(
    arm_dir, dish_config, dish_entries
):
    """A store whose identity cannot be read cannot be shown to belong here.

    Rebuilding the sidecar over the feature files already beside it would give
    them a provenance nobody established: they would then claim this dataset
    version whatever they were computed from.
    """
    encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())(
        dish_entries[0], dish_config
    )
    (feature_cache_directory(arm_dir) / CACHE_SIDECAR_FILENAME).write_text(
        "{not json", encoding="utf-8"
    )

    with pytest.raises(ValueError, match=CACHE_SIDECAR_FILENAME):
        encoder_featuriser(arm_dir, dish_config, encoder=RecordingEncoder())


def test_a_half_written_cache_entry_is_recomputed_rather_than_read_as_complete(
    arm_dir, dish_config, dish_entries
):
    """A file the encoder never finished writing is a miss, not a short answer."""
    entry = dish_entries[0]
    complete = encoder_featuriser(
        arm_dir, dish_config, encoder=RecordingEncoder()
    )(entry, dish_config)

    torn = feature_cache_path(arm_dir, entry["path"])
    torn.write_bytes(torn.read_bytes()[: len(torn.read_bytes()) // 2])

    encoder = RecordingEncoder()
    recomputed = encoder_featuriser(arm_dir, dish_config, encoder=encoder)(
        entry, dish_config
    )

    assert encoder.calls == 1
    np.testing.assert_allclose(recomputed, complete, rtol=1e-6)


def test_an_interrupted_write_leaves_nothing_at_the_destination(
    arm_dir, dish_config, dish_entries, monkeypatch
):
    """The destination appears whole or not at all, and no scratch file remains."""
    entry = dish_entries[0]
    featuriser = encoder_featuriser(
        arm_dir, dish_config, encoder=RecordingEncoder()
    )

    def refuse(*args, **kwargs):
        raise OSError("the disk went away mid-write")

    monkeypatch.setattr(np, "save", refuse)
    with pytest.raises(OSError):
        featuriser(entry, dish_config)
    monkeypatch.undo()

    assert not feature_cache_path(arm_dir, entry["path"]).exists()
    assert not list(feature_cache_directory(arm_dir).glob("*.tmp"))

    encoder = RecordingEncoder()
    recovered = encoder_featuriser(arm_dir, dish_config, encoder=encoder)(
        entry, dish_config
    )
    assert encoder.calls == 1
    np.testing.assert_allclose(
        recovered, _expected_rows(_patches_of(entry, dish_config)), atol=1e-5
    )


def test_an_encoder_that_refuses_leaves_no_cache_entry_claiming_success(
    arm_dir, dish_config, dish_entries
):
    """A fold that died partway must not look complete to the fold after it."""
    entry = dish_entries[0]
    encoder = FailingEncoder()

    with pytest.raises(RuntimeError):
        encoder_featuriser(arm_dir, dish_config, encoder=encoder)(entry, dish_config)

    assert encoder.calls == 1
    assert not feature_cache_path(arm_dir, entry["path"]).exists()


# --- the arm the dispatch resolves ------------------------------------------


def test_the_arm_binds_its_featuriser_to_the_shared_fold_trainer(
    arm_dir, dish_config, dish_entries, monkeypatch
):
    """`encoder_probe_fold` is a binding and nothing else.

    Every choice the fold makes — the selection, the standardisation, the
    aggregation back to one prediction per photograph — is `probe_fold`'s, and
    shared with the descriptor arm. An arm that reimplemented any of them would
    differ from the arm it is contrasted against in more than its features,
    which is the confound SPEC 0054 exists to avoid.
    """
    seen = {}

    def probe_fold(cfg, fold_manifest, **kwargs):
        seen.update(kwargs)
        seen["cfg"] = cfg
        seen["fold_manifest"] = fold_manifest
        return {"deterministic_ops": True}

    stub = types.ModuleType("src.arms.probe")
    stub.probe_fold = probe_fold
    monkeypatch.setitem(sys.modules, "src.arms.probe", stub)

    returned = encoder_probe_fold(
        dish_config,
        {"repeats": 1, "k": 2},
        arm_dir=arm_dir,
        arm="encoder_probe",
        repeat=0,
        fold=1,
        shuffled_control=True,
        verify=False,
    )

    assert returned == {"deterministic_ops": True}
    assert seen["arm_dir"] == arm_dir
    assert seen["arm"] == "encoder_probe"
    assert (seen["repeat"], seen["fold"]) == (0, 1)
    assert seen["shuffled_control"] is True
    assert seen["verify"] is False
    assert callable(seen["featuriser"])


def test_the_module_is_importable_without_the_training_stack():
    """TensorFlow is imported on first use, the way `src.dataset` imports it.

    Every read of this module — the cache, the store's provenance, the arm's
    binding — has to be possible on a machine with no training stack, which is
    where most of this suite runs.
    """
    source = (
        "import sys\n"
        "import src.arms.encoder\n"
        "assert 'tensorflow' not in sys.modules, 'tensorflow was imported'\n"
    )
    result = subprocess.run(
        [sys.executable, "-c", source],
        cwd=str(Path(__file__).resolve().parents[1]),
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


# --- the frozen backbone itself ---------------------------------------------


@pytest.fixture
def full_size_version(tmp_path):
    """One photograph whose grid is cut at the production patch size."""
    return _write_measured_version(
        tmp_path,
        [
            {
                "class": "Arenosa",
                "image": _photograph(
                    SOIL_LEVELS[0],
                    seed=11,
                    side=FULL_SIDE_PX,
                    centre=FULL_CENTRE_PX,
                    diameter=FULL_DISC_DIAMETER_PX,
                ),
                "mm_per_px": CANONICAL,
                "centre_x": FULL_CENTRE_PX,
                "centre_y": FULL_CENTRE_PX,
                "diameter": FULL_DISC_DIAMETER_PX,
            }
        ],
    )


@requires_tensorflow
def test_the_frozen_backbone_embeds_a_patch_as_1280_floats():
    """MobileNetV2, ImageNet weights, global-average-pooled."""
    from src.arms.encoder import _mobilenet_v2_encoder

    batch = prepare_for_mobilenet_v2(
        np.random.default_rng(3).integers(
            0, 256, size=(2, FULL_INPUT_SIZE, FULL_INPUT_SIZE, 3), dtype=np.uint8
        )
    )

    embedded = _mobilenet_v2_encoder(FULL_INPUT_SIZE)(batch)

    assert embedded.shape == (2, ENCODER_EMBEDDING_DIM)
    assert np.isfinite(embedded).all()
    # Two different patches, two different embeddings: a backbone that pooled to
    # a constant would pass every shape assertion above.
    assert not np.allclose(embedded[0], embedded[1])


@requires_tensorflow
def test_the_backbone_is_built_once_per_process():
    """Weights are loaded once, not once per photograph."""
    from src.arms.encoder import _backbone

    assert _backbone(FULL_INPUT_SIZE) is _backbone(FULL_INPUT_SIZE)


@requires_tensorflow
def test_the_arm_embeds_a_photographs_grid_and_caches_it(
    arm_dir, full_size_version
):
    """End to end on the real backbone: nine patches, 1280 columns, cached once."""
    cfg = _config(full_size_version, image_size=FULL_INPUT_SIZE)
    entry = _entries(full_size_version, [0])[0]

    features = encoder_featuriser(arm_dir, cfg)(entry, cfg)

    assert features.shape == (PATCHES_PER_PHOTOGRAPH, ENCODER_EMBEDDING_DIM)
    assert features.dtype == np.float32

    # A second featuriser, standing for the next fold, must not touch the model.
    refused = FailingEncoder()
    reread = encoder_featuriser(arm_dir, cfg, encoder=refused)(entry, cfg)

    assert refused.calls == 0
    np.testing.assert_array_equal(reread, features)
