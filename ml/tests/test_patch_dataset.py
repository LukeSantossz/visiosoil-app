"""The training pipeline as a stream of scale-normalised patches (SPEC 0053).

`test_patches.py` covers the grid itself — the resample, the inset, the counts.
This covers what `src.dataset` does with it: one tensor per patch rather than
one per photograph, the measured dish read from the manifest, and the caching,
shuffling and augmentation order the stream is assembled in. The SPEC 0050
cache criteria moved here with `build_dataset`, because they are statements
about this pipeline and there is now one fixture that can express them.

The fixture works at its own canonical scale and its own input size: the grid
is arithmetic, so a 16 px patch on a 100 px dish exercises every property a
160 px patch on a 697 px dish does, in a fraction of the time.
"""

import numpy as np
import pytest
from PIL import Image

from src.dataset import (
    build_dataset,
    create_folds_for_config,
    drop_refused_photographs,
    fold_split,
    photograph_patch_counts,
    photograph_scale,
)
from src.manifest import SCALE_COLUMNS, ManifestRow, write_manifest
from src.patches import PatchRefusal, cut_patches, resample_to_canonical
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

#: Soil levels far enough apart that a patch's mean names the photograph it was
#: cut from, whatever the texture noise does. See :func:`_photograph_of`.
SOIL_LEVELS = (60, 110, 160)
TEXTURE_AMPLITUDE = 12.0

#: A bright square painted into one photograph, so a patch's content can be
#: located against the arithmetic rather than against itself. Twelve pixels
#: across and aligned to an even boundary, so the two-to-one resample lands it
#: on whole pixels.
MARKER_PX = 12
MARKER_TOP_LEFT = (110, 94)
MARKER_LEVEL = 250


def _photograph(level, seed, marker=None, diameter=DISC_DIAMETER_PX):
    """A dish of textured soil on a bright bench, in the photograph's pixels."""
    generator = np.random.default_rng(seed)
    rows, columns = np.mgrid[0:SIDE_PX, 0:SIDE_PX]
    radius = np.hypot(rows - CENTRE_PX, columns - CENTRE_PX)
    noise = generator.uniform(-TEXTURE_AMPLITUDE, TEXTURE_AMPLITUDE, size=radius.shape)
    plane = np.where(radius <= diameter / 2.0, level + noise, 235.0)
    if marker is not None:
        top, left = marker
        plane[top : top + MARKER_PX, left : left + MARKER_PX] = MARKER_LEVEL
    # Grey, so the BT.601 luma of a pixel is the pixel: a patch's mean is the
    # soil level it was painted with, and `_photograph_of` can read it back.
    stacked = np.dstack([plane, plane, plane]).clip(0.0, 255.0)
    return Image.fromarray(stacked.astype(np.uint8), mode="RGB")


def _write_measured_version(tmp_path, photographs, version="v1"):
    """Write a dataset version whose manifest carries the dish measurement.

    `tests.support.write_image_version` writes neither the four scale columns
    nor a class per photograph, and every test here needs both.
    """
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
                site="Fazenda Um",
                device="Pixel 8",
                captured_at="2026-08-12",
                scale={
                    "mm_per_px": photograph.get("mm_per_px", MEASURED),
                    "disc_diameter_px": photograph.get("diameter", DISC_DIAMETER_PX),
                    "disc_centre_x_px": CENTRE_PX,
                    "disc_centre_y_px": CENTRE_PX,
                },
            )
        )

    write_manifest(root, rows)
    return root


def _config(root, batch_size=1, augmentation=None, classes=("Arenosa", "Media")):
    return {
        "classes": list(classes),
        "data": {
            "datasets_dir": str(root.parent),
            "dataset_version": root.name,
            "image_size": INPUT_SIZE,
            "seed": 7,
        },
        "evaluation": {"k": 2, "repeats": 1, "inner_k": 2},
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
            "canonical_mm_per_px": CANONICAL,
            "patch_stride_fraction": 0.5,
            "min_patches": PATCHES_PER_PHOTOGRAPH,
        },
        "augmentation": augmentation or {},
        "training": {"batch_size": batch_size},
    }


