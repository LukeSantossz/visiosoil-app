"""Configuration loader and validator for the ML pipeline."""

import os
from pathlib import Path

import yaml

from .manifest import validate_version_name


_REQUIRED_TOP_KEYS = {
    # `project` is not here. `project.version` was required, read by nothing,
    # and a third thing called "version" beside `data.dataset_version` and the
    # CLIs' `--version` (SPEC 0047). `project.name` survives in config.yaml as
    # a label; nothing requires it either.
    "classes",
    "data",
    "evaluation",
    "preprocessing",
    "model",
    "training",
    "export",
}
_REQUIRED_DATA_KEYS = {
    "raw_dir",
    "splits_dir",
    "datasets_dir",
    "dataset_version",
    "image_size",
    "seed",
}

# Keys the single three-way split needed. They are refused rather than ignored:
# a config still carrying them describes an evaluation design that no longer
# exists (ADR 0020), and silently dropping them would let a reader believe the
# fractions still governed something.
_RETIRED_DATA_KEYS = ("val_split", "test_split")

_REQUIRED_EVALUATION_KEYS = {"k", "repeats", "inner_k", "alpha", "power", "contrasts"}

# A contrast belongs either to the primary family — every arm against the
# shuffled-label control — or is the one named secondary. More than one
# secondary is a second family with no correction applied to it.
_VALID_CONTRAST_FAMILIES = {"primary", "secondary"}

_REQUIRED_PREPROCESSING_KEYS = {
    "normalization",
    "canonical_mm_per_px",
    "patch_stride_fraction",
    "min_patches",
}
_REQUIRED_MODEL_KEYS = {"architecture", "dropout"}
_REQUIRED_TRAINING_KEYS = {"epochs", "batch_size", "learning_rate"}
_VALID_ARCHITECTURES = {"mobilenetv2"}
# One entry, because the pipeline implements one preprocessing contract:
# `build_model` bakes Rescaling(2.0, -1.0) into the graph unconditionally, and
# `_build_spec` declares `divide_255` to match it. `imagenet` was accepted here
# and served by `normalize_imagenet`, but no code path ever removed the baked
# rescaling, so that configuration trained the backbone on 2v - 1 over the
# imagenet range and raised nothing. SPEC 0034 removes the value rather than the
# layer; adding a second contract means adding the model code path with it.
_VALID_NORMALIZATIONS = {"mobilenet_v2"}
_VALID_QUANTIZATIONS = {"dynamic_range", "float16", "none"}

# Input size the pretrained weights of each architecture were trained at. Any
# other size loads without error and silently degrades transfer learning.
#: The input sizes each architecture publishes pretrained weights at. Any
#: other size loads the weights into a graph they were never trained for,
#: which costs the transfer this pipeline exists to use. Widened from a
#: single 224 by SPEC 0053, which needs 160: the patch side in millimetres
#: is `input_size x canonical_mm_per_px`, so the input size is now a
#: physical decision rather than a default.
_ARCHITECTURE_IMAGE_SIZE = {"mobilenetv2": (96, 128, 160, 192, 224)}

# Augmentation keys expressed as a [lower, upper] multiplicative range.
_RANGED_AUGMENTATION_KEYS = ("brightness_range", "contrast_range", "zoom_range")

