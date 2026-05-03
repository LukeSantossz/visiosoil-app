"""Tests for model architecture: output shape, probabilities, and build variants."""

import numpy as np
import pytest
import tensorflow as tf

from src.model import build_model, unfreeze_model


@pytest.fixture
def mobilenetv2_config() -> dict:
    """Config for MobileNetV2 model (uses weights=None for test speed)."""
    return {
        "classes": ["Arenosa", "Media", "Siltosa", "Muito Argilosa", "Argilosa"],
        "data": {"image_size": 224},
        "model": {
            "architecture": "mobilenetv2",
            "freeze_backbone": True,
            "dropout": 0.5,
            "unfreeze_at_epoch": 10,
            "unfreeze_layers": 50,
        },
        "training": {
            "learning_rate": 0.001,
            "fine_tune_learning_rate": 0.0001,
        },
    }


@pytest.fixture
def mobilenetv2_model(mobilenetv2_config) -> tf.keras.Model:
    """Build MobileNetV2 model once for reuse."""
    return build_model(mobilenetv2_config)


def test_output_shape(mobilenetv2_model):
    """Model output shape matches (batch_size, num_classes)."""
    dummy = np.random.rand(2, 224, 224, 3).astype(np.float32)
    output = mobilenetv2_model.predict(dummy, verbose=0)
    assert output.shape == (2, 5)


def test_output_probabilities_sum(mobilenetv2_model):
    """Output probabilities sum to approximately 1.0 per sample."""
    dummy = np.random.rand(4, 224, 224, 3).astype(np.float32)
    output = mobilenetv2_model.predict(dummy, verbose=0)
    sums = np.sum(output, axis=1)
    np.testing.assert_allclose(sums, 1.0, atol=1e-5)


def test_output_non_negative(mobilenetv2_model):
    """All output probabilities are non-negative."""
    dummy = np.random.rand(2, 224, 224, 3).astype(np.float32)
    output = mobilenetv2_model.predict(dummy, verbose=0)
    assert np.all(output >= 0)


def test_output_dtype(mobilenetv2_model):
    """Output dtype is float32."""
    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    output = mobilenetv2_model.predict(dummy, verbose=0)
    assert output.dtype == np.float32


def test_model_name(mobilenetv2_model):
    """Model name reflects architecture."""
    assert "mobilenetv2" in mobilenetv2_model.name


def test_rescaling_layer_present(mobilenetv2_model):
    """Model contains a Rescaling layer."""
    layer_names = [layer.name for layer in mobilenetv2_model.layers]
    assert "rescaling" in layer_names


def test_two_class_model():
    """Model builds with minimum 2 classes."""
    cfg = {
        "classes": ["A", "B"],
        "data": {"image_size": 224},
        "model": {"architecture": "mobilenetv2", "dropout": 0.0},
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


def test_unfreeze_model(mobilenetv2_model, mobilenetv2_config):
    """unfreeze_model unfreezes layers and recompiles."""
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    # After unfreezing, model should still produce valid output
    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    output = model.predict(dummy, verbose=0)
    assert output.shape == (1, 5)
    np.testing.assert_allclose(np.sum(output), 1.0, atol=1e-5)


def test_unfreeze_model_layers_trainable(mobilenetv2_model, mobilenetv2_config):
    """unfreeze_model sets the last N backbone layers to trainable."""
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    unfreeze_layers = mobilenetv2_config["model"]["unfreeze_layers"]

    # Find backbone
    backbone = None
    for layer in model.layers:
        if hasattr(layer, "layers") and "mobilenetv2" in layer.name.lower():
            backbone = layer
            break

    assert backbone is not None, "MobileNetV2 backbone not found"
    assert backbone.trainable is True

    # Last N layers should be trainable
    trainable_tail = [l for l in backbone.layers[-unfreeze_layers:] if l.trainable]
    assert len(trainable_tail) > 0, "No layers unfrozen in backbone tail"

    # Earlier layers should be frozen
    frozen_head = [l for l in backbone.layers[:-unfreeze_layers] if not l.trainable]
    assert len(frozen_head) > 0, "No layers frozen in backbone head"
