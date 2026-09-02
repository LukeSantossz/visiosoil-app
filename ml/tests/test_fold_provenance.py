"""The production entry points check the folds they load (SPEC 0042).

`load_folds` has always been able to refuse a fold manifest that belongs to
another dataset — and no production caller ever asked it to. The criterion
`result_from_another_manifest_is_refused` passed on a direct call to the loader
while every real path went unguarded, which is the shape of test that proves a
capability exists rather than that it is used.

So these tests go through the entry points. `src.evaluate.evaluate` and
`src.crossval.run_arm` both reach the guard before they reach TensorFlow, so
they run wherever the suite runs; `src.train.train` shares the same loader and
is exercised in CI.

The scenario that makes this urgent is not hypothetical, and since SPEC 0046 it
is not hypothetical at all: `config.yaml` now declares four classes, and a
`splits.json` drawn under the previous five would keep assigning label 4 to a
model that has four outputs — a silent relabelling of every result.
"""

import json
import shutil

import pytest
import yaml

from src import crossval as crossval_module
from src.crossval import write_fold_predictions
from src.dataset import (
    FOLD_MANIFEST_FILENAME,
    create_folds,
    fold_split,
)
from src.evaluate import evaluate
from src.manifest import class_images, read_manifest, sample_ids_by_image
from tests.support import CLASSES, write_version

K = 5
REPEATS = 2
SEED = 42


def write_config(tmp_path, *, classes=CLASSES, seed=SEED, k=K, repeats=REPEATS):
    """A complete, valid config pointing at this test's temporary tree.

    Absolute paths, because `resolve_paths` joins relative ones onto the `ml/`
    root and would send the run at the real dataset.
    """
    config = {
        "project": {"name": "test"},
        "classes": list(classes),
        "data": {
            "raw_dir": str(tmp_path / "raw"),
            "splits_dir": str(tmp_path / "splits"),
            "datasets_dir": str(tmp_path / "datasets"),
            "dataset_version": "v1",
            "image_size": 224,
            "seed": seed,
        },
        "evaluation": {
            "k": k,
            "repeats": repeats,
            "inner_k": 4,
            "alpha": 0.05,
            "power": 0.8,
            "contrasts": [],
        },
        "preprocessing": {"normalization": "mobilenet_v2", "bake_into_model": True},
        "model": {"architecture": "mobilenetv2", "dropout": 0.5},
        "training": {"epochs": 5, "batch_size": 8, "learning_rate": 0.001},
        "export": {"quantization": "none", "output_dir": str(tmp_path / "models")},
    }
    path = tmp_path / "config.yaml"
    path.write_text(yaml.safe_dump(config), encoding="utf-8")
    return str(path)


