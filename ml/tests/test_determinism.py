"""Reproducibility of the training pipeline (SPEC 0032).

Experiment E0 asks whether a real model beats a label-shuffled control by more
than run-to-run variance. Without a seed there is no denominator, so these are
the tests that make E0 interpretable.

Determinism is asserted across two runs inside one process, with the pinned
TensorFlow and Keras. Equality across machines or across versions is not
claimed.
"""

import numpy as np
import pytest
import tensorflow as tf

from src import train as train_module
from src.model import build_model
from src.preprocess import build_augmentation_layer
from src.train import seed_everything

SEED = 1234
HEAD_LAYERS = ("bn", "dense_head", "predictions")


@pytest.fixture
def model_config() -> dict:
    return {
        "classes": ["A", "B", "C"],
        "data": {"image_size": 224, "seed": SEED},
        "model": {"architecture": "mobilenetv2", "dropout": 0.5, "freeze_backbone": True},
        "training": {"learning_rate": 0.001},
    }


@pytest.fixture
def augmentation_config() -> dict:
    return {
        "data": {"image_size": 224, "seed": SEED},
        "augmentation": {
            "horizontal_flip": True,
            "rotation_range": 15,
            "brightness_range": [0.85, 1.15],
            "contrast_range": [0.9, 1.1],
            "zoom_range": [0.95, 1.05],
            "translation_range": 0.05,
        },
    }


def _head_weights(model) -> list:
    weights = []
    for name in HEAD_LAYERS:
        for weight in model.get_layer(name).weights:
            weights.append(np.array(weight))
    return weights


# --- the seed reaches the entry point before anything is built -------------


class _StopHere(Exception):
    """Raised by the patched scanner to end the run under test."""


def test_seed_is_set_before_any_dataset_or_model_work(tmp_path, monkeypatch):
    calls = []
    cfg = {
        "classes": ["A", "B"],
        "data": {
            "raw_dir": str(tmp_path / "raw"),
            "splits_dir": str(tmp_path / "splits"),
            "image_size": 224,
            "val_split": 0.15,
            "test_split": 0.15,
            "seed": SEED,
        },
        # `load_config` guarantees this key, defaulting it to True, so a stub
        # standing in for it has to supply it too.
        "training": {"deterministic_ops": True},
        "export": {"output_dir": str(tmp_path / "models")},
    }

    monkeypatch.setattr(train_module, "load_config", lambda path=None: cfg)
    monkeypatch.setattr(train_module, "resolve_paths", lambda c: c)
    monkeypatch.setattr(
        train_module,
        "seed_everything",
        lambda seed, deterministic_ops=True: calls.append(("seed", seed)),
    )

    def _scan(*args, **kwargs):
        calls.append(("scan", None))
        raise _StopHere

    monkeypatch.setattr(train_module, "scan_dataset", _scan)

    with pytest.raises(_StopHere):
        train_module.train("vtest")

    assert calls, "train() ran without seeding or scanning"
    assert calls[0] == ("seed", SEED), f"first call was {calls[0]}"
    assert ("scan", None) in calls


# --- what the seed has to make reproducible --------------------------------


def test_model_init_is_reproducible(model_config):
    """The classification head is randomly initialized; the backbone is not."""
    seed_everything(SEED)
    first = _head_weights(build_model(model_config))
    seed_everything(SEED)
    second = _head_weights(build_model(model_config))

    assert len(first) == len(second)
    for a, b in zip(first, second):
        np.testing.assert_array_equal(a, b)


def test_model_init_differs_across_seeds(model_config):
    """Guards the previous test against an accidentally constant initializer."""
    seed_everything(SEED)
    first = _head_weights(build_model(model_config))
    seed_everything(SEED + 1)
    second = _head_weights(build_model(model_config))

    assert any(not np.array_equal(a, b) for a, b in zip(first, second))


def test_training_forward_pass_is_reproducible(model_config):
    """Covers dropout: the same seeded build gives the same training output."""
    batch = np.linspace(0.0, 1.0, 2 * 224 * 224 * 3, dtype="float32").reshape(
        2, 224, 224, 3
    )

    seed_everything(SEED)
    first = build_model(model_config)(batch, training=True).numpy()
    seed_everything(SEED)
    second = build_model(model_config)(batch, training=True).numpy()

    np.testing.assert_array_equal(first, second)


def test_augmentation_is_reproducible(augmentation_config):
    batch = np.linspace(0.0, 1.0, 2 * 64 * 64 * 3, dtype="float32").reshape(
        2, 64, 64, 3
    )

    seed_everything(SEED)
    first = build_augmentation_layer(augmentation_config)(batch, training=True).numpy()
    seed_everything(SEED)
    second = build_augmentation_layer(augmentation_config)(batch, training=True).numpy()

    np.testing.assert_array_equal(first, second)


def test_augmentation_differs_across_seeds(augmentation_config):
    """Proves the previous test measures seeding, not a disabled pipeline."""
    batch = np.linspace(0.0, 1.0, 2 * 64 * 64 * 3, dtype="float32").reshape(
        2, 64, 64, 3
    )

    seed_everything(SEED)
    first = build_augmentation_layer(augmentation_config)(batch, training=True).numpy()

    other = dict(augmentation_config)
    other["data"] = dict(augmentation_config["data"], seed=SEED + 1)
    seed_everything(SEED + 1)
    second = build_augmentation_layer(other)(batch, training=True).numpy()

    assert not np.array_equal(first, second)


def test_seed_everything_seeds_numpy_and_tensorflow():
    seed_everything(SEED)
    numpy_first = np.random.rand(4)
    tf_first = tf.random.uniform((4,)).numpy()

    seed_everything(SEED)
    np.testing.assert_array_equal(numpy_first, np.random.rand(4))
    np.testing.assert_array_equal(tf_first, tf.random.uniform((4,)).numpy())


# --- Operator determinism (decided by the project owner, 2026-08-06) ---
#
# Training runs on whatever hardware is available, CPU or GPU. Seeding the RNGs
# is enough on CPU but not on GPU, where several kernels reduce across threads
# in completion order, so two runs of one configuration still diverge. Since E0
# measures an effect against run-to-run variance, a GPU run under seeding alone
# would let that variance swallow the signal with nothing reporting it.
#
# These monkeypatch the TensorFlow call rather than invoking it: op determinism
# cannot be switched off once enabled, so really enabling it here would leak
# into every test that runs afterwards in the same process.


def test_seeding_enables_operator_determinism_by_default(monkeypatch):
    calls = []
    monkeypatch.setattr(
        tf.config.experimental,
        "enable_op_determinism",
        lambda: calls.append("enabled"),
    )

    seed_everything(SEED)

    assert calls == ["enabled"]


def test_seeding_can_opt_out_of_operator_determinism(monkeypatch):
    """Exploratory runs may trade reproducibility for throughput, explicitly."""
    calls = []
    monkeypatch.setattr(
        tf.config.experimental,
        "enable_op_determinism",
        lambda: calls.append("enabled"),
    )

    seed_everything(SEED, deterministic_ops=False)

    assert calls == []
