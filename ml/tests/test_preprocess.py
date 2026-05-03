"""Tests for image preprocessing: shape, dtype, and value range."""

import numpy as np
import pytest
import tensorflow as tf

from src.preprocess import (
    normalize_imagenet,
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
            "rotation_range": 15,
            "brightness_range": [0.85, 1.15],
            "contrast_range": [0.9, 1.1],
            "zoom_range": [0.95, 1.05],
            "translation_range": 0.05,
        },
        "classes": ["A", "B", "C"],
        "training": {"batch_size": 4},
    }


@pytest.fixture
def sample_config_imagenet() -> dict:
    """Return a config for imagenet preprocessing (backward compat)."""
    return {
        "data": {"image_size": 224, "seed": 42},
        "preprocessing": {
            "normalization": "imagenet",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
        },
        "augmentation": {
            "horizontal_flip": True,
            "rotation_range": 20,
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


def test_normalize_imagenet_output_dtype(sample_image):
    """ImageNet normalization produces float32."""
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]
    normalized = normalize_imagenet(sample_image, mean, std)
    assert normalized.dtype == tf.float32


def test_normalize_imagenet_output_range(sample_image):
    """ImageNet normalized values fall within expected range."""
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]
    normalized = normalize_imagenet(sample_image, mean, std)
    values = normalized.numpy()
    assert values.min() >= -3.0, f"Min value {values.min()} too low"
    assert values.max() <= 3.0, f"Max value {values.max()} too high"


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


def test_preprocess_imagenet(sample_image, sample_config_imagenet):
    """Full preprocess pipeline with imagenet normalization."""
    result = preprocess(sample_image, sample_config_imagenet)
    assert result.shape == (224, 224, 3)
    assert result.dtype == tf.float32


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
