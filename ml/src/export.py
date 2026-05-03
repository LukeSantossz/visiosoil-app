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
    1. Load Keras .keras checkpoint.
    2. Convert to TFLite with configured quantization.
    3. Verify TFLite output matches Keras output.
    4. Generate spec.json (integration contract for Flutter InferenceService).

    Args:
        version: Model version string (e.g., "v2").
        config_path: Optional path to config.yaml.

    Returns:
        Path to the exported .tflite file.
    """
    cfg = load_config(config_path)
    cfg = resolve_paths(cfg)

    output_dir = Path(cfg["export"]["output_dir"]) / version
    tflite_path = output_dir / "model.tflite"

    # Try .keras first, then .h5 for backward compatibility
    keras_path = output_dir / "model.keras"
    h5_path = output_dir / "model.h5"

    if keras_path.exists():
        model_path = keras_path
    elif h5_path.exists():
        model_path = h5_path
    else:
        raise FileNotFoundError(
            f"Model checkpoint not found: tried {keras_path} and {h5_path}"
        )

    # Load Keras model
    model = tf.keras.models.load_model(model_path)

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

    The spec tells the Flutter app how to prepare input for the model.
    With mobilenet_v2 normalization + bake_into_model, the app only
    needs to divide by 255 (the model handles [-1,1] internally).

    Args:
        cfg: Configuration dictionary.
        version: Model version string.

    Returns:
        Spec dictionary.
    """
    image_size = cfg["data"]["image_size"]
    num_classes = len(cfg["classes"])
    normalization = cfg["preprocessing"]["normalization"]
    bake_into_model = cfg["preprocessing"].get("bake_into_model", False)

    # Determine normalization method for the app
    if normalization == "mobilenet_v2" and bake_into_model:
        norm_spec = {
            "method": "divide_255",
        }
    elif normalization == "imagenet":
        norm_spec = {
            "method": "imagenet",
            "mean": cfg["preprocessing"]["mean"],
            "std": cfg["preprocessing"]["std"],
        }
    else:
        norm_spec = {
            "method": normalization,
        }

    return {
        "version": version,
        "input": {
            "shape": [1, image_size, image_size, 3],
            "dtype": "float32",
            "normalization": norm_spec,
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
    parser.add_argument("--version", type=str, default="v1", help="Model version (e.g., v2)")
    parser.add_argument("--config", type=str, default=None, help="Path to config.yaml")
    args = parser.parse_args()

    export(args.version, args.config)


if __name__ == "__main__":
    main()