def build(tmp_path, *, classes=CLASSES, seed=SEED, k=K, repeats=REPEATS):
    """Write a dataset version and the fold manifest drawn from it."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    folds = create_folds(
        class_images(manifest, classes),
        k=k,
        repeats=repeats,
        seed=seed,
        splits_dir=str(tmp_path / "splits"),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
    )
    return root, folds


def fabricate_predictions(tmp_path, folds, arm="cnn"):
    """A perfect arm, so the accepting path has something to report."""
    arm_dir = tmp_path / "models" / "v1" / arm
    width = len(folds["classes"])
    for repeat in range(folds["repeats"]):
        for fold in range(folds["k"]):
            records = []
            for entry in fold_split(folds, repeat, fold)["test"]:
                distribution = [0.0] * width
                distribution[entry["label"]] = 1.0
                records.append(
                    {
                        "path": entry["path"],
                        "group": entry["group"],
                        "label": entry["label"],
                        "probabilities": distribution,
                    }
                )
            write_fold_predictions(
                arm_dir,
                repeat=repeat,
                fold=fold,
                arm=arm,
                classes=folds["classes"],
                records=records,
                shuffled_control=False,
            )
    return arm_dir


# --- the digest guard, at the entry point -----------------------------------


def test_evaluate_refuses_a_fold_manifest_drawn_from_another_manifest(tmp_path):
    """The guard that existed and was never called from anywhere real."""
    root, _ = build(tmp_path)
    config_path = write_config(tmp_path)

    # The dataset changes after the folds were drawn: one more photograph.
    shutil.copy(root / "images" / "Arenosa-0_dish.jpg", root / "images" / "extra.jpg")
    manifest_csv = root / "manifest.csv"
    manifest_csv.write_text(
        manifest_csv.read_text(encoding="utf-8")
        + "Arenosa-9,Arenosa,images/extra.jpg,dish,Fazenda 0,Pixel 8,2026-08-12\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError) as raised:
        evaluate("v1", "cnn", config_path)

    assert "manifest_digest" in str(raised.value)


def test_crossval_refuses_a_fold_manifest_drawn_from_another_manifest(tmp_path):
    """The training entry point reaches the guard before it reaches TensorFlow."""
    root, _ = build(tmp_path)
    config_path = write_config(tmp_path)
    manifest_csv = root / "manifest.csv"
    manifest_csv.write_text(
        manifest_csv.read_text(encoding="utf-8").replace("Pixel 8", "Pixel 9", 1),
        encoding="utf-8",
    )

    with pytest.raises(ValueError) as raised:
        crossval_module.run_arm("v1", "cnn", config_path)

    assert "manifest_digest" in str(raised.value)


def test_evaluate_refuses_when_the_dataset_the_folds_name_is_not_there(tmp_path):
    """Unverifiable is refused, exactly as an unrecorded digest already was."""
    _, _ = build(tmp_path)
    config_path = write_config(tmp_path)
    (tmp_path / "datasets" / "v1" / "manifest.csv").unlink()

    with pytest.raises(FileNotFoundError, match="cannot be checked"):
        evaluate("v1", "cnn", config_path)


# --- the config agreement check, at the entry point -------------------------


def test_a_five_class_fold_manifest_is_refused(tmp_path):
    """Five classes drawn, four configured, every label after Siltosa remapped.

    Named after SPEC 0046's criterion, and no longer hypothetical: `ml/config.yaml`
    now declares the four, so a `splits.json` left over from before that change
    is exactly this case. It is refused rather than reused, which is what makes
    "regenerate the folds after the class change, not before" a guard instead of
    an instruction someone has to remember.
    """
    build(tmp_path)
    config_path = write_config(tmp_path, classes=[c for c in CLASSES if c != "Siltosa"])

    with pytest.raises(ValueError) as raised:
        evaluate("v1", "cnn", config_path)

    message = str(raised.value)
    assert "classes" in message
    assert "Siltosa" in message
    assert FOLD_MANIFEST_FILENAME in message


def test_evaluate_refuses_folds_drawn_under_a_different_seed(tmp_path):
    build(tmp_path)
    config_path = write_config(tmp_path, seed=SEED + 1)

    with pytest.raises(ValueError, match="seed"):
        evaluate("v1", "cnn", config_path)


def test_evaluate_refuses_folds_drawn_under_a_different_k(tmp_path):
    build(tmp_path)
    config_path = write_config(tmp_path, k=4)

    with pytest.raises(ValueError, match="evaluation.k"):
        evaluate("v1", "cnn", config_path)


def test_evaluate_refuses_folds_drawn_under_a_different_repeat_count(tmp_path):
    build(tmp_path)
    config_path = write_config(tmp_path, repeats=REPEATS + 1)

    with pytest.raises(ValueError, match="evaluation.repeats"):
        evaluate("v1", "cnn", config_path)


def test_every_disagreement_is_reported_in_one_pass(tmp_path):
    """The reader is fixing a config; one list beats four cycles."""
    build(tmp_path)
    config_path = write_config(tmp_path, seed=SEED + 1, k=4, repeats=REPEATS + 1)

    with pytest.raises(ValueError) as raised:
        evaluate("v1", "cnn", config_path)

    message = str(raised.value)
    assert "seed" in message
    assert "evaluation.k" in message
    assert "evaluation.repeats" in message


def test_evaluate_accepts_the_folds_the_config_actually_describes(tmp_path):
    """The guard has to be a check and not a wall, or nothing can run."""
    _, folds = build(tmp_path)
    config_path = write_config(tmp_path)
    fabricate_predictions(tmp_path, folds)

    metrics = evaluate("v1", "cnn", config_path)

    assert metrics["primary"]["median"] == pytest.approx(1.0)
    written = json.loads(
        (tmp_path / "models" / "v1" / "cnn" / "metrics.json").read_text(
            encoding="utf-8"
        )
    )
    assert written["protocol"]["k"] == K


# --- a named contrast without --contrasts -----------------------------------


def test_evaluate_refuses_a_named_contrast_without_the_contrasts_flag(tmp_path):
    """Otherwise it silently recomputes metrics and reports no contrast at all."""
    _, folds = build(tmp_path)
    config_path = write_config(tmp_path)
    fabricate_predictions(tmp_path, folds)

    with pytest.raises(ValueError) as raised:
        evaluate("v1", "cnn", config_path, contrast_name="cnn_vs_control")

    message = str(raised.value)
    assert "cnn_vs_control" in message
    assert "--contrasts" in message


def test_the_refused_combination_leaves_no_metrics_behind(tmp_path):
    """The refusal must precede the write, or it overwrote what it refused."""
    _, folds = build(tmp_path)
    config_path = write_config(tmp_path)
    arm_dir = fabricate_predictions(tmp_path, folds)

    with pytest.raises(ValueError):
        evaluate("v1", "cnn", config_path, contrast_name="whatever")

    assert not (arm_dir / "metrics.json").exists()
    assert not (arm_dir / "confusion_matrix.png").exists()