def _path(root, index):
    """The path a fold manifest carries, which is what `class_images` builds."""
    return str(root / f"images/photograph_{index}.png")


def _entries(root, labels):
    """Fold entries for the version's photographs, in manifest order."""
    return [
        {
            "path": _path(root, index),
            "label": label,
            "class": f"C{label}",
            "group": f"C{label}::sample-{index}",
        }
        for index, label in enumerate(labels)
    ]


def _photograph_of(patch, levels=SOIL_LEVELS):
    """Which photograph a patch was cut from, read off its soil level.

    Nearest level rather than an exact signature: the soil carries texture, so
    two patches of one photograph have means that differ in the first decimal
    and are fifty apart from any other photograph's.
    """
    mean = float(np.asarray(patch).mean()) * 255.0
    return min(range(len(levels)), key=lambda index: abs(levels[index] - mean))


def _tensors(dataset):
    """Every (patch, label) the dataset yields, unbatched, in order."""
    return [
        (patch.numpy(), label.numpy())
        for patches, labels in dataset
        for patch, label in zip(patches, labels)
    ]


def _patches(dataset):
    return [patch for patch, _ in _tensors(dataset)]


@pytest.fixture
def dish_version(tmp_path):
    """Three measured photographs of three distinguishable soils."""
    return _write_measured_version(
        tmp_path,
        [
            {"class": "Arenosa", "image": _photograph(SOIL_LEVELS[0], seed=1)},
            {"class": "Media", "image": _photograph(SOIL_LEVELS[1], seed=2)},
            {"class": "Arenosa", "image": _photograph(SOIL_LEVELS[2], seed=3)},
        ],
    )


@pytest.fixture
def dish_entries(dish_version):
    return _entries(dish_version, [0, 1, 0])


# --- the measurement the grid is cut around --------------------------------


def test_photograph_scale_maps_every_resolved_path_to_its_measurement(dish_version):
    """Keyed by the path a fold entry carries, so a caller joins on what it has."""
    scale = photograph_scale(_config(dish_version))

    assert set(scale) == {_path(dish_version, index) for index in range(3)}
    assert set(scale[_path(dish_version, 0)]) == set(SCALE_COLUMNS)
    assert scale[_path(dish_version, 0)]["disc_diameter_px"] == pytest.approx(
        DISC_DIAMETER_PX
    )


def test_photograph_scale_names_the_command_that_measures_an_unmeasured_version(
    tmp_path,
):
    """A version is ingested before it is measured; the remedy is one command."""
    from dataclasses import replace
    from src.manifest import read_manifest
    from tests.support import CLASSES

    root = _write_measured_version(
        tmp_path, [{"class": "Arenosa", "image": _photograph(SOIL_LEVELS[0], seed=1)}]
    )
    write_manifest(
        root, [replace(row, scale={}) for row in read_manifest(root, CLASSES).rows]
    )

    with pytest.raises(ValueError, match="measure_scale.py"):
        photograph_scale(_config(root))


def test_photograph_scale_reads_one_manifest_once_per_process(
    dish_version, monkeypatch
):
    """Every fold of every repeat asks for this; parsing it each time is waste."""
    from src import dataset as dataset_module

    reads = []
    original = dataset_module.read_manifest

    def counting(root, classes, **kwargs):
        reads.append(str(root))
        return original(root, classes, **kwargs)

    monkeypatch.setattr(dataset_module, "read_manifest", counting)
    cfg = _config(dish_version)

    first = photograph_scale(cfg)
    second = photograph_scale(cfg)

    assert first == second
    assert len(reads) == 1, f"the manifest was read {len(reads)} times"


