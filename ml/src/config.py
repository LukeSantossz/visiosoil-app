"""Configuration loader and validator for the ML pipeline."""

import os
from pathlib import Path

import yaml


_REQUIRED_TOP_KEYS = {"project", "classes", "data", "preprocessing", "model", "training", "export"}
_REQUIRED_DATA_KEYS = {"raw_dir", "splits_dir", "image_size", "val_split", "test_split", "seed"}
_REQUIRED_PREPROCESSING_KEYS = {"normalization", "mean", "std"}
_REQUIRED_MODEL_KEYS = {"architecture", "dropout"}
_REQUIRED_TRAINING_KEYS = {"epochs", "batch_size", "learning_rate"}
_VALID_ARCHITECTURES = {"squeezenet", "mobilenetv2"}
_VALID_NORMALIZATIONS = {"imagenet"}
_VALID_QUANTIZATIONS = {"dynamic_range", "float16", "none"}


def _get_config_path() -> Path:
    """Return the default config.yaml path relative to the ml/ directory."""
    return Path(__file__).resolve().parent.parent / "config.yaml"


def load_config(path: str | None = None) -> dict:
    """Load and validate config.yaml.

    Args:
        path: Optional path to config file. Defaults to ml/config.yaml.

    Returns:
        Validated configuration dictionary.

    Raises:
        FileNotFoundError: If config file does not exist.
        ValueError: If config is invalid.
    """
    config_path = Path(path) if path else _get_config_path()

    if not config_path.exists():
        raise FileNotFoundError(f"Config file not found: {config_path}")

    with open(config_path, "r") as f:
        cfg = yaml.safe_load(f)

    _validate(cfg)

    return cfg


def _validate(cfg: dict) -> None:
    """Validate config structure and values."""
    if not isinstance(cfg, dict):
        raise ValueError("Config must be a YAML mapping")

    missing_top = _REQUIRED_TOP_KEYS - set(cfg.keys())
    if missing_top:
        raise ValueError(f"Missing top-level keys: {missing_top}")

    # classes
    classes = cfg["classes"]
    if not isinstance(classes, list) or len(classes) < 2:
        raise ValueError("'classes' must be a list with at least 2 entries")

    # data
    data = cfg["data"]
    missing_data = _REQUIRED_DATA_KEYS - set(data.keys())
    if missing_data:
        raise ValueError(f"Missing data keys: {missing_data}")

    if not (0 < data["val_split"] < 1):
        raise ValueError("val_split must be between 0 and 1")
    if not (0 < data["test_split"] < 1):
        raise ValueError("test_split must be between 0 and 1")
    if data["val_split"] + data["test_split"] >= 1:
        raise ValueError("val_split + test_split must be less than 1")
    if data["image_size"] < 32:
        raise ValueError("image_size must be at least 32")

    # preprocessing
    pre = cfg["preprocessing"]
    missing_pre = _REQUIRED_PREPROCESSING_KEYS - set(pre.keys())
    if missing_pre:
        raise ValueError(f"Missing preprocessing keys: {missing_pre}")
    if pre["normalization"] not in _VALID_NORMALIZATIONS:
        raise ValueError(f"normalization must be one of {_VALID_NORMALIZATIONS}")
    for key in ("mean", "std"):
        if not isinstance(pre[key], list) or len(pre[key]) != 3:
            raise ValueError(f"preprocessing.{key} must be a list of 3 floats")

    # model
    model = cfg["model"]
    missing_model = _REQUIRED_MODEL_KEYS - set(model.keys())
    if missing_model:
        raise ValueError(f"Missing model keys: {missing_model}")
    if model["architecture"] not in _VALID_ARCHITECTURES:
        raise ValueError(f"architecture must be one of {_VALID_ARCHITECTURES}")
    if not (0 <= model["dropout"] < 1):
        raise ValueError("dropout must be between 0 and 1")

    # training
    training = cfg["training"]
    missing_training = _REQUIRED_TRAINING_KEYS - set(training.keys())
    if missing_training:
        raise ValueError(f"Missing training keys: {missing_training}")
    if training["epochs"] < 1:
        raise ValueError("epochs must be at least 1")
    if training["batch_size"] < 1:
        raise ValueError("batch_size must be at least 1")
    if training["learning_rate"] <= 0:
        raise ValueError("learning_rate must be positive")

    # export
    export = cfg["export"]
    quantization = export.get("quantization", "dynamic_range")
    if quantization not in _VALID_QUANTIZATIONS:
        raise ValueError(f"quantization must be one of {_VALID_QUANTIZATIONS}")


def resolve_paths(cfg: dict) -> dict:
    """Resolve relative data paths to absolute paths based on ml/ root.

    Args:
        cfg: Configuration dictionary.

    Returns:
        Config with absolute paths in data section.
    """
    ml_root = Path(__file__).resolve().parent.parent
    cfg = cfg.copy()
    cfg["data"] = cfg["data"].copy()
    cfg["data"]["raw_dir"] = str(ml_root / cfg["data"]["raw_dir"])
    cfg["data"]["splits_dir"] = str(ml_root / cfg["data"]["splits_dir"])
    cfg["export"] = cfg["export"].copy()
    cfg["export"]["output_dir"] = str(ml_root / cfg["export"]["output_dir"])
    return cfg
