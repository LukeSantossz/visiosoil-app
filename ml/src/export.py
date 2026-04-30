"""Export CLI: converts Keras model to TFLite and generates spec.json."""

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

from .config import load_config, resolve_paths


def export(version: str, config_path: str | None = None) -> Path:
    """Export trained Keras model to TFLite with spec.json.

    Steps:
    1. Load Keras .h5 checkpoint.
    2. Convert to TFLite with configured quantization.
    3. Verify TFLite output matches Keras output.
    4. Generate spec.json (integration contract for Flutter InferenceService).

    Args:
        version: Model version string (e.g., "v1").
        config_path: Optional path to config.yaml.

    Returns:
        Path to the exported .tflite file.
    """
    cfg = load_config(config_path)
    cfg = resolve_paths(cfg)

    output_dir = Path(cfg["export"]["output_dir"]) / version
    h5_path = output_dir / "model.h5"
    tflite_path = output_dir / "model.tflite"

    if not h5_path.exists():
        raise FileNotFoundError(f"Model checkpoint not found: {h5_path}")

    # Load Keras model
    model = tf.keras.models.load_model(h5_path)

    # Convert to TFLite
    converter = tf.lite.TFLiteConverter.from_keras_model(model)

    quantization = cfg["export"].get("quantization", "dynamic_range")
    if quantization == "dynamic_range":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
    elif quantization == "float16":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.target_spec.supported_types = [tf.float16]
    # "none" — no quantization applied

    tflite_model = converter.convert()

    with open(tflite_path, "wb") as f:
        f.write(tflite_model)

    print(f"TFLite model saved to {tflite_path} ({len(tflite_model) / 1024:.1f} KB)")

    # Verify TFLite output
    _verify_tflite(model, tflite_path, cfg)

    # Generate spec.json
    spec = _build_spec(cfg, version)
    spec_path = output_dir / "spec.json"
    with open(spec_path, "w") as f:
        json.dump(spec, f, indent=2)

    print(f"spec.json saved to {spec_path}")

    return tflite_path


def _verify_tflite(keras_model: tf.keras.Model, tflite_path: Path, cfg: dict) -> None:
    """Verify TFLite model produces compatible output with Keras model.

    Args:
        keras_model: Original Keras model.
        tflite_path: Path to exported TFLite file.
        cfg: Configuration dictionary.
    """
    image_size = cfg["data"]["image_size"]
    dummy_input = np.random.rand(1, image_size, image_size, 3).astype(np.float32)

    # Keras prediction
    keras_pred = keras_model.predict(dummy_input, verbose=0)

    # TFLite prediction
    interpreter = tf.lite.Interpreter(model_path=str(tflite_path))
    interpreter.allocate_tensors()

    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()

    interpreter.set_tensor(input_details[0]["index"], dummy_input)
    interpreter.invoke()
    tflite_pred = interpreter.get_tensor(output_details[0]["index"])

    # Compare
    max_diff = float(np.max(np.abs(keras_pred - tflite_pred)))
    print(f"Keras vs TFLite max difference: {max_diff:.6f}")

    if max_diff > 0.01:
        print(f"WARNING: Large difference between Keras and TFLite outputs ({max_diff:.6f})")
    else:
        print("TFLite verification passed")


def _build_spec(cfg: dict, version: str) -> dict:
    """Build the spec.json integration contract.

    Args:
        cfg: Configuration dictionary.
        version: Model version string.

    Returns:
        Spec dictionary.
    """
    image_size = cfg["data"]["image_size"]
    num_classes = len(cfg["classes"])

    return {
        "version": version,
        "input": {
            "shape": [1, image_size, image_size, 3],
            "dtype": "float32",
            "normalization": {
                "method": cfg["preprocessing"]["normalization"],
                "mean": cfg["preprocessing"]["mean"],
                "std": cfg["preprocessing"]["std"],
            },
        },
        "output": {
            "shape": [1, num_classes],
            "dtype": "float32",
            "type": "probabilities",
        },
        "classes": cfg["classes"],
    }


def main():
    parser = argparse.ArgumentParser(description="Export soil classifier to TFLite")
    parser.add_argument("--version", type=str, default="v1", help="Model version (e.g., v1)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    export(args.version, args.config)


if __name__ == "__main__":
    main()
