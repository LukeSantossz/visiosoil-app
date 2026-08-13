"""Tests for config loading and validation."""

import pytest
import yaml
import tempfile
from pathlib import Path

from src.config import load_config, resolve_paths


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
            "datasets_dir": "data/datasets",
            "dataset_version": "v1",
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


def test_imagenet_normalization_is_rejected(valid_config):
    """imagenet normalization is rejected even when mean and std are supplied.

    These two tests replace `test_imagenet_normalization_requires_mean_std` and
    `test_imagenet_normalization_with_mean_std`, which asserted that a complete
    imagenet configuration loads. It did load before this change, and the model
    it produced was wrong: `build_model` applies Rescaling(2.0, -1.0)
    unconditionally, so the backbone received the imagenet range mapped by
    2v - 1. SPEC 0034 removes the value rather than the layer, because the
    pipeline implements exactly one preprocessing contract.
    """
    valid_config["preprocessing"] = {
        "normalization": "imagenet",
        "mean": [0.485, 0.456, 0.406],
        "std": [0.229, 0.224, 0.225],
    }
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="mobilenet_v2"):
        load_config(path)


def test_imagenet_normalization_is_rejected_without_mean_std(valid_config):
    """imagenet is rejected as a value, not for its missing mean and std.

    Matching on the accepted value rather than on "mean" is what distinguishes
    the two rejections: the old code refused this config for the wrong reason,
    and a test matching "normalization" alone would have passed either way.
    """
    valid_config["preprocessing"]["normalization"] = "imagenet"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="mobilenet_v2"):
        load_config(path)


def test_normalization_rejection_does_not_offer_imagenet(valid_config):
    """The rejection message names the accepted value and only that one."""
    valid_config["preprocessing"]["normalization"] = "custom"
    path = _write_config(valid_config)
    with pytest.raises(ValueError) as excinfo:
        load_config(path)
    assert "mobilenet_v2" in str(excinfo.value)
    assert "imagenet" not in str(excinfo.value)


def test_mobilenet_v2_with_bake_into_model_loads(valid_config):
    """The one accepted preprocessing combination still loads.

    Renamed from `test_mobilenet_v2_normalization`, whose docstring described a
    contrast with imagenet that no longer exists. This is the only coverage of
    the accepted path, so it is a regression guard, not leftover.
    """
    path = _write_config(valid_config)
    cfg = load_config(path)
    assert cfg["preprocessing"]["normalization"] == "mobilenet_v2"
    assert cfg["preprocessing"]["bake_into_model"] is True


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


def test_deterministic_ops_defaults_to_enabled(valid_config):
    """Training runs on whatever hardware is present, so the safe default is the
    reproducible one. An exploratory run opts out explicitly and the choice is
    recorded in metrics.json, rather than depending on where it happened to run.
    """
    valid_config["training"].pop("deterministic_ops", None)
    path = _write_config(valid_config)
    assert load_config(path)["training"]["deterministic_ops"] is True


def test_deterministic_ops_must_be_a_boolean(valid_config):
    valid_config["training"]["deterministic_ops"] = "yes"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="deterministic_ops"):
        load_config(path)


def test_deterministic_ops_can_be_disabled(valid_config):
    valid_config["training"]["deterministic_ops"] = False
    path = _write_config(valid_config)
    assert load_config(path)["training"]["deterministic_ops"] is False


def test_brightness_range_beyond_the_layer_bounds_is_rejected(valid_config):
    """`preprocess` builds `factor=(lower - 1, upper - 1)`, and
    `RandomBrightness` requires each bound within [-1.0, 1.0]. So the config
    range must lie within [0.0, 2.0]; [0.0, 3.0] passes the ascending-numbers
    check but produces `factor=(-1.0, 2.0)`, which the layer rejects at
    construction — a failure that would surface only once training starts.
    """
    valid_config["augmentation"]["brightness_range"] = [0.0, 3.0]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="brightness_range"):
        load_config(path)


def test_brightness_range_at_the_layer_bounds_is_accepted(valid_config):
    valid_config["augmentation"]["brightness_range"] = [0.0, 2.0]
    path = _write_config(valid_config)
    assert load_config(path)["augmentation"]["brightness_range"] == [0.0, 2.0]


def test_dataset_version_is_required(valid_config):
    """A run that cannot name its dataset version cannot be reproduced."""
    del valid_config["data"]["dataset_version"]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="dataset_version"):
        load_config(path)


def test_datasets_dir_is_required(valid_config):
    """The version key is useless without the root it is a version of."""
    del valid_config["data"]["datasets_dir"]
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="datasets_dir"):
        load_config(path)


def test_dataset_version_must_be_v_prefixed_and_numbered(valid_config):
    """A version is an immutable directory name, so its shape is fixed."""
    valid_config["data"]["dataset_version"] = "latest"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="dataset_version"):
        load_config(path)


def test_dataset_version_rejects_a_zero_version(valid_config):
    """Versions start at v1, so v0 is a typo rather than a dataset."""
    valid_config["data"]["dataset_version"] = "v0"
    path = _write_config(valid_config)
    with pytest.raises(ValueError, match="dataset_version"):
        load_config(path)


def test_resolve_paths_resolves_the_datasets_dir(valid_config):
    """Every data path is resolved in one place, against the ml/ root."""
    path = _write_config(valid_config)
    cfg = resolve_paths(load_config(path))
    assert Path(cfg["data"]["datasets_dir"]).is_absolute()
    assert Path(cfg["data"]["datasets_dir"]).name == "datasets"
