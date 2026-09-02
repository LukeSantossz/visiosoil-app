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
        "project": {"name": "test"},
        "classes": ["A", "B", "C"],
        "data": {
            "raw_dir": "data/raw",
            "splits_dir": "data/splits",
            "image_size": 224,
            "seed": 42,
            "datasets_dir": "data/datasets",
            "dataset_version": "v1",
        },
        "evaluation": {
            "k": 5,
            "repeats": 5,
            "inner_k": 4,
            "alpha": 0.05,
            "power": 0.8,
            "contrasts": [],
        },
        "preprocessing": {
            "normalization": "mobilenet_v2",
            "bake_into_model": True,
        },
        "augmentation": {
            "horizontal_flip": True,
            "vertical_flip": True,
            "rotation_degrees": 40,
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


# --- SPEC 0042: the evaluation protocol is configuration ---------------------


def test_single_split_path_is_removed(valid_config):
    """A config still carrying the split fractions is refused, naming them."""
    valid_config["data"]["val_split"] = 0.15
    valid_config["data"]["test_split"] = 0.15
    path = _write_config(valid_config)

    with pytest.raises(ValueError) as raised:
        load_config(path)

    message = str(raised.value)
    assert "val_split" in message
    assert "test_split" in message
    assert "evaluation" in message


def test_a_config_carrying_only_one_stale_fraction_is_still_refused(valid_config):
    """Half a migration is the case a set-difference check would miss."""
    valid_config["data"]["test_split"] = 0.15
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="test_split"):
        load_config(path)


def test_the_evaluation_block_is_required(valid_config):
    del valid_config["evaluation"]
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="evaluation"):
        load_config(path)


def test_every_evaluation_key_is_required(valid_config):
    for key in ("k", "repeats", "inner_k", "alpha", "power", "contrasts"):
        config = {**valid_config, "evaluation": dict(valid_config["evaluation"])}
        del config["evaluation"][key]
        path = _write_config(config)

        with pytest.raises(ValueError, match=key):
            load_config(path)


def test_k_below_two_is_rejected(valid_config):
    valid_config["evaluation"]["k"] = 1
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="evaluation.k"):
        load_config(path)


def test_inner_k_below_two_is_rejected(valid_config):
    """One inner fold is not a selection set; it is the training set again."""
    valid_config["evaluation"]["inner_k"] = 1
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="evaluation.inner_k"):
        load_config(path)


def test_repeats_below_one_is_rejected(valid_config):
    valid_config["evaluation"]["repeats"] = 0
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="evaluation.repeats"):
        load_config(path)


def test_alpha_and_power_must_lie_in_the_unit_interval(valid_config):
    for key in ("alpha", "power"):
        config = {**valid_config, "evaluation": dict(valid_config["evaluation"])}
        config["evaluation"][key] = 1.0
        path = _write_config(config)

        with pytest.raises(ValueError, match=f"evaluation.{key}"):
            load_config(path)


def test_a_contrast_must_name_two_distinct_arms(valid_config):
    valid_config["evaluation"]["contrasts"] = [
        {"name": "self", "arms": ["cnn", "cnn"], "family": "primary"}
    ]
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="two distinct arms"):
        load_config(path)


def test_a_contrast_must_declare_a_known_family(valid_config):
    valid_config["evaluation"]["contrasts"] = [
        {"name": "c", "arms": ["a", "b"], "family": "exploratory"}
    ]
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="family"):
        load_config(path)


def test_only_one_secondary_contrast_may_be_registered(valid_config):
    """ADR 0020 registers one named secondary; two is a family, uncorrected."""
    valid_config["evaluation"]["contrasts"] = [
        {"name": "one", "arms": ["a", "b"], "family": "secondary"},
        {"name": "two", "arms": ["a", "c"], "family": "secondary"},
    ]
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="one secondary"):
        load_config(path)


def test_two_contrasts_may_not_share_a_name(valid_config):
    valid_config["evaluation"]["contrasts"] = [
        {"name": "same", "arms": ["a", "b"], "family": "primary"},
        {"name": "same", "arms": ["a", "c"], "family": "primary"},
    ]
    path = _write_config(valid_config)

    with pytest.raises(ValueError, match="same"):
        load_config(path)


def test_a_registered_family_of_contrasts_is_accepted(valid_config):
    valid_config["evaluation"]["contrasts"] = [
        {"name": "cnn_vs_control", "arms": ["cnn", "control"], "family": "primary"},
        {"name": "cnn_vs_descriptors", "arms": ["cnn", "lbp"], "family": "secondary"},
    ]
    path = _write_config(valid_config)

    cfg = load_config(path)

    assert [c["name"] for c in cfg["evaluation"]["contrasts"]] == [
        "cnn_vs_control",
        "cnn_vs_descriptors",
    ]


def test_the_shipped_config_declares_the_protocol_ADR_0020_fixed():
    """k, R and the inner fold count are the decision, not a default."""
    cfg = load_config()

    assert cfg["evaluation"]["k"] == 5
    assert cfg["evaluation"]["repeats"] == 5
    assert cfg["evaluation"]["inner_k"] == 4
    assert cfg["evaluation"]["alpha"] == 0.05
    assert cfg["evaluation"]["power"] == 0.8
    assert "val_split" not in cfg["data"]
    assert "test_split" not in cfg["data"]