def test_photograph_scale_rereads_a_manifest_that_changed(dish_version):
    """Keyed by the digest, so a remeasured version is a new entry, not a hit.

    `measure_scale.py` rewrites the manifest in place, and a memo keyed by the
    root alone would serve the readings from before it ran for the rest of the
    process.
    """
    from dataclasses import replace
    from src.manifest import read_manifest
    from tests.support import CLASSES

    cfg = _config(dish_version)
    before = photograph_scale(cfg)[_path(dish_version, 0)]["disc_diameter_px"]
    write_manifest(
        dish_version,
        [
            replace(row, scale={**row.scale, "disc_diameter_px": 80.0})
            for row in read_manifest(dish_version, CLASSES).rows
        ],
    )

    after = photograph_scale(cfg)[_path(dish_version, 0)]["disc_diameter_px"]

    assert before == pytest.approx(DISC_DIAMETER_PX)
    assert after == pytest.approx(80.0)


def test_photograph_scale_serves_two_manifests_in_one_process(tmp_path):
    """The memo is keyed by the manifest, not by the module."""
    first = _write_measured_version(
        tmp_path / "first",
        [{"class": "Arenosa", "image": _photograph(SOIL_LEVELS[0], seed=1)}],
    )
    second = _write_measured_version(
        tmp_path / "second",
        [
            {
                "class": "Arenosa",
                "image": _photograph(SOIL_LEVELS[0], seed=1),
                "diameter": 80.0,
            }
        ],
    )

    measured_first = photograph_scale(_config(first))
    measured_second = photograph_scale(_config(second))

    assert measured_first[_path(first, 0)]["disc_diameter_px"] == pytest.approx(96.0)
    assert measured_second[_path(second, 0)]["disc_diameter_px"] == pytest.approx(80.0)


# --- one tensor per patch --------------------------------------------------


