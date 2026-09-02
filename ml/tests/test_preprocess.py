"""Tests for image preprocessing: shape, dtype, and value range."""

import numpy as np
import pytest

# The training stack is pinned to Python 3.12 and has no wheel for every
# interpreter this repository is developed on, so this module skips rather than
# failing to collect. In CI, where `ml/requirements.txt` is installed, it runs.
tf = pytest.importorskip("tensorflow")

from src import preprocess as preprocess_module  # noqa: E402
from src.preprocess import (  # noqa: E402
    normalize_mobilenet_v2,
    resize,
    preprocess,
    build_augmentation_layer,
)


@pytest.fixture
def sample_image() -> tf.Tensor:
    """Create a random 100x100 RGB image (uint8)."""
    return tf.constant(np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8))


@pytest.fixture
def sample_config_mobilenet() -> dict:
    """Return a config for mobilenet_v2 preprocessing."""
    return {
        "data": {"image_size": 224, "seed": 42},
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
        },
        "augmentation": {
            "horizontal_flip": True,
            "vertical_flip": False,
            "rotation_degrees": 15,
            "brightness_range": [0.85, 1.15],
            "contrast_range": [0.9, 1.1],
            "zoom_range": [0.95, 1.05],
            "translation_fraction": 0.05,
        },
        "classes": ["A", "B", "C"],
        "training": {"batch_size": 4},
    }


def test_resize_output_shape(sample_image):
    """Resize produces correct spatial dimensions."""
    resized = resize(sample_image, 224)
    assert resized.shape == (224, 224, 3)


def test_resize_dtype(sample_image):
    """Resize output is float32."""
    resized = resize(sample_image, 224)
    assert resized.dtype == tf.float32


def test_normalize_imagenet_is_gone():
    """The imagenet helper is not importable.

    A tested, exported helper reads as a supported contract. SPEC 0034 leaves
    one contract, so the helper that served the other is removed rather than
    kept as documented dead code.
    """
    assert not hasattr(preprocess_module, "normalize_imagenet")


def test_preprocess_rejects_imagenet_normalization(sample_image):
    """preprocess fails loudly on imagenet rather than silently normalizing."""
    cfg = {
        "data": {"image_size": 224},
        "preprocessing": {
            "normalization": "imagenet",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
        },
    }
    with pytest.raises(ValueError, match="imagenet"):
        preprocess(sample_image, cfg)


def test_normalize_mobilenet_v2_output_dtype(sample_image):
    """MobileNetV2 normalization produces float32."""
    normalized = normalize_mobilenet_v2(sample_image)
    assert normalized.dtype == tf.float32


def test_normalize_mobilenet_v2_output_range(sample_image):
    """MobileNetV2 normalization produces values in [0, 1]."""
    normalized = normalize_mobilenet_v2(sample_image)
    values = normalized.numpy()
    assert values.min() >= 0.0, f"Min value {values.min()} below 0"
    assert values.max() <= 1.0, f"Max value {values.max()} above 1"


def test_preprocess_mobilenet_v2(sample_image, sample_config_mobilenet):
    """Full preprocess pipeline with mobilenet_v2 normalization."""
    result = preprocess(sample_image, sample_config_mobilenet)
    assert result.shape == (224, 224, 3)
    assert result.dtype == tf.float32
    values = result.numpy()
    assert values.min() >= 0.0
    assert values.max() <= 1.0


def test_augmentation_layer_builds(sample_config_mobilenet):
    """Augmentation layer builds without error."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    assert isinstance(aug, tf.keras.Sequential)


def test_augmentation_preserves_shape(sample_config_mobilenet):
    """Augmentation preserves spatial dimensions."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    dummy = tf.random.uniform((2, 224, 224, 3))
    output = aug(dummy, training=True)
    assert output.shape == (2, 224, 224, 3)


def test_augmentation_no_config():
    """Empty augmentation config builds an empty layer."""
    aug = build_augmentation_layer({"augmentation": {}})
    assert isinstance(aug, tf.keras.Sequential)
    assert len(aug.layers) == 0


def test_augmentation_horizontal_flip_only(sample_config_mobilenet):
    """Only horizontal flip layer is included when vertical_flip is false."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    layer_types = [type(l).__name__ for l in aug.layers]
    assert layer_types.count("RandomFlip") == 1


def test_augmentation_contrast_layer(sample_config_mobilenet):
    """Contrast layer is included when configured."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    layer_types = [type(l).__name__ for l in aug.layers]
    assert "RandomContrast" in layer_types


def test_augmentation_translation_layer(sample_config_mobilenet):
    """Translation layer is included when configured."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    layer_types = [type(l).__name__ for l in aug.layers]
    assert "RandomTranslation" in layer_types


def test_augmentation_output_range_normalized_input(sample_config_mobilenet):
    """Augmented images from [0,1] input stay within [0,1] range."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    # Input in [0, 1] range (post-normalization)
    dummy = tf.random.uniform((16, 224, 224, 3), minval=0.0, maxval=1.0)
    output = aug(dummy, training=True)
    values = output.numpy()
    assert values.max() <= 1.01, f"Augmented max {values.max():.4f} exceeds [0,1] range"
    assert values.min() >= -0.01, f"Augmented min {values.min():.4f} below [0,1] range"


# --- SPEC 0032: both bounds are honoured, and every layer is seeded --------


def _brightness_deltas(cfg: dict, draws: int = 400) -> tuple[float, float]:
    """Observed additive delta range over a flat mid-grey image."""
    layer = build_augmentation_layer(cfg).layers[0]
    flat = tf.fill((1, 8, 8, 3), 0.5)
    deltas = [
        float(tf.reduce_mean(layer(flat, training=True)).numpy() - 0.5)
        for _ in range(draws)
    ]
    return min(deltas), max(deltas)


