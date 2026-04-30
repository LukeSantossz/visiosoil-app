"""Tests for model architecture: output shape, probabilities, and build variants."""

import numpy as np
import pytest
import tensorflow as tf

from src.model import build_model


@pytest.fixture
def squeezenet_config() -> dict:
    """Config for SqueezeNet model."""
    return {
        "classes": ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"],
        "data": {"image_size": 224},
        "model": {
            "architecture": "squeezenet",
            "freeze_backbone": True,
            "dropout": 0.3,
        },
        "training": {"learning_rate": 0.001},
    }


@pytest.fixture
def squeezenet_model(squeezenet_config) -> tf.keras.Model:
    """Build SqueezeNet model once for reuse."""
    return build_model(squeezenet_config)


def test_output_shape(squeezenet_model):
    """Model output shape matches (batch_size, num_classes)."""
    dummy = np.random.rand(2, 224, 224, 3).astype(np.float32)
    output = squeezenet_model.predict(dummy, verbose=0)
    assert output.shape == (2, 5)


def test_output_probabilities_sum(squeezenet_model):
    """Output probabilities sum to approximately 1.0 per sample."""
    dummy = np.random.rand(4, 224, 224, 3).astype(np.float32)
    output = squeezenet_model.predict(dummy, verbose=0)
    sums = np.sum(output, axis=1)
    np.testing.assert_allclose(sums, 1.0, atol=1e-5)


def test_output_non_negative(squeezenet_model):
    """All output probabilities are non-negative."""
    dummy = np.random.rand(2, 224, 224, 3).astype(np.float32)
    output = squeezenet_model.predict(dummy, verbose=0)
    assert np.all(output >= 0)


def test_output_dtype(squeezenet_model):
    """Output dtype is float32."""
    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    output = squeezenet_model.predict(dummy, verbose=0)
    assert output.dtype == np.float32


def test_model_name(squeezenet_model):
    """Model name reflects architecture."""
    assert "squeezenet" in squeezenet_model.name


def test_two_class_model():
    """Model builds with minimum 2 classes."""
    cfg = {
        "classes": ["A", "B"],
        "data": {"image_size": 224},
        "model": {"architecture": "squeezenet", "dropout": 0.0},
        "training": {"learning_rate": 0.001},
    }
    model = build_model(cfg)
    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    output = model.predict(dummy, verbose=0)
    assert output.shape == (1, 2)


def test_invalid_architecture_raises():
    """Unknown architecture raises ValueError."""
    cfg = {
        "classes": ["A", "B"],
        "data": {"image_size": 224},
        "model": {"architecture": "unknown_net", "dropout": 0.0},
        "training": {"learning_rate": 0.001},
    }
    with pytest.raises(ValueError, match="Unknown architecture"):
        build_model(cfg)
