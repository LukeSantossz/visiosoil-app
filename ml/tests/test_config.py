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
        "project": {"name": "test", "version": 1},
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
            "normalization": "imagenet",
            "mean": [0.485, 0.456, 0.406],
            "std": [0.229, 0.224, 0.225],
        },
        "augmentation": {
            "horizontal_flip": True,
            "rotation_range": 20,
        },
        "model": {
            "architecture": "squeezenet",
            "freeze_backbone": True,
            "dropout": 0.3,
        },
        "training": {
            "epochs": 50,
            "batch_size": 32,
            "learning_rate": 0.001,
        },
        "export": {
            "quantization": "dynamic_range",
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


def test_mobilenetv2_architecture(valid_config):
    """mobilenetv2 is a valid architecture."""
    valid_config["model"]["architecture"] = "mobilenetv2"
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["model"]["architecture"] == "mobilenetv2"