# --- SPEC 0047: keys that mean what they say -------------------------------


def test_scalar_augmentation_keys_carry_no_range_suffix():
    """The `_range` suffix marks exactly the keys that hold a `[lo, hi]` pair.

    The split was hardcoded in `_RANGED_AUGMENTATION_KEYS` while two scalar keys
    carried the same suffix, so the name and the validator contradicted each
    other and the name was the one a reader met first.
    """
    from src.config import _RANGED_AUGMENTATION_KEYS, load_config

    aug = load_config()["augmentation"]

    assert "rotation_degrees" in aug
    assert "translation_fraction" in aug
    assert "rotation_range" not in aug
    assert "translation_range" not in aug

    suffixed = {key for key in aug if key.endswith("_range")}
    assert suffixed == set(_RANGED_AUGMENTATION_KEYS), (
        f"keys ending in _range are {sorted(suffixed)}, but the validator "
        f"treats {sorted(_RANGED_AUGMENTATION_KEYS)} as pairs"
    )


@pytest.mark.parametrize(
    "old_key, new_key, value",
    [
        ("rotation_range", "rotation_degrees", 15),
        ("translation_range", "translation_fraction", 0.05),
    ],
)
def test_an_old_augmentation_key_is_refused_by_name(
    tmp_path, valid_config, old_key, new_key, value
):
    """A renamed key fails loudly rather than defaulting the new one to zero.

    This is the whole reason the rename refuses instead of aliasing: both new
    keys default to "no augmentation" when absent, so a config carrying the old
    name would train without the rotation or the translation the operator asked
    for, and nothing would say so.
    """
    from src.config import load_config

    cfg = valid_config
    cfg["augmentation"] = {old_key: value}
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(cfg), encoding="utf-8")

    with pytest.raises(ValueError) as raised:
        load_config(str(path))

    message = str(raised.value)
    assert old_key in message
    assert new_key in message


def test_project_version_is_not_required(tmp_path, valid_config):
    """`load_config` accepts a config with no `project.version`.

    It was required, read by nothing, and a third thing called "version" beside
    `data.dataset_version` and the CLIs' `--version`.
    """
    from src.config import load_config

    cfg = valid_config
    cfg.pop("project", None)
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(cfg), encoding="utf-8")

    assert load_config(str(path))["classes"]


def test_rotation_divisor_is_explained():
    """`preprocess.py` says why the divisor is 360 rather than 180.

    The conversion is correct and non-obvious: `RandomRotation` takes a fraction
    of a full turn, so a reader expecting a +/- convention would read 180 as the
    right divisor and halve every rotation while fixing nothing.
    """
    from pathlib import Path

    source = (
        Path(__file__).resolve().parents[1] / "src" / "preprocess.py"
    ).read_text(encoding="utf-8")

    divisor_line = next(
        index
        for index, line in enumerate(source.splitlines())
        if "/ 360.0" in line
    )
    preceding = "\n".join(source.splitlines()[max(0, divisor_line - 6):divisor_line])

    assert "360" in preceding and "180" in preceding, (
        "the divisor is used with no comment explaining why it is 360"
    )


def test_config_declares_four_classes_without_siltosa():
    """The model's class list, pinned to a literal in exactly one place.

    SPEC 0046 dropped Siltosa and SPEC 0043's audit reported this criterion as
    having no test named after it. Spelled out rather than derived: a test that
    computed the expected list from the config would assert the config equals
    itself, and the thing worth catching is a class silently added, removed or
    reordered — reordering being the dangerous one, since the index is the
    model's output position.
    """
    from src.config import load_config

    assert load_config()["classes"] == [
        "Arenosa",
        "Media",
        "Muito Argilosa",
        "Argilosa",
    ]


def test_tests_read_the_configured_class_list():
    """No test module keeps its own copy of the four classes the model emits.

    `V1_EVALUATION_CLASSES` was one, and it stopped being a second opinion the
    moment SPEC 0046 made the config declare those same four. A copy that
    nothing compares against the file the training reads is a copy that drifts.

    The five-entry *archive* vocabulary is a different list and is deliberately
    left alone: `test_manifest.py` ties it to `src.manifest.ARCHIVE_CLASSES`.
    """
    from pathlib import Path

    tests_dir = Path(__file__).resolve().parent
    literal = '["Arenosa", "Media", "Muito Argilosa", "Argilosa"]'
    offenders = [
        module.name
        for module in sorted(tests_dir.glob("*.py"))
        # This module is the one place the four are pinned, by the test above.
        if module.name != "test_config.py"
        and literal in module.read_text(encoding="utf-8")
    ]

    # The literal alone is enough: the constant this replaced,
    # `V1_EVALUATION_CLASSES`, was that list, so anything reintroducing it
    # reintroduces the string. Searching for the old name as well would flag the
    # sentence in `support.py` that explains why it is gone.

    assert offenders == [], (
        f"these modules carry their own copy of the model's class list: {offenders}"
    )
