"""Tests for TFLite export: model loads, runs inference, output is compatible."""

import json
import tempfile
from pathlib import Path

import numpy as np
import pytest
import tensorflow as tf

from src.config import _VALID_NORMALIZATIONS
from src.model import build_model
from src.export import _build_spec


@pytest.fixture
def model_and_tflite():
    """Build a MobileNetV2 model and export to TFLite in a temp directory."""
    cfg = {
        "classes": ["A", "B", "C"],
        "data": {"image_size": 224},
        "model": {"architecture": "mobilenetv2", "dropout": 0.0},
        "training": {"learning_rate": 0.001},
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
        },
        "export": {"quantization": "none", "output_dir": "models"},
    }

    model = build_model(cfg)

    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_bytes = converter.convert()

    tmp_dir = tempfile.mkdtemp()
    tflite_path = Path(tmp_dir) / "model.tflite"
    with open(tflite_path, "wb") as f:
        f.write(tflite_bytes)

    return model, tflite_path, cfg


def test_tflite_loads(model_and_tflite):
    """TFLite model file loads without error."""
    _, tflite_path, _ = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    assert interpreter is not None


def test_tflite_input_shape(model_and_tflite):
    """TFLite input shape matches expected (1, 224, 224, 3)."""
    _, tflite_path, _ = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    assert list(input_details[0]["shape"]) == [1, 224, 224, 3]


def test_tflite_output_shape(model_and_tflite):
    """TFLite output shape matches (1, num_classes)."""
    _, tflite_path, cfg = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()
    output_details = interpreter.get_output_details()
    num_classes = len(cfg["classes"])
    assert list(output_details[0]["shape"]) == [1, num_classes]


def test_tflite_inference_runs(model_and_tflite):
    """TFLite inference produces output without error."""
    _, tflite_path, _ = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])

    assert output.shape == (1, 3)
    assert output.dtype == np.float32


def test_tflite_output_probabilities(model_and_tflite):
    """TFLite output probabilities sum to ~1.0."""
    _, tflite_path, _ = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)
    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    output = interpreter.get_tensor(output_details[0]["index"])

    np.testing.assert_allclose(np.sum(output), 1.0, atol=1e-4)


def test_tflite_keras_parity(model_and_tflite):
    """TFLite output is close to Keras output (no quantization)."""
    model, tflite_path, _ = model_and_tflite
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    dummy = np.random.rand(1, 224, 224, 3).astype(np.float32)

    keras_out = model.predict(dummy, verbose=0)

    interpreter.set_tensor(input_details[0]["index"], dummy)
    interpreter.invoke()
    tflite_out = interpreter.get_tensor(output_details[0]["index"])

    np.testing.assert_allclose(keras_out, tflite_out, atol=1e-4)


def test_spec_json_structure_mobilenet(model_and_tflite):
    """spec.json for mobilenet_v2 has divide_255 normalization."""
    _, _, cfg = model_and_tflite
    spec = _build_spec(cfg, "v2")

    assert spec["version"] == "v2"
    assert spec["input"]["shape"] == [1, 224, 224, 3]
    assert spec["input"]["dtype"] == "float32"
    assert spec["input"]["normalization"]["method"] == "divide_255"
    assert "mean" not in spec["input"]["normalization"]
    assert "std" not in spec["input"]["normalization"]
    assert spec["output"]["shape"] == [1, 3]
    assert spec["output"]["dtype"] == "float32"
    assert spec["output"]["type"] == "probabilities"
    assert spec["classes"] == ["A", "B", "C"]


def test_spec_declares_divide_255_for_every_accepted_normalization():
    """Every normalization load_config accepts exports the same contract.

    This replaces `test_spec_json_structure_imagenet`, which asserted the export
    of a value the pipeline never implemented. The accepted set has one member
    today; enumerating it here means adding a second one without revisiting the
    export fails at this test rather than in a trained model.
    """
    for normalization in _VALID_NORMALIZATIONS:
        cfg = {
            "classes": ["A", "B"],
            "data": {"image_size": 224},
            "preprocessing": {
                "normalization": normalization,
                "bake_into_model": True,
            },
            "export": {"quantization": "none", "output_dir": "models"},
        }
        spec = _build_spec(cfg, "v1")

        assert spec["input"]["normalization"]["method"] == "divide_255", normalization
        assert "mean" not in spec["input"]["normalization"]
        assert "std" not in spec["input"]["normalization"]


def test_build_spec_raises_on_a_contract_the_graph_does_not_implement():
    """_build_spec refuses to declare a preprocessing the graph contradicts.

    `build_model` always applies Rescaling(2.0, -1.0). A config asking for it to
    be absent is already rejected by load_config; the export refuses too, so a
    hand-built config cannot produce a spec.json that disagrees with the graph.
    """
    cfg = {
        "classes": ["A", "B"],
        "data": {"image_size": 224},
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": False,
        },
        "export": {"quantization": "none", "output_dir": "models"},
    }
    with pytest.raises(ValueError, match="bake_into_model"):
        _build_spec(cfg, "v1")