@requires_tensorflow
def test_the_dataset_yields_one_tensor_per_patch(dish_version, dish_entries):
    """SPEC 0053: N photographs of P patches produce N x P tensors.

    Each labelled with its photograph's class, and each the input size across
    with three identical channels — the greyscale MobileNetV2's ImageNet
    weights are loaded against.
    """
    cfg = _config(dish_version)

    tensors = _tensors(build_dataset(dish_entries, cfg))

    assert len(tensors) == len(dish_entries) * PATCHES_PER_PHOTOGRAPH
    for position, (patch, label) in enumerate(tensors):
        entry = dish_entries[position // PATCHES_PER_PHOTOGRAPH]
        assert patch.shape == (INPUT_SIZE, INPUT_SIZE, 3)
        assert patch.dtype == np.float32
        assert np.array_equal(patch[..., 0], patch[..., 1])
        assert np.array_equal(patch[..., 1], patch[..., 2])
        assert int(label.argmax()) == entry["label"]


@requires_tensorflow
def test_the_patch_counts_agree_with_what_the_dataset_yields(
    dish_version, dish_entries
):
    """`train.py` slices the model's output by these counts, so they must agree.

    Not only in total: the boundaries have to fall between photographs, or a
    photograph's averaged distribution is a mixture of two soils.
    """
    cfg = _config(dish_version)
    counts = photograph_patch_counts(dish_entries, cfg)

    patches = _patches(build_dataset(dish_entries, cfg))

    assert counts == [PATCHES_PER_PHOTOGRAPH] * len(dish_entries)
    assert sum(counts) == len(patches)
    start = 0
    for index, count in enumerate(counts):
        origins = {_photograph_of(patch) for patch in patches[start : start + count]}
        assert origins == {index}, f"slice {index} mixes photographs {origins}"
        start += count


def test_the_patch_counts_open_no_image(dish_version, dish_entries, monkeypatch):
    """Counting is arithmetic over the measured dish, not a pass over the data.

    `train.py` needs the counts once per fold to slice its predictions back
    into photographs; paying a decode of the whole fold for a number the
    manifest already implies would double the cost of the bookkeeping.
    """
    from src import dataset as dataset_module

    def refuse(*args, **kwargs):
        raise AssertionError("the patch counts decoded a photograph")

    monkeypatch.setattr(dataset_module.Image, "open", refuse)

    counts = photograph_patch_counts(dish_entries, _config(dish_version))

    assert counts == [PATCHES_PER_PHOTOGRAPH] * len(dish_entries)


# --- the grid is cut where the arithmetic says -----------------------------


@requires_tensorflow
def test_a_patch_lands_where_the_arithmetic_says(tmp_path):
    """The dish is measured in the photograph's pixels and the image is resampled.

    So the centre and the diameter travel by the same ratio the image does. Get
    that wrong and the grid is cut from the wrong place while still producing
    patches, which is the silent version of this failure.

    The marker is painted 16 px below the dish centre in the photograph, which
    is 8 px after the resample, which is exactly the centre of the patch at
    offset (8, 0) — the eighth of the nine sorted offsets.
    """
    root = _write_measured_version(
        tmp_path,
        [
            {
                "class": "Arenosa",
                "image": _photograph(SOIL_LEVELS[0], seed=1, marker=MARKER_TOP_LEFT),
            }
        ],
    )

    patches = _patches(build_dataset(_entries(root, [0]), _config(root)))

    below_the_centre = patches[7][..., 0]
    rows, columns = np.nonzero(below_the_centre > 0.8)
    assert rows.size == (MARKER_PX // 2) ** 2, "the marker is not wholly in the patch"
    assert rows.mean() == pytest.approx((INPUT_SIZE - 1) / 2.0, abs=0.5)
    assert columns.mean() == pytest.approx((INPUT_SIZE - 1) / 2.0, abs=0.5)
    above_the_centre = patches[1][..., 0]
    assert not (above_the_centre > 0.8).any(), "the marker reached the wrong patch"


@requires_tensorflow
def test_the_pipeline_resamples_before_it_cuts(dish_version, dish_entries):
    """Cutting first and resampling after would resample the soil, not the frame.

    Asserted against the two `patches.py` functions applied in that order, so
    the ordering is pinned by an oracle rather than by the pipeline's own
    output. A patch is never resized on top of that: it leaves the grid at the
    input size, and `preprocess.preprocess` — which resizes — is not on this
    path.
    """
    cfg = _config(dish_version)
    with Image.open(dish_entries[0]["path"]) as handle:
        photograph = handle.convert("RGB")
    resampled, _ = resample_to_canonical(photograph, MEASURED, CANONICAL)
    ratio = MEASURED / CANONICAL
    expected = cut_patches(
        resampled,
        centre_y=CENTRE_PX * ratio,
        centre_x=CENTRE_PX * ratio,
        region_diameter_px=DISC_DIAMETER_PX * ratio,
        input_size=INPUT_SIZE,
        canonical_mm_per_px=CANONICAL,
        min_patches=PATCHES_PER_PHOTOGRAPH,
        stride_fraction=0.5,
    )

    produced = _patches(build_dataset(dish_entries[:1], cfg))

    assert len(produced) == len(expected)
    for patch, oracle in zip(produced, expected):
        assert np.array_equal(patch, oracle.astype(np.float32) / 255.0)


# --- what the cache and the shuffle buffer hold ----------------------------


@requires_tensorflow
def test_the_cached_stream_holds_uint8_patches(dish_version, dish_entries):
    """Normalising before the cache would quadruple what the fold costs in memory.

    A fold's training side is roughly 4500 patches at the production input
    size: 340 MB as uint8 and 1.7 GB as float32, held twice over while the
    shuffle buffer fills from the cache. The stream is uint8 and the finished
    pipeline is float32, which is what places the normalisation between them.
    """
    import tensorflow as tf
    from src import dataset as dataset_module

    stream = dataset_module._patch_stream(dish_entries, _config(dish_version))
    finished = build_dataset(dish_entries, _config(dish_version))

    assert stream.element_spec[0].dtype == tf.uint8
    assert tuple(stream.element_spec[0].shape) == (INPUT_SIZE, INPUT_SIZE, 3)
    assert finished.element_spec[0].dtype == tf.float32


@requires_tensorflow
def test_the_shuffle_buffer_spans_every_patch(dish_version, dish_entries):
    """A buffer sized by photographs shuffles a ninth of the epoch.

    With one buffer slot per photograph the first patch of the last photograph
    cannot be emitted before position `18 - 3 + 1`, whatever the seed: a buffer
    of size B never emits element i earlier than position `i - B + 1`. The
    assertion is that it lands before then, which only a patch-sized buffer
    allows.
    """
    cfg = _config(dish_version)
    counts = photograph_patch_counts(dish_entries, cfg)
    first_of_the_last = sum(counts[:-1])
    unreachable_with_a_photograph_buffer = first_of_the_last - len(dish_entries) + 1

    shuffled = build_dataset(dish_entries, cfg, shuffle=True)
    order = [_photograph_of(patch) for patch in _patches(shuffled)]

    assert len(order) == sum(counts)
    assert order.index(len(dish_entries) - 1) < unreachable_with_a_photograph_buffer


# --- a refused photograph is named, never skipped --------------------------


def _coarse_version(tmp_path):
    return _write_measured_version(
        tmp_path,
        [
            {"class": "Arenosa", "image": _photograph(SOIL_LEVELS[0], seed=1)},
            {
                "class": "Media",
                "image": _photograph(SOIL_LEVELS[1], seed=2),
                "mm_per_px": CANONICAL * 2.0,
            },
            {"class": "Arenosa", "image": _photograph(SOIL_LEVELS[2], seed=3)},
        ],
    )


def test_a_photograph_coarser_than_the_canonical_is_refused_by_name(tmp_path):
    """Refused before the fit starts, and by the name `patches.py` gives it."""
    root = _coarse_version(tmp_path)
    entries = _entries(root, [0, 1, 0])
    cfg = _config(root)

    with pytest.raises(ValueError, match=PatchRefusal.TOO_COARSE.value):
        photograph_patch_counts(entries, cfg)


@requires_tensorflow
def test_the_dataset_refuses_a_coarse_photograph_before_it_yields_anything(tmp_path):
    """Not mid-epoch, wrapped by tf.data: the refusal is a failure to build."""
    root = _coarse_version(tmp_path)
    entries = _entries(root, [0, 1, 0])

    with pytest.raises(ValueError, match=PatchRefusal.TOO_COARSE.value) as refusal:
        build_dataset(entries, _config(root))

    assert _path(root, 1) in str(refusal.value), "the refusal does not name the file"


def test_a_region_too_small_for_the_floor_is_refused_by_name(tmp_path):
    """A dish below the floor is refused rather than padded with background."""
    root = _write_measured_version(
        tmp_path,
        [
            {
                "class": "Arenosa",
                "image": _photograph(SOIL_LEVELS[0], seed=1, diameter=60.0),
                "diameter": 60.0,
            }
        ],
    )

    with pytest.raises(ValueError, match=PatchRefusal.REGION_TOO_SMALL.value):
        photograph_patch_counts(_entries(root, [0]), _config(root))


@requires_tensorflow
def test_dropping_a_refused_photograph_is_one_named_step(tmp_path):
    """SPEC 0053's eleven coarse photographs leave training here and nowhere else.

    The pipeline itself still refuses the whole list: a generator that skipped
    them would shorten an epoch by an amount nothing records.
    """
    root = _coarse_version(tmp_path)
    entries = _entries(root, [0, 1, 0])
    cfg = _config(root)

    kept, refused = drop_refused_photographs(entries, cfg)

    assert [entry["path"] for entry in kept] == [_path(root, 0), _path(root, 2)]
    assert list(refused) == [_path(root, 1)]
    assert PatchRefusal.TOO_COARSE.value in refused[_path(root, 1)]
    assert len(_patches(build_dataset(kept, cfg))) == 2 * PATCHES_PER_PHOTOGRAPH
    with pytest.raises(ValueError, match=PatchRefusal.TOO_COARSE.value):
        build_dataset(entries, cfg)


def test_a_photograph_the_manifest_does_not_hold_is_named(dish_version, dish_entries):
    """A fold manifest and a dataset version that disagree is not a refusal.

    It is a provenance fault, so it says so rather than dropping the entry.
    """
    stray = dict(dish_entries[0], path=_path(dish_version, 9))

    with pytest.raises(ValueError, match="not in the dataset manifest"):
        photograph_patch_counts([stray], _config(dish_version))


@requires_tensorflow
def test_an_unknown_normalisation_is_refused(dish_version, dish_entries):
    """The patch path skips `preprocess`, so it must not skip its one contract."""
    cfg = _config(dish_version)
    cfg["preprocessing"]["normalization"] = "imagenet"

    with pytest.raises(ValueError, match="Unknown normalization"):
        build_dataset(dish_entries, cfg)


# --- grouping is unchanged -------------------------------------------------


@requires_tensorflow
def test_patches_of_one_photograph_never_span_two_folds(tmp_path):
    """SPEC 0053: grouping stays on `sample_id`, and patches follow their photograph.

    Two photographs per sample, so the assertion is about a group and not only
    about a file: every patch of both photographs of a sample lands on one side
    of a fold, and the two sides share no photograph at all.
    """
    levels = tuple(range(40, 40 + 25 * 8, 25))
    root = _write_measured_version(
        tmp_path,
        [
            {
                "class": "Arenosa" if index < 4 else "Media",
                "sample_id": f"sample-{index // 2}",
                "image": _photograph(levels[index], seed=index + 1),
            }
            for index in range(8)
        ],
    )
    cfg = _config(root)
    folds = create_folds_for_config(cfg, str(tmp_path / "splits"))

    for fold in range(cfg["evaluation"]["k"]):
        split = fold_split(folds, 0, fold)
        seen = {}
        for side in ("train", "test"):
            counts = photograph_patch_counts(split[side], cfg)
            assert counts == [PATCHES_PER_PHOTOGRAPH] * len(split[side])
            seen[side] = [
                _photograph_of(patch, levels)
                for patch in _patches(build_dataset(split[side], cfg))
            ]

        assert set(seen["train"]).isdisjoint(seen["test"]), (
            f"fold {fold} put patches of one photograph on both sides"
        )
        for side in ("train", "test"):
            for index in set(seen[side]):
                assert seen[side].count(index) == PATCHES_PER_PHOTOGRAPH, (
                    f"photograph {index} is split across fold {fold}"
                )


# --- SPEC 0050: decode once per fit, not once per epoch --------------------


@requires_tensorflow
def test_decode_happens_once_per_fit(dish_version, dish_entries, monkeypatch):
    """The photograph is decoded once across two epochs, not once per epoch.

    Counted with a plain Python counter, which the traced `map` this pipeline
    used to be would have defeated: `from_generator` runs Python per element,
    so the count is exact rather than a count of traces.
    """
    from src import dataset as dataset_module

    decoded = []
    original = dataset_module._photograph_patches

    def counting(entry, measurement, cfg):
        decoded.append(entry["path"])
        return original(entry, measurement, cfg)

    monkeypatch.setattr(dataset_module, "_photograph_patches", counting)

    dataset = build_dataset(dish_entries, _config(dish_version))
    _patches(dataset)
    after_first = len(decoded)
    _patches(dataset)

    assert after_first == len(dish_entries), (
        f"{after_first} decode(s) for {len(dish_entries)} photographs in epoch one"
    )
    assert len(decoded) == after_first, (
        f"epoch two decoded {len(decoded) - after_first} photograph(s) again; "
        "the cache is missing, or sits after the augmentation"
    )


@requires_tensorflow
def test_augmentation_still_draws_each_epoch(dish_version, dish_entries):
    """Caching the decode must not freeze the augmentation to one draw."""
    cfg = _config(
        dish_version, augmentation={"horizontal_flip": True, "rotation_degrees": 25}
    )
    dataset = build_dataset(dish_entries, cfg, augment=True)

    first, second = _patches(dataset), _patches(dataset)

    assert any(
        not np.array_equal(a, b) for a, b in zip(first, second)
    ), "two epochs produced identical pixels; the augmentation is frozen"


@requires_tensorflow
def test_shuffle_order_differs_between_epochs(dish_version, dish_entries):
    """A cache upstream of `shuffle` replays one order forever."""
    dataset = build_dataset(dish_entries, _config(dish_version), shuffle=True)

    orders = [[_photograph_of(patch) for patch in _patches(dataset)] for _ in range(2)]

    assert orders[0] != orders[1], "the shuffle replayed one order"


@requires_tensorflow
def test_unshuffled_order_matches_the_entries(dish_version, dish_entries):
    """Without shuffling, the patches arrive photograph by photograph, in order.

    Asserted against the entries rather than against a second iteration of the
    same pipeline: comparing it to itself proves it is stable, which a frozen
    cache also is.
    """
    order = [
        _photograph_of(patch)
        for patch in _patches(build_dataset(dish_entries, _config(dish_version)))
    ]

    expected = [
        index
        for index in range(len(dish_entries))
        for _ in range(PATCHES_PER_PHOTOGRAPH)
    ]
    assert order == expected


@requires_tensorflow
def test_labels_stay_with_their_patches(dish_version, dish_entries):
    """Reordering moved batches; it must not separate a label from its patch."""
    cfg = _config(dish_version)

    for patch, label in _tensors(build_dataset(dish_entries, cfg, shuffle=True)):
        origin = dish_entries[_photograph_of(patch)]
        assert int(label.argmax()) == origin["label"]


@requires_tensorflow
def test_the_pipeline_yields_the_same_multiset(dish_version, dish_entries):
    """Shuffling moved patches between batches and lost none of them."""
    cfg = _config(dish_version)

    plain = sorted(
        _photograph_of(patch) for patch in _patches(build_dataset(dish_entries, cfg))
    )
    shuffled = sorted(
        _photograph_of(patch)
        for patch in _patches(build_dataset(dish_entries, cfg, shuffle=True))
    )

    assert plain == shuffled
    assert len(plain) == len(dish_entries) * PATCHES_PER_PHOTOGRAPH


# --- a refused photograph never enters a fold ------------------------------


def _partitionable_version(tmp_path, coarse=()):
    """Four sample groups per class, those in `coarse` photographed too coarsely."""
    photographs = []
    for index in range(8):
        texture_class = "Arenosa" if index < 4 else "Media"
        photographs.append(
            {
                "image": _photograph(SOIL_LEVELS[index % len(SOIL_LEVELS)], seed=index),
                "class": texture_class,
                "sample_id": f"sample-{index}",
                # A coarse one measures above the canonical, so reaching it
                # could only invent grain that was never photographed.
                "mm_per_px": CANONICAL * 2.0 if index in coarse else MEASURED,
            }
        )
    return _write_measured_version(tmp_path, photographs)


def test_a_photograph_the_patch_grid_refuses_never_enters_a_fold(tmp_path):
    """The fold manifest is the record of what a run trained on.

    Filtering when a fold's sides are assembled instead would leave the record
    naming photographs no run can use, and every later reader — the composition
    report, the audit, `evaluate.py` — would be counting images that were never
    scored.
    """
    root = _partitionable_version(tmp_path, coarse=(7,))
    coarse = _path(root, 7)

    fold_manifest = create_folds_for_config(_config(root), str(tmp_path / "splits"))

    listed = {
        image
        for record in fold_manifest["groups"].values()
        for image in record["images"]
    }
    assert coarse not in listed
    assert len(listed) == 7


def test_the_fold_manifest_records_what_the_patch_grid_refused(tmp_path):
    """Named and counted, because a photograph that vanishes silently is a
    dataset shrinking without anyone knowing which images went."""
    root = _partitionable_version(tmp_path, coarse=(7,))

    fold_manifest = create_folds_for_config(_config(root), str(tmp_path / "splits"))

    refused = fold_manifest["refused"]
    assert list(refused) == [_path(root, 7)]
    assert PatchRefusal.TOO_COARSE.value in refused[_path(root, 7)]
    assert fold_manifest["counts"]["refused_photographs"] == 1


def test_a_version_the_patch_grid_accepts_records_no_refusal(tmp_path):
    root = _partitionable_version(tmp_path)

    fold_manifest = create_folds_for_config(_config(root), str(tmp_path / "splits"))

    assert fold_manifest["refused"] == {}
    assert fold_manifest["counts"]["refused_photographs"] == 0
