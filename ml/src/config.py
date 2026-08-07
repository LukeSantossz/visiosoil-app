"""Configuration loader and validator for the ML pipeline."""

import os
from pathlib import Path

import yaml


_REQUIRED_TOP_KEYS = {"project", "classes", "data", "preprocessing", "model", "training", "export"}
_REQUIRED_DATA_KEYS = {"raw_dir", "splits_dir", "image_size", "val_split", "test_split", "seed"}
_REQUIRED_PREPROCESSING_KEYS = {"normalization"}
_REQUIRED_MODEL_KEYS = {"architecture", "dropout"}
_REQUIRED_TRAINING_KEYS = {"epochs", "batch_size", "learning_rate"}
_VALID_ARCHITECTURES = {"mobilenetv2"}
_VALID_NORMALIZATIONS = {"imagenet", "mobilenet_v2"}
_VALID_QUANTIZATIONS = {"dynamic_range", "float16", "none"}

# Input size the pretrained weights of each architecture were trained at. Any
# other size loads without error and silently degrades transfer learning.
_ARCHITECTURE_IMAGE_SIZE = {"mobilenetv2": 224}

# Augmentation keys expressed as a [lower, upper] multiplicative range.
_RANGED_AUGMENTATION_KEYS = ("brightness_range", "contrast_range", "zoom_range")

# Defaults that were previously inline `.get()` calls in the modules that read
# them, where nothing validated the value and nothing declared the default.
OPTIONAL_MODEL_DEFAULTS = {"freeze_backbone": True}


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
    _apply_defaults(cfg)

    return cfg


def _apply_defaults(cfg: dict) -> None:
    """Fill declared optional defaults so readers never supply their own."""
    for key, value in OPTIONAL_MODEL_DEFAULTS.items():
        cfg["model"].setdefault(key, value)


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

    # A seed that is not a plain non-negative int changes seeding behaviour
    # without erroring. bool is an int subclass, so it is excluded explicitly.
    seed = data["seed"]
    if isinstance(seed, bool) or not isinstance(seed, int) or seed < 0:
        raise ValueError(f"data.seed must be a non-negative integer, got {seed!r}")

    # preprocessing
    pre = cfg["preprocessing"]
    missing_pre = _REQUIRED_PREPROCESSING_KEYS - set(pre.keys())
    if missing_pre:
        raise ValueError(f"Missing preprocessing keys: {missing_pre}")
    if pre["normalization"] not in _VALID_NORMALIZATIONS:
        raise ValueError(f"normalization must be one of {_VALID_NORMALIZATIONS}")

    # For imagenet normalization, mean and std are required
    if pre["normalization"] == "imagenet":
        for key in ("mean", "std"):
            if key not in pre:
                raise ValueError(f"preprocessing.{key} required for imagenet normalization")
            if not isinstance(pre[key], list) or len(pre[key]) != 3:
                raise ValueError(f"preprocessing.{key} must be a list of 3 floats")

    # bake_into_model is optional, defaults to False
    if "bake_into_model" in pre:
        if not isinstance(pre["bake_into_model"], bool):
            raise ValueError("preprocessing.bake_into_model must be a boolean")

    # `build_model` adds Rescaling(2.0, -1.0) unconditionally and never reads
    # this flag, while `export.py` does read it to declare the preprocessing
    # contract in spec.json. Declaring the rescaling absent while the graph
    # performs it is a train/serve skew produced by configuration alone.
    if pre["normalization"] == "mobilenet_v2" and not pre.get("bake_into_model", False):
        raise ValueError(
            "preprocessing.bake_into_model must be true for mobilenet_v2 "
            "normalization: build_model always applies the Rescaling layer"
        )

    # augmentation (optional section)
    aug = cfg.get("augmentation", {})
    if not isinstance(aug, dict):
        raise ValueError("'augmentation' must be a mapping")
    for key in _RANGED_AUGMENTATION_KEYS:
        if key not in aug:
            continue
        value = aug[key]
        valid = (
            isinstance(value, (list, tuple))
            and len(value) == 2
            and all(
                isinstance(v, (int, float)) and not isinstance(v, bool) for v in value
            )
            and value[0] < value[1]
        )
        if not valid:
            raise ValueError(
                f"augmentation.{key} must be two ascending numbers "
                f"[lower, upper], got {value!r}"
            )

    # Keras RandomContrast realizes [1 - min(factor), 1 + max(factor)]: it sorts
    # the pair, so the two sides cannot be set independently. An asymmetric
    # range would be silently approximated, which is the defect #81 reports.
    contrast = aug.get("contrast_range")
    if contrast is not None and abs((1.0 - contrast[0]) - (contrast[1] - 1.0)) > 1e-9:
        raise ValueError(
            f"augmentation.contrast_range must be symmetric about 1.0 "
            f"(RandomContrast cannot express an asymmetric range), got {contrast!r}"
        )

    # model
    model = cfg["model"]
    missing_model = _REQUIRED_MODEL_KEYS - set(model.keys())
    if missing_model:
        raise ValueError(f"Missing model keys: {missing_model}")
    if model["architecture"] not in _VALID_ARCHITECTURES:
        raise ValueError(f"architecture must be one of {_VALID_ARCHITECTURES}")
    if not (0 <= model["dropout"] < 1):
        raise ValueError("dropout must be between 0 and 1")

    expected_size = _ARCHITECTURE_IMAGE_SIZE.get(model["architecture"])
    if expected_size is not None and data["image_size"] != expected_size:
        raise ValueError(
            f"data.image_size must be {expected_size} for architecture "
            f"{model['architecture']}, got {data['image_size']}"
        )

    if "freeze_backbone" in model and not isinstance(model["freeze_backbone"], bool):
        raise ValueError("model.freeze_backbone must be a boolean")

    # Optional model fields
    if "unfreeze_at_epoch" in model:
        if not isinstance(model["unfreeze_at_epoch"], int) or model["unfreeze_at_epoch"] < 1:
            raise ValueError("model.unfreeze_at_epoch must be a positive integer")
    if "unfreeze_layers" in model:
        if not isinstance(model["unfreeze_layers"], int) or model["unfreeze_layers"] < 1:
            raise ValueError("model.unfreeze_layers must be a positive integer")

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

    # Optional training fields
    if "fine_tune_learning_rate" in training:
        if training["fine_tune_learning_rate"] <= 0:
            raise ValueError("fine_tune_learning_rate must be positive")
    if "class_weights" in training:
        if training["class_weights"] not in {"balanced", "none"}:
            raise ValueError("training.class_weights must be 'balanced' or 'none'")

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
