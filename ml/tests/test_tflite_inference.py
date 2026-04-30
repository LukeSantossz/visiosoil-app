"""Tests for TFLite export: model loads, runs inference, output is compatible."""

import json
import tempfile
from pathlib import Path

import numpy as np
import pytest
import tensorflow as tf

from src.model import build_model
from src.export import _build_spec


@pytest.fixture
def model_and_tflite():
    """Build a small model and export to TFLite in a temp directory."""
    cfg = {
        "classes": ["A", "B", "C"],
        "data": {"image_size": 224},
        "model": {"architecture": "squeezenet", "dropout": 0.0},
        "training": {"learning_rate": 0.001},
        "preprocessing": {
            "normalization": "imagenet",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
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


def test_spec_json_structure(model_and_tflite):
    """spec.json has the required contract fields."""
    _, _, cfg = model_and_tflite
    spec = _build_spec(cfg, "v1")

    assert spec["version"] == "v1"
    assert spec["input"]["shape"] == [1, 224, 224, 3]
    assert spec["input"]["dtype"] == "float32"
    assert spec["input"]["normalization"]["method"] == "imagenet"
    assert len(spec["input"]["normalization"]["mean"]) == 3
    assert len(spec["input"]["normalization"]["std"]) == 3
    assert spec["output"]["shape"] == [1, 3]
    assert spec["output"]["dtype"] == "float32"
    assert spec["output"]["type"] == "probabilities"
    assert spec["classes"] == ["A", "B", "C"]
