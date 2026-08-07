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


# --- SPEC 0032: validations that stop a silently degraded run --------------


def test_image_size_must_match_the_architecture(valid_config):
    """MobileNetV2 pretrained weights expect 224; other sizes degrade silently."""
    valid_config["data"]["image_size"] = 128
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="image_size"):
        load_config(path)


def test_seed_must_be_a_non_negative_int(valid_config):
    for bad in (-1, 1.5, "42", True):
        valid_config["data"]["seed"] = bad
        path = _write_config(valid_config)
        with pytest.raises(ValueError, match="seed"):
            load_config(path)


def test_valid_seed_is_accepted(valid_config):
    valid_config["data"]["seed"] = 0
    path = _write_config(valid_config)
    assert load_config(path)["data"]["seed"] == 0


def test_augmentation_range_must_be_two_ascending_values(valid_config):
    for bad in ([0.9], [1.2, 0.8], [0.9, 1.0, 1.1], "0.9", [0.9, 0.9]):
        valid_config["augmentation"]["brightness_range"] = bad
        path = _write_config(valid_config)
        with pytest.raises(ValueError, match="brightness_range"):
            load_config(path)


def test_every_ranged_augmentation_key_is_validated(valid_config):
    for key in ("brightness_range", "contrast_range", "zoom_range"):
        valid_config["augmentation"] = {key: [1.3, 0.7]}
        path = _write_config(valid_config)
        with pytest.raises(ValueError, match=key):
            load_config(path)


def test_valid_augmentation_ranges_are_accepted(valid_config):
    valid_config["augmentation"] = {
        "brightness_range": [0.7, 1.15],
        "contrast_range": [0.9, 1.1],
        "zoom_range": [0.95, 1.05],
    }
    path = _write_config(valid_config)
    assert load_config(path)["augmentation"]["brightness_range"] == [0.7, 1.15]


def test_baked_rescaling_must_match_the_declared_contract(valid_config):
    """build_model rescales unconditionally; export.py reads this flag."""
    valid_config["preprocessing"]["bake_into_model"] = False
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="bake_into_model"):
        load_config(path)


def test_freeze_backbone_default_is_declared(valid_config):
    """The default belongs to config, not to a .get() inside model.py."""
    del valid_config["model"]["freeze_backbone"]
    path = _write_config(valid_config)
    assert load_config(path)["model"]["freeze_backbone"] is True


def test_freeze_backbone_must_be_a_boolean(valid_config):
    valid_config["model"]["freeze_backbone"] = "yes"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="freeze_backbone"):
        load_config(path)


def test_asymmetric_contrast_range_is_rejected(valid_config):
    """RandomContrast sorts its factor pair, so it cannot express one."""
    valid_config["augmentation"]["contrast_range"] = [0.7, 1.15]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="symmetric"):
        load_config(path)


def test_symmetric_contrast_range_is_accepted(valid_config):
    valid_config["augmentation"]["contrast_range"] = [0.85, 1.15]
    path = _write_config(valid_config)
    assert load_config(path)["augmentation"]["contrast_range"] == [0.85, 1.15]
