"""Reproducibility of the training pipeline (SPEC 0032).

Experiment E0 asks whether a real model beats a label-shuffled control by more
than run-to-run variance. Without a seed there is no denominator, so these are
the tests that make E0 interpretable.

Determinism is asserted across two runs inside one process, with the pinned
TensorFlow and Keras. Equality across machines or across versions is not
claimed.
"""

import json

import numpy as np
import pytest

# The training stack is pinned to Python 3.12 and has no wheel for every
# interpreter this repository is developed on, so this module skips rather than
# failing to collect. In CI, where `ml/requirements.txt` is installed, it runs.
tf = pytest.importorskip("tensorflow")

from src import train as train_module  # noqa: E402
from src.dataset import derive_repeat_seed  # noqa: E402
from src.model import build_model  # noqa: E402
from src.preprocess import build_augmentation_layer  # noqa: E402
from src.train import (  # noqa: E402
    RUNTIME_FILENAME,
    control_seed,
    load_runtime,
    runtime_mode,
    seed_everything,
)

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


def _fold_config(tmp_path, deterministic_ops=True):
    """The keys `train_fold` indexes, in the shape `load_config` guarantees."""
    return {
        "classes": ["A", "B"],
        "data": {
            "raw_dir": str(tmp_path / "raw"),
            "splits_dir": str(tmp_path / "splits"),
            "image_size": 224,
            "seed": SEED,
        },
        "evaluation": {"k": 5, "repeats": 5, "inner_k": 4},
        # `load_config` guarantees this key, defaulting it to True, so a stub
        # standing in for it has to supply it too.
        "training": {"deterministic_ops": deterministic_ops},
        "export": {"output_dir": str(tmp_path / "models")},
    }


REPEAT = 2


def test_seed_is_set_before_any_dataset_or_model_work(tmp_path, monkeypatch):
    calls = []

    # The stub defaults to None, not True: with a True default the test would
    # pass even if `train_fold` stopped forwarding the flag entirely, which is
    # the regression most worth catching here.
    def _seed(seed, deterministic_ops=None):
        calls.append(("seed", seed, deterministic_ops))
        return {"deterministic_ops": deterministic_ops, "device": "CPU", "gpu_count": 0}

    monkeypatch.setattr(train_module, "seed_everything", _seed)

    def _split(*args, **kwargs):
        calls.append(("fold_split", None))
        raise _StopHere

    monkeypatch.setattr(train_module, "fold_split", _split)

    with pytest.raises(_StopHere):
        train_module.train_fold(
            _fold_config(tmp_path),
            {"seed": SEED},
            arm_dir=tmp_path / "models" / "vtest" / "cnn",
            arm="cnn",
            repeat=REPEAT,
            fold=0,
        )

    assert calls, "train_fold() ran without seeding or reading the dataset"
    assert calls[0] == ("seed", derive_repeat_seed(SEED, REPEAT), True), (
        f"first call was {calls[0]}"
    )
    assert ("fold_split", None) in calls


def test_each_repeat_trains_under_its_own_derived_seed(tmp_path, monkeypatch):
    """The repeat spread measures training variance, which needs distinct seeds."""
    seeds = []
    monkeypatch.setattr(
        train_module,
        "seed_everything",
        lambda seed, deterministic_ops=None: seeds.append(seed)
        or {"deterministic_ops": True, "device": "CPU", "gpu_count": 0},
    )
    monkeypatch.setattr(
        train_module, "fold_split", lambda *a, **k: (_ for _ in ()).throw(_StopHere)
    )

    for repeat in range(3):
        with pytest.raises(_StopHere):
            train_module.train_fold(
                _fold_config(tmp_path),
                {"seed": SEED},
                arm_dir=tmp_path / "models" / "vtest" / "cnn",
                arm="cnn",
                repeat=repeat,
                fold=0,
            )

    assert seeds == [derive_repeat_seed(SEED, r) for r in range(3)]
    assert len(set(seeds)) == 3


def test_the_shuffled_control_seed_is_distinct_from_every_fold_seed():
    """A permutation drawn from the seed that drew the folds is not a control."""
    fold_seeds = {derive_repeat_seed(SEED, r) for r in range(10)}
    control_seeds = {
        control_seed(SEED, repeat, fold) for repeat in range(10) for fold in range(5)
    }

    assert not (fold_seeds & control_seeds)
    assert len(control_seeds) == 50


def test_train_persists_the_runtime_beside_the_fold_artifacts(tmp_path, monkeypatch):
    """Recorded at training time, so evaluation on another host cannot overwrite
    it with a description of that host.
    """
    monkeypatch.setattr(
        train_module,
        "seed_everything",
        lambda seed, deterministic_ops=None: {
            "deterministic_ops": deterministic_ops,
            "device": "CPU",
            "gpu_count": 0,
        },
    )
    monkeypatch.setattr(
        train_module, "fold_split", lambda *a, **k: (_ for _ in ()).throw(_StopHere)
    )

    arm_dir = tmp_path / "models" / "vtest" / "cnn"
    with pytest.raises(_StopHere):
        train_module.train_fold(
            _fold_config(tmp_path, deterministic_ops=False),
            {"seed": SEED},
            arm_dir=arm_dir,
            arm="cnn",
            repeat=1,
            fold=3,
        )

    recorded = load_runtime(arm_dir / "repeat-1" / "fold-3")
    assert recorded == {
        "deterministic_ops": False,
        "device": "CPU",
        "gpu_count": 0,
    }


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


def _record_seeding(monkeypatch) -> list:
    """Record both seeding calls in the order they happen.

    Order matters: `enable_op_determinism` must follow the seed, not replace it.
    Asserting only that determinism was switched on would pass for an
    implementation that forgot to seed at all.
    """
    calls = []
    monkeypatch.setattr(
        tf.keras.utils,
        "set_random_seed",
        lambda seed: calls.append(("seed", seed)),
    )
    monkeypatch.setattr(
        tf.config.experimental,
        "enable_op_determinism",
        lambda: calls.append(("determinism", True)),
    )
    return calls


def test_seeding_enables_operator_determinism_by_default(monkeypatch):
    calls = _record_seeding(monkeypatch)

    runtime = seed_everything(SEED)

    assert calls == [("seed", SEED), ("determinism", True)]
    assert runtime["deterministic_ops"] is True


def test_seeding_can_opt_out_of_operator_determinism(monkeypatch):
    """Exploratory runs may trade reproducibility for throughput, explicitly."""
    calls = _record_seeding(monkeypatch)

    runtime = seed_everything(SEED, deterministic_ops=False)

    assert calls == [("seed", SEED)]
    assert runtime["deterministic_ops"] is False


def test_runtime_records_the_device_it_ran_on():
    """A comparison needs the device as well as the flag: two deterministic runs
    on different hardware are still not guaranteed bit-identical to each other.
    """
    runtime = runtime_mode(True)

    assert runtime["device"] in {"CPU", "GPU"}
    assert isinstance(runtime["gpu_count"], int)


def test_load_runtime_returns_none_when_the_record_is_absent(tmp_path):
    """Absent is not the same as deterministic, and must not read as it."""
    assert load_runtime(tmp_path) is None


def test_load_runtime_reads_back_what_training_wrote(tmp_path):
    written = {"deterministic_ops": False, "device": "CPU", "gpu_count": 0}
    (tmp_path / RUNTIME_FILENAME).write_text(json.dumps(written))

    assert load_runtime(tmp_path) == written