def _contrast_factors(cfg: dict, draws: int = 400) -> tuple[float, float]:
    """Observed contrast factor, recovered from how the value span scales."""
    layer = build_augmentation_layer(cfg).layers[0]
    half = tf.fill((1, 8, 4, 3), 0.25)
    other = tf.fill((1, 8, 4, 3), 0.75)
    image = tf.concat([half, other], axis=2)
    factors = []
    for _ in range(draws):
        out = layer(image, training=True).numpy()
        factors.append(float(out.max() - out.min()) / 0.5)
    return min(factors), max(factors)


def _only(key: str, value, seed: int = 42) -> dict:
    """A config whose augmentation section holds exactly one ranged key."""
    return {
        "data": {"image_size": 224, "seed": seed},
        "preprocessing": {"normalization": "mobilenet_v2", "bake_into_model": True},
        "augmentation": {key: value},
        "classes": ["A", "B", "C"],
        "training": {"batch_size": 4},
    }


def test_brightness_honours_both_bounds():
    low, high = _brightness_deltas(_only("brightness_range", [0.7, 1.15]))
    assert low == pytest.approx(-0.30, abs=0.02)
    assert high == pytest.approx(0.15, abs=0.02)


def test_contrast_spans_the_whole_configured_range():
    """A symmetric range is realized end to end, not only its upper half.

    Contrast cannot take an asymmetric range: RandomContrast realizes
    `[1 - min(factor), 1 + max(factor)]`, sorting the pair, so the two sides are
    not independently settable. `load_config` rejects an asymmetric range rather
    than approximate it; see `test_asymmetric_contrast_range_is_rejected`.
    """
    low, high = _contrast_factors(_only("contrast_range", [0.75, 1.25]))
    assert low == pytest.approx(0.75, abs=0.02)
    assert high == pytest.approx(1.25, abs=0.02)


def test_symmetric_brightness_range_is_unchanged():
    """Proves the fix is latent: today's config keeps today's distribution."""
    low, high = _brightness_deltas(_only("brightness_range", [0.85, 1.15]))
    assert low == pytest.approx(-0.15, abs=0.02)
    assert high == pytest.approx(0.15, abs=0.02)


def test_contrast_lower_bound_is_no_longer_discarded():
    """Unlike brightness, this one is a real behaviour change.

    `RandomContrast` expands a float `f` to `(0, f)`, so passing the radius as a
    float realized `[1.0, 1.1]` for a configured `[0.9, 1.1]`: contrast was only
    ever increased. The pair has to be passed explicitly.
    """
    low, high = _contrast_factors(_only("contrast_range", [0.9, 1.1]))
    assert low == pytest.approx(0.90, abs=0.02)
    assert high == pytest.approx(1.10, abs=0.02)


def test_float_contrast_factor_would_be_one_sided():
    """Pins the Keras behaviour this fix exists for, so a regression is loud."""
    layer = tf.keras.layers.RandomContrast(
        factor=0.1, value_range=(0.0, 1.0), seed=42
    )
    assert tuple(layer.factor) == (0, pytest.approx(0.1))


def test_every_augmentation_layer_is_seeded(sample_config_mobilenet):
    """A global seed does not reach a layer's own generator."""
    aug = build_augmentation_layer(sample_config_mobilenet)
    expected = sample_config_mobilenet["data"]["seed"]

    assert aug.layers, "no augmentation layers were built"
    for layer in aug.layers:
        assert getattr(layer, "seed", None) == expected, (
            f"{type(layer).__name__} was built without the configured seed"
        )


def test_augmentation_layers_read_the_renamed_keys(sample_config_mobilenet):
    """The rotation and translation layers come from the renamed scalar keys.

    Both keys default to "no augmentation" when absent, so a reader that still
    looked for `rotation_range` would build no rotation layer at all and raise
    nothing — which is why SPEC 0047 refuses the old name at the config
    boundary as well as asserting the new one here.

    The factor is checked too, not only the layer's presence: 15 degrees is
    15/360 of a full turn, and a divisor changed to 180 would still produce a
    `RandomRotation` and halve every rotation silently.
    """
    layers = build_augmentation_layer(sample_config_mobilenet).layers
    by_type = {type(layer).__name__: layer for layer in layers}

    assert "RandomRotation" in by_type, "the rotation layer was not built"
    assert "RandomTranslation" in by_type, "the translation layer was not built"

    # Keras normalises a scalar factor into the pair it spans, so the layer
    # reports (-f, f) rather than f. Both bounds are asserted: the conversion
    # is what this criterion is about, and reading only one of them would miss
    # a sign error.
    rotation = sample_config_mobilenet["augmentation"]["rotation_degrees"]
    turns = rotation / 360.0
    lower, upper = by_type["RandomRotation"].factor
    assert (lower, upper) == (pytest.approx(-turns), pytest.approx(turns))
    # Stated in the unit the config uses, so the assertion reads as the claim:
    # 15 degrees is a fifteen-degree rotation either way, not thirty.
    assert upper * 360.0 == pytest.approx(rotation)

    # Absent the renamed keys, neither layer exists. Asserted rather than
    # assumed, because it is what makes a silent fallback impossible to miss.
    without = {
        **sample_config_mobilenet,
        "augmentation": {"horizontal_flip": True},
    }
    reduced = {type(layer).__name__ for layer in build_augmentation_layer(without).layers}
    assert "RandomRotation" not in reduced
    assert "RandomTranslation" not in reduced