#: Augmentation keys renamed by SPEC 0047, old name to new. The `_range` suffix
#: meant a `[lo, hi]` pair for three keys and a scalar for these two, so the
#: suffix now marks exactly the keys in `_RANGED_AUGMENTATION_KEYS` above.
#:
#: Refused by name rather than accepted as an alias: a config carrying the old
#: key would otherwise leave the new one absent, and the new one defaults to
#: "no augmentation" — so the run would train without the rotation the operator
#: asked for and report nothing.
_RENAMED_AUGMENTATION_KEYS = {
    "rotation_range": "rotation_degrees",
    "translation_range": "translation_fraction",
}

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

    retired = [key for key in _RETIRED_DATA_KEYS if key in data]
    if retired:
        raise ValueError(
            f"data.{' and data.'.join(retired)} no longer governs anything and "
            "must be removed: evaluation is repeated stratified group k-fold "
            "with nested selection (ADR 0020), configured under the "
            "'evaluation' block. There is no train/val/test partition to size"
        )

    if data["image_size"] < 32:
        raise ValueError("image_size must be at least 32")

    # The rule lives in src.manifest, which owns the dataset layout, so this
    # check and the --version flag check cannot diverge.
    try:
        validate_version_name(str(data["dataset_version"]))
    except ValueError as error:
        raise ValueError(f"data.dataset_version invalid: {error}") from error

    # A seed that is not a plain non-negative int changes seeding behaviour
    # without erroring. bool is an int subclass, so it is excluded explicitly.
    seed = data["seed"]
    if isinstance(seed, bool) or not isinstance(seed, int) or seed < 0:
        raise ValueError(f"data.seed must be a non-negative integer, got {seed!r}")

    _validate_evaluation(cfg["evaluation"])

    # preprocessing
    pre = cfg["preprocessing"]
    missing_pre = _REQUIRED_PREPROCESSING_KEYS - set(pre.keys())
    if missing_pre:
        raise ValueError(f"Missing preprocessing keys: {missing_pre}")
    if pre["normalization"] not in _VALID_NORMALIZATIONS:
        # sorted(), not the set repr: the message is what an operator migrating a
        # stale config.yaml reads, and it has to say why the value went away, not
        # only which one to use.
        raise ValueError(
            f"normalization must be one of {sorted(_VALID_NORMALIZATIONS)}, "
            f"got {pre['normalization']!r}: build_model bakes "
            "Rescaling(2.0, -1.0) into the graph unconditionally, so that is "
            "the only preprocessing contract the pipeline implements"
        )

    canonical = pre["canonical_mm_per_px"]
    if not isinstance(canonical, (int, float)) or isinstance(canonical, bool):
        raise ValueError("preprocessing.canonical_mm_per_px must be a number")
    if canonical <= 0.0:
        raise ValueError(
            "preprocessing.canonical_mm_per_px must be positive, got "
            f"{canonical}: it is the scale every photograph is resampled to, "
            "and it is measured rather than chosen (SPEC 0052)"
        )

    stride = pre["patch_stride_fraction"]
    if not isinstance(stride, (int, float)) or isinstance(stride, bool):
        raise ValueError("preprocessing.patch_stride_fraction must be a number")
    if not 0.0 < stride <= 1.0:
        raise ValueError(
            "preprocessing.patch_stride_fraction must be in (0, 1], got "
            f"{stride}: 1.0 is a non-overlapping grid and anything above it "
            "would leave gaps of soil the model never sees"
        )

    minimum = pre["min_patches"]
    if not isinstance(minimum, int) or isinstance(minimum, bool):
        raise ValueError("preprocessing.min_patches must be an integer")
    if minimum < 1:
        raise ValueError(
            f"preprocessing.min_patches must be at least 1, got {minimum}"
        )

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

    renamed = [key for key in _RENAMED_AUGMENTATION_KEYS if key in aug]
    if renamed:
        raise ValueError(
            "; ".join(
                f"augmentation.{key} was renamed to "
                f"augmentation.{_RENAMED_AUGMENTATION_KEYS[key]} (SPEC 0047): "
                f"the _range suffix marks the keys holding a [lower, upper] "
                f"pair, and this one holds a scalar"
                for key in renamed
            )
        )

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

    # `preprocess` builds RandomBrightness with factor=(lower - 1, upper - 1),
    # and the layer requires each bound within [-1.0, 1.0]. A config range
    # outside [0.0, 2.0] therefore passes the ascending-numbers check above and
    # then fails at layer construction, once training has already started.
    brightness = aug.get("brightness_range")
    if brightness is not None and not (0.0 <= brightness[0] < brightness[1] <= 2.0):
        raise ValueError(
            f"augmentation.brightness_range must lie within [0.0, 2.0] "
            f"(RandomBrightness takes factor={{lower - 1, upper - 1}} and "
            f"requires each bound within [-1.0, 1.0]), got {brightness!r}"
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

    published = _ARCHITECTURE_IMAGE_SIZE.get(model["architecture"])
    if published is not None and data["image_size"] not in published:
        raise ValueError(
            f"data.image_size must be one of {list(published)} for architecture "
            f"{model['architecture']}, got {data['image_size']}: those are the "
            "sizes it publishes ImageNet weights at, and an unpublished size "
            "loads them into a graph they were never trained for"
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

    # Operator determinism defaults ON, because training runs on whatever
    # hardware is available and seeding alone is not reproducible on a GPU.
    # Defaulted here rather than at the call site so the effective value is in
    # the config that gets snapshotted next to the run.
    if "deterministic_ops" in training:
        if not isinstance(training["deterministic_ops"], bool):
            raise ValueError(
                "training.deterministic_ops must be true or false, got "
                f"{training['deterministic_ops']!r}"
            )
    else:
        training["deterministic_ops"] = True

    # export
    export = cfg["export"]
    quantization = export.get("quantization", "dynamic_range")
    if quantization not in _VALID_QUANTIZATIONS:
        raise ValueError(f"quantization must be one of {_VALID_QUANTIZATIONS}")


def _validate_evaluation(evaluation: dict) -> None:
    """Validate the k-fold protocol block (SPEC 0042).

    Every number the protocol reports is a function of these values, so an
    invalid one has to fail at load rather than partway through the twenty-fifth
    training of a run.
    """
    if not isinstance(evaluation, dict):
        raise ValueError("'evaluation' must be a mapping")

    missing = _REQUIRED_EVALUATION_KEYS - set(evaluation.keys())
    if missing:
        raise ValueError(f"Missing evaluation keys: {sorted(missing)}")

    _require_integer_at_least(evaluation, "k", 2)
    _require_integer_at_least(evaluation, "repeats", 1)
    _require_integer_at_least(evaluation, "inner_k", 2)
    _require_unit_fraction(evaluation, "alpha")
    _require_unit_fraction(evaluation, "power")
    _validate_contrasts(evaluation["contrasts"])


def _require_integer_at_least(evaluation: dict, key: str, minimum: int) -> None:
    value = evaluation[key]
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise ValueError(
            f"evaluation.{key} must be an integer of at least {minimum}, "
            f"got {value!r}"
        )


def _require_unit_fraction(evaluation: dict, key: str) -> None:
    value = evaluation[key]
    valid = (
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and 0 < value < 1
    )
    if not valid:
        raise ValueError(
            f"evaluation.{key} must lie strictly between 0 and 1, got {value!r}"
        )


def _validate_contrasts(contrasts) -> None:
    """Validate the pre-registered contrast family.

    Pre-registration is the point: a contrast that is not in this list before
    the run cannot be evaluated after it, so E0 cannot be read for whichever
    comparison happens to clear. An empty list is valid and refuses every
    contrast, which is the honest state until the experiment that owns the arms
    registers its own.
    """
    if not isinstance(contrasts, list):
        raise ValueError("evaluation.contrasts must be a list")

    seen: set[str] = set()
    secondaries = 0
    for index, contrast in enumerate(contrasts):
        where = f"evaluation.contrasts[{index}]"
        if not isinstance(contrast, dict):
            raise ValueError(f"{where} must be a mapping")

        name = contrast.get("name")
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"{where}.name must be a non-empty string")
        if name in seen:
            raise ValueError(
                f"{where}.name {name!r} is registered twice; a contrast is "
                "named so a result can be attributed to it"
            )
        seen.add(name)

        arms = contrast.get("arms")
        valid_arms = (
            isinstance(arms, list)
            and len(arms) == 2
            and all(isinstance(arm, str) and arm.strip() for arm in arms)
            and arms[0] != arms[1]
        )
        if not valid_arms:
            raise ValueError(
                f"{where}.arms must name two distinct arms, got {arms!r}"
            )

        family = contrast.get("family")
        if family not in _VALID_CONTRAST_FAMILIES:
            raise ValueError(
                f"{where}.family must be one of "
                f"{sorted(_VALID_CONTRAST_FAMILIES)}, got {family!r}"
            )
        if family == "secondary":
            secondaries += 1

    if secondaries > 1:
        raise ValueError(
            f"{secondaries} secondary contrasts are registered; ADR 0020 "
            "registers one secondary, because a second family carries no "
            "correction of its own"
        )


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
    cfg["data"]["datasets_dir"] = str(ml_root / cfg["data"]["datasets_dir"])
    cfg["export"] = cfg["export"].copy()
    cfg["export"]["output_dir"] = str(ml_root / cfg["export"]["output_dir"])
    return cfg
