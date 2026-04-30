"""Tests for image preprocessing: shape, dtype, and value range."""

import numpy as np
import pytest
import tensorflow as tf

from src.preprocess import normalize_imagenet, resize, preprocess, build_augmentation_layer


@pytest.fixture
def sample_image() -> tf.Tensor:
    """Create a random 100x100 RGB image (uint8)."""
    return tf.constant(np.random.randint(0, 256, (100, 100, 3), dtype=np.uint8))


@pytest.fixture
def sample_config() -> dict:
    """Return a minimal config for preprocessing tests."""
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
            "brightness_range": [0.8, 1.2],
            "zoom_range": [0.9, 1.1],
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


def test_normalize_output_dtype(sample_image):
    """Normalization produces float32."""
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]
    normalized = normalize_imagenet(sample_image, mean, std)
    assert normalized.dtype == tf.float32


def test_normalize_output_range(sample_image):
    """Normalized values fall within expected ImageNet range."""
    mean = [0.485, 0.456, 0.406]
    std = [0.229, 0.224, 0.225]
    normalized = normalize_imagenet(sample_image, mean, std)
    values = normalized.numpy()
    # ImageNet normalized range: approximately [-2.2, 2.7]
    assert values.min() >= -3.0, f"Min value {values.min()} too low"
    assert values.max() <= 3.0, f"Max value {values.max()} too high"


def test_preprocess_full_pipeline(sample_image, sample_config):
    """Full preprocess pipeline produces correct shape and dtype."""
    result = preprocess(sample_image, sample_config)
    assert result.shape == (224, 224, 3)
    assert result.dtype == tf.float32


def test_augmentation_layer_builds(sample_config):
    """Augmentation layer builds without error."""
    aug = build_augmentation_layer(sample_config)
    assert isinstance(aug, tf.keras.Sequential)


def test_augmentation_preserves_shape(sample_config):
    """Augmentation preserves spatial dimensions."""
    aug = build_augmentation_layer(sample_config)
    dummy = tf.random.uniform((2, 224, 224, 3))
    output = aug(dummy, training=True)
    assert output.shape == (2, 224, 224, 3)


def test_augmentation_no_config():
    """Empty augmentation config builds an empty layer."""
    aug = build_augmentation_layer({"augmentation": {}})
    assert isinstance(aug, tf.keras.Sequential)
    assert len(aug.layers) == 0
