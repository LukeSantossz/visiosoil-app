"""Tests for config loading and validation."""

import pytest
import yaml
import tempfile
from pathlib import Path

from src.config import load_config


@pytest.fixture
def valid_config() -> dict:
    """Return a minimal valid config dict."""
    return {
        "project": {"name": "test", "version": 2},
        "classes": ["A", "B", "C"],
        "data": {
            "raw_dir": "data/raw",
            "splits_dir": "data/splits",
            "image_size": 224,
            "val_split": 0.15,
            "test_split": 0.15,
            "seed": 42,
        },
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
        },
        "augmentation": {
            "horizontal_flip": True,
            "vertical_flip": True,
            "rotation_range": 40,
        },
        "model": {
            "architecture": "mobilenetv2",
            "freeze_backbone": True,
            "dropout": 0.5,
            "unfreeze_at_epoch": 10,
            "unfreeze_layers": 50,
        },
        "training": {
            "epochs": 50,
            "batch_size": 32,
            "learning_rate": 0.001,
            "fine_tune_learning_rate": 0.00001,
            "class_weights": "balanced",
        },
        "export": {
            "quantization": "none",
            "output_dir": "models",
        },
    }


def _write_config(cfg: dict) -> str:
    """Write config dict to a temp YAML file and return its path."""
    tmp = tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False)
    yaml.dump(cfg, tmp)
    tmp.close()
    return tmp.name


def test_load_valid_config(valid_config):
    """Valid config loads without error."""
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["classes"] == ["A", "B", "C"]
    assert cfg["data"]["image_size"] == 224


def test_missing_top_key(valid_config):
    """Missing top-level key raises ValueError."""
    del valid_config["classes"]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="Missing top-level keys"):
        load_config(path)


def test_invalid_val_split(valid_config):
    """val_split outside (0, 1) raises ValueError."""
    valid_config["data"]["val_split"] = 1.5
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="val_split"):
        load_config(path)


def test_splits_sum_too_large(valid_config):
    """val_split + test_split >= 1 raises ValueError."""
    valid_config["data"]["val_split"] = 0.5
    valid_config["data"]["test_split"] = 0.5
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="val_split.*test_split"):
        load_config(path)


def test_invalid_architecture(valid_config):
    """Unknown architecture raises ValueError."""
    valid_config["model"]["architecture"] = "resnet50"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="architecture"):
        load_config(path)


def test_invalid_normalization(valid_config):
    """Unknown normalization raises ValueError."""
    valid_config["preprocessing"]["normalization"] = "custom"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="normalization"):
        load_config(path)


def test_missing_file():
    """Non-existent config file raises FileNotFoundError."""
    with pytest.raises(FileNotFoundError):
        load_config("/nonexistent/path/config.yaml")


def test_too_few_classes(valid_config):
    """Fewer than 2 classes raises ValueError."""
    valid_config["classes"] = ["A"]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="classes"):
        load_config(path)


def test_mobilenetv2_is_valid(valid_config):
    """mobilenetv2 is a valid architecture."""
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["model"]["architecture"] == "mobilenetv2"


def test_imagenet_normalization_requires_mean_std(valid_config):
    """imagenet normalization requires mean and std fields."""
    valid_config["preprocessing"]["normalization"] = "imagenet"
    # No mean/std provided
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="mean"):
        load_config(path)


def test_imagenet_normalization_with_mean_std(valid_config):
    """imagenet normalization works with mean and std."""
    valid_config["preprocessing"] = {
        "normalization": "imagenet",
        "mean": [0.485, 0.456, 0.406],
        "std": [0.229, 0.224, 0.225],
    }
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["preprocessing"]["normalization"] == "imagenet"


def test_mobilenet_v2_normalization(valid_config):
    """mobilenet_v2 normalization does not require mean/std."""
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["preprocessing"]["normalization"] == "mobilenet_v2"


def test_unfreeze_at_epoch_validation(valid_config):
    """unfreeze_at_epoch must be a positive integer."""
    valid_config["model"]["unfreeze_at_epoch"] = -1
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="unfreeze_at_epoch"):
        load_config(path)


def test_unfreeze_layers_validation(valid_config):
    """unfreeze_layers must be a positive integer."""
    valid_config["model"]["unfreeze_layers"] = 0
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="unfreeze_layers"):
        load_config(path)


def test_fine_tune_lr_validation(valid_config):
    """fine_tune_learning_rate must be positive."""
    valid_config["training"]["fine_tune_learning_rate"] = -0.001
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="fine_tune_learning_rate"):
        load_config(path)


def test_class_weights_validation(valid_config):
    """class_weights must be 'balanced' or 'none'."""
    valid_config["training"]["class_weights"] = "invalid"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="class_weights"):
        load_config(path)
