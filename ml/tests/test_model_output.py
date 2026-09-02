"""Tests for model architecture: output shape, probabilities, and build variants."""

import numpy as np
import pytest

# The training stack is pinned to Python 3.12 and has no wheel for every
# interpreter this repository is developed on, so this module skips rather than
# failing to collect. In CI, where `ml/requirements.txt` is installed, it runs.
tf = pytest.importorskip("tensorflow")

from src.model import build_model, fine_tune_report, unfreeze_model  # noqa: E402


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


def test_rescaling_maps_unit_range_to_signed_unit_range(mobilenetv2_model):
    """The Rescaling layer implements the contract spec.json declares.

    spec.json declares `divide_255`, which means the app hands the model input
    in [0, 1] and the graph maps it to [-1, 1]. Asserted on the layer itself,
    not on the configuration, because the configuration is what was wrong.
    """
    rescaling = mobilenetv2_model.get_layer("rescaling")
    assert rescaling.scale == 2.0
    assert rescaling.offset == -1.0


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


def _backbone(model):
    """The MobileNetV2 sub-model, found the way `unfreeze_model` finds it."""
    for layer in model.layers:
        if hasattr(layer, "layers") and "mobilenetv2" in layer.name.lower():
            return layer
    raise AssertionError("MobileNetV2 backbone not found")


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


def test_unfreeze_leaves_no_backbone_batch_norm_trainable(
    mobilenetv2_model, mobilenetv2_config
):
    """No BatchNormalization layer inside the backbone is trainable afterwards.

    A trainable BatchNormalization layer runs in training mode during `fit` and
    overwrites its ImageNet moving statistics with statistics estimated from
    this dataset, which was photographed on one rig under one lighting
    condition. The damage is done by the forward pass rather than by the
    optimizer, so no learning rate governs it.
    """
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    backbone = _backbone(model)

    batch_norms = [
        layer
        for layer in backbone.layers
        if isinstance(layer, tf.keras.layers.BatchNormalization)
    ]
    trainable = [layer.name for layer in batch_norms if layer.trainable]
    assert trainable == [], (
        f"{len(trainable)} backbone BatchNormalization layer(s) are trainable "
        f"after unfreezing: {trainable}"
    )


def test_the_backbone_carries_batch_norm_layers_to_freeze(mobilenetv2_model):
    """The assertion above is not vacuous.

    If a future Keras stops building MobileNetV2 with BatchNormalization layers,
    or renames the class, the test that no backbone BatchNormalization layer is
    trainable would pass over an empty list while checking nothing. This is the
    companion that fails instead, and it is a test of its own rather than a line
    inside that one so that the criterion has something named after it.
    """
    backbone = _backbone(mobilenetv2_model)
    batch_norms = [
        layer
        for layer in backbone.layers
        if isinstance(layer, tf.keras.layers.BatchNormalization)
    ]
    assert batch_norms, "the backbone carries no BatchNormalization layers"


def test_unfreeze_leaves_the_head_batch_norm_trainable(
    mobilenetv2_model, mobilenetv2_config
):
    """The classification head's own BatchNormalization is untouched.

    `build_model` places one after the pooling layer. It has no pretrained
    statistics to protect — it was initialized on this dataset — so freezing it
    would be a different change from the one this fix makes, and a fix that
    reached it would be over-broad.
    """
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    head_batch_norms = [
        layer
        for layer in model.layers
        if isinstance(layer, tf.keras.layers.BatchNormalization)
    ]
    assert head_batch_norms, "the head carries no BatchNormalization layer"
    assert all(layer.trainable for layer in head_batch_norms)


def test_unfreeze_keeps_the_declared_layer_count(
    mobilenetv2_model, mobilenetv2_config
):
    """Freezing the BatchNormalization layers does not change what was unfrozen.

    Every non-BatchNormalization layer in the tail the config names is still
    trainable, and nothing outside that tail became trainable, so the fix is
    confined to the layer type it is about.
    """
    unfreeze_layers = mobilenetv2_config["model"]["unfreeze_layers"]
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    backbone = _backbone(model)

    tail = backbone.layers[-unfreeze_layers:]
    head = backbone.layers[:-unfreeze_layers]
    non_batch_norm_tail = [
        layer
        for layer in tail
        if not isinstance(layer, tf.keras.layers.BatchNormalization)
    ]

    assert len(non_batch_norm_tail) < len(tail), "no BatchNormalization in the tail"
    assert [layer.name for layer in non_batch_norm_tail if not layer.trainable] == []
    assert [layer.name for layer in head if layer.trainable] == []


def test_fine_tune_report_counts_the_model_not_the_config(
    mobilenetv2_model, mobilenetv2_config
):
    """The report describes the model, so a change to `unfreeze_model` shows up.

    Counted off the model rather than restated from the config: the config
    records the intent, and this records the outcome.
    """
    before = fine_tune_report(mobilenetv2_model)
    model = unfreeze_model(mobilenetv2_model, mobilenetv2_config)
    after = fine_tune_report(model)

    assert after["backbone_unfrozen"] is True
    assert after["trainable_backbone_layers"] > 0
    assert after["trainable_batch_norm_layers"] == 0
    assert after["batch_norm_layers"] == before["batch_norm_layers"] > 0
    assert after["trainable_parameters"] > before["trainable_parameters"]
    assert (
        after["trainable_parameters"] + after["non_trainable_parameters"]
        == model.count_params()
    )


def test_fine_tune_report_records_a_backbone_that_never_unfroze(mobilenetv2_model):
    """A fold whose refit never reached phase two is a real outcome, not an error.

    The nested epoch selection can choose fewer epochs than `unfreeze_at_epoch`,
    in which case `unfreeze_model` is never called and the backbone is still
    frozen when the fold's predictions are made. The record has to say so, or a
    reader comparing two folds cannot tell a protected backbone from one that
    was never fine-tuned at all.
    """
    report = fine_tune_report(mobilenetv2_model)

    assert report["backbone_unfrozen"] is False
    assert report["trainable_backbone_layers"] == 0
    assert report["trainable_batch_norm_layers"] == 0
    assert report["batch_norm_layers"] > 0
