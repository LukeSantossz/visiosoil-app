"""SPEC 0044's criteria, each checked under its own name (SPEC 0074).

Six of the gate's criteria had no test carrying their name, so SPEC 0043's audit
could not see them. They are not renames of the tests that already assert the
same mechanisms: several of those carry SPEC 0042's or SPEC 0054's criteria, and
a test can carry only one name. Each test here asserts what SPEC 0044's
criterion says, at the level it says it — the registry the gate actually
registered, the arm bindings that actually ran, the verdict that was written.

Writing them found one criterion that was not true of the code, and this module
is also where that is pinned: evaluation pooled a fold scored against another
manifest digest whenever its groups coincided.
"""

import itertools
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from src.config import load_config
from src.crossval import (
    COST_FILENAME,
    PREDICTIONS_FILENAME,
    RUNTIME_FILENAME,
    SELECTION_AUDIT_FILENAME,
    fold_directory,
    load_arm_predictions,
    run_arm,
    write_fold_cost,
    write_fold_predictions,
)
from src.dataset import create_folds, fold_split
from src.evaluate import contrast_results, require_registered_contrast
from src.manifest import class_images, read_manifest, sample_ids_by_image
from src.stats import mcnemar_minimum_detectable_effect
from tests.support import CLASSES, requires_tensorflow, write_version
from tests.test_criteria_coverage import ML_TESTS_DIR, SPECS_DIR, audit
from tests.test_crossval import fabricate, folds  # noqa: F401 - `folds` is a fixture
from tests.test_encoder_arm import SOIL_LEVELS, _config, _photograph, _write_measured_version

ML_ROOT = Path(__file__).resolve().parents[1]
VERDICT = ML_ROOT.parent / "docs" / "ml" / "e0-verdict.md"
GATE_SPEC = "0044-four-arm-e0-feasibility-gate.md"
CONTROL = "shuffled_control"
REAL_ARMS = ("cnn", "descriptors", "encoder_probe")

#: What a fold records about the stack it ran on, for the tests that stand in
#: for a trainer. Identical across folds, because `run_arm` refuses an arm whose
#: folds disagree.
FAKE_RUNTIME = {"deterministic_ops": True, "device": "CPU", "library_versions": {}}

#: Sample groups per class in the measured fixture. Two folds leave two groups
#: of each class on the training side, one for each of the two inner folds.
MEASURED_GROUPS_PER_CLASS = 4


def registry():
    """The contrasts the gate registered before its first run."""
    return list(load_config()["evaluation"]["contrasts"])


# --- unregistered_contrast_is_refused_by_name --------------------------------


def test_unregistered_contrast_is_refused_by_name():
    """The comparisons the gate chose not to make stay unmade.

    Over the four arms there are six pairs and the gate registered four, so two
    comparisons exist that a reader could want after seeing the numbers. Each
    is refused by the name it is asked for, which is the only way `evaluate`
    reaches a single contrast.
    """
    entries = registry()
    arms = sorted({arm for entry in entries for arm in entry["arms"]})
    registered = {frozenset(entry["arms"]) for entry in entries}
    unregistered = [
        pair for pair in itertools.combinations(arms, 2)
        if frozenset(pair) not in registered
    ]
    assert unregistered, "the gate registers every pair, so nothing is refused here"

    for first, second in unregistered:
        requested = f"{first}_vs_{second}"
        with pytest.raises(ValueError) as raised:
            require_registered_contrast(entries, requested)
        assert requested in str(raised.value)


# --- every_arm_reads_the_same_fold_manifest ----------------------------------


def _fake_trainer(received):
    """A fold trainer that records the manifest it was handed and writes the
    artifacts `run_arm` reads back, in the order a real one does."""

    def train(cfg, fold_manifest, *, arm_dir, arm, repeat, fold, **kwargs):
        received.append((arm, fold_manifest))
        records = [
            {
                "path": entry["path"],
                "group": entry["group"],
                "label": entry["label"],
                "probabilities": [1.0 / len(fold_manifest["classes"])]
                * len(fold_manifest["classes"]),
            }
            for entry in fold_split(fold_manifest, repeat, fold)["test"]
        ]
        write_fold_predictions(
            arm_dir,
            repeat=repeat,
            fold=fold,
            arm=arm,
            classes=fold_manifest["classes"],
            records=records,
            shuffled_control=kwargs.get("shuffled_control", False),
            manifest_digest=fold_manifest["manifest_digest"],
        )
        with open(fold_directory(arm_dir, repeat, fold) / RUNTIME_FILENAME, "w") as handle:
            json.dump(FAKE_RUNTIME, handle)
        write_fold_cost(arm_dir, repeat, fold, 1, [0.01])
        return dict(FAKE_RUNTIME)

    return train


def test_every_arm_reads_the_same_fold_manifest(tmp_path, monkeypatch):
    """All four arms are handed the manifest `load_folds_for_config` returned,
    and a fold scored against another digest is refused rather than pooled."""
    import src.crossval as crossval
    import src.dataset as dataset

    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    cfg = load_config()
    cfg["classes"] = list(CLASSES)
    cfg["evaluation"] = {**cfg["evaluation"], "k": 2, "repeats": 1}
    cfg["data"] = {
        **cfg["data"],
        "datasets_dir": str(root.parent),
        "dataset_version": manifest.version,
        "splits_dir": str(tmp_path / "splits"),
    }
    cfg["export"] = {**cfg["export"], "output_dir": str(tmp_path / "models")}
    create_folds(
        class_images(manifest, CLASSES),
        k=2,
        repeats=1,
        seed=cfg["data"]["seed"],
        splits_dir=cfg["data"]["splits_dir"],
        dataset_root=str(root),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
    )

    loaded = []
    real_loader = crossval.load_folds_for_config

    def recording_loader(config, splits_dir):
        loaded.append(real_loader(config, splits_dir))
        return loaded[-1]

    received = []
    trainer = _fake_trainer(received)
    monkeypatch.setattr(crossval, "load_config", lambda path=None: cfg)
    monkeypatch.setattr(crossval, "resolve_paths", lambda config: config)
    monkeypatch.setattr(crossval, "load_folds_for_config", recording_loader)
    monkeypatch.setattr(crossval, "ARM_TRAINERS", {
        arm: (lambda: trainer) for arm in REAL_ARMS + (CONTROL,)
    })
    monkeypatch.setattr(dataset, "verify_images", lambda images: None)

    for arm in REAL_ARMS + (CONTROL,):
        run_arm(manifest.version, arm=arm, shuffled_control=arm == CONTROL)

    assert len(loaded) == 4, "each run loads its folds through load_folds_for_config"
    assert {arm for arm, _ in received} == set(REAL_ARMS) | {CONTROL}
    for arm, handed in received:
        assert any(handed is fold_manifest for fold_manifest in loaded), (
            f"{arm} was handed a manifest load_folds_for_config did not return"
        )

    elsewhere = {**loaded[0], "manifest_digest": "e" * 64}
    with pytest.raises(ValueError, match="manifest"):
        load_arm_predictions(tmp_path / "models" / manifest.version / "cnn", elsewhere)


# --- descriptor_arm_trains_without_a_gpu --------------------------------------


@pytest.fixture
def measured(tmp_path):
    """A measured version of two distinguishable soils, and folds over it.

    Real pixels and a real dish measurement, because the arms below are the real
    bindings: the descriptor arm cuts and describes these patches, and nothing
    stands in for it.
    """
    photographs = [
        {
            "class": name,
            "sample_id": f"{name}-{index}",
            "image": _photograph(level, seed=10 * position + index),
        }
        for position, (name, level) in enumerate(zip(("Arenosa", "Media"), SOIL_LEVELS))
        for index in range(MEASURED_GROUPS_PER_CLASS)
    ]
    root = _write_measured_version(tmp_path, photographs)
    cfg = _config(root)
    cfg["training"] = {**cfg["training"], "deterministic_ops": True}
    manifest = read_manifest(root, cfg["classes"])
    fold_manifest = create_folds(
        class_images(manifest, cfg["classes"]),
        k=cfg["evaluation"]["k"],
        repeats=cfg["evaluation"]["repeats"],
        seed=cfg["data"]["seed"],
        splits_dir=str(tmp_path / "splits"),
        dataset_root=str(root),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
    )
    return cfg, fold_manifest


#: Run in a child process so that hiding the GPU happens before TensorFlow is
#: imported: a process that has already imported it has already enumerated its
#: devices.
DESCRIPTOR_FOLD_SCRIPT = """
import json, sys
from src.arms.descriptors import descriptor_fold
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
fold_manifest = json.load(open(sys.argv[2], encoding="utf-8"))
runtime = descriptor_fold(
    cfg, fold_manifest, arm_dir=sys.argv[3], arm="descriptors",
    repeat=0, fold=0, verify=False,
)
print("RUNTIME=" + json.dumps(runtime))
"""


@requires_tensorflow
def test_descriptor_arm_trains_without_a_gpu(tmp_path, measured):
    """One fold on CPU, with its cost recorded like every other arm's.

    TensorFlow is still needed: `probe_fold` seeds through `src.train`, which
    imports it. The criterion is about the GPU, and that is what is hidden.
    """
    cfg, fold_manifest = measured
    arm_dir = tmp_path / "models" / "v1" / "descriptors"
    cfg_path = tmp_path / "cfg.json"
    folds_path = tmp_path / "folds.json"
    cfg_path.write_text(json.dumps(cfg), encoding="utf-8")
    folds_path.write_text(json.dumps(fold_manifest), encoding="utf-8")

    completed = subprocess.run(
        [sys.executable, "-c", DESCRIPTOR_FOLD_SCRIPT, str(cfg_path), str(folds_path), str(arm_dir)],
        cwd=ML_ROOT,
        env={**os.environ, "CUDA_VISIBLE_DEVICES": "-1"},
        capture_output=True,
        text=True,
        timeout=600,
    )
    assert completed.returncode == 0, completed.stderr[-3000:]

    runtime = json.loads(completed.stdout.split("RUNTIME=", 1)[1])
    assert runtime["device"] == "CPU"
    cost = json.loads((fold_directory(arm_dir, 0, 0) / COST_FILENAME).read_text())
    assert cost["trainings"] >= 1
    assert len(cost["wall_clock_seconds"]) == cost["trainings"]
    assert (fold_directory(arm_dir, 0, 0) / PREDICTIONS_FILENAME).exists()


# --- encoder_arm_probe_is_selected_inside_the_fold ----------------------------


@requires_tensorflow
def test_encoder_arm_probe_is_selected_inside_the_fold(tmp_path, measured, monkeypatch):
    """The encoder arm's own binding, with a stand-in forward pass.

    Only the backbone is replaced — its weights would need a download and say
    nothing about where the probe's `C` was chosen. The binding, the featuriser,
    the cut and the selection are the ones the arm ran with.
    """
    import src.arms.encoder as encoder

    def forward(batch):
        return np.stack([batch.mean(axis=(1, 2, 3)), batch.std(axis=(1, 2, 3))], axis=1)

    monkeypatch.setattr(encoder, "_mobilenet_v2_encoder", lambda image_size: forward)
    cfg, fold_manifest = measured
    arm_dir = tmp_path / "models" / "v1" / "encoder_probe"

    encoder.encoder_probe_fold(
        cfg, fold_manifest, arm_dir=arm_dir, arm="encoder_probe",
        repeat=0, fold=0, verify=False,
    )

    audit_record = json.loads(
        (fold_directory(arm_dir, 0, 0) / SELECTION_AUDIT_FILENAME).read_text()
    )
    test_groups = {entry["group"] for entry in fold_split(fold_manifest, 0, 0)["test"]}
    assert audit_record["groups_read_during_selection"], "selection read nothing"
    assert set(audit_record["groups_read_during_selection"]) & test_groups == set()
    assert audit_record["leaked_groups"] == []
    assert set(audit_record["test_groups"]) == test_groups


# --- every_arm_is_contrasted_against_the_shuffled_control ---------------------


def test_every_arm_is_contrasted_against_the_shuffled_control(folds):  # noqa: F811
    """Over the registered family: one primary contrast per real arm against the
    control, each an exact McNemar test on sample groups, Holm-corrected within
    a primary family of three.

    SPEC 0044 says `metrics.json`; `evaluate` writes this record to
    `contrasts.json`, which is what the verdict reads (SPEC 0074).
    """
    predictions = {
        "cnn": fabricate(folds, correct_rate=0.6, seed=1),
        "descriptors": fabricate(folds, correct_rate=0.8, seed=2),
        "encoder_probe": fabricate(folds, correct_rate=0.85, seed=3),
        CONTROL: fabricate(folds, correct_rate=0.3, seed=4),
    }

    results = contrast_results(registry(), predictions, folds, alpha=0.05, power=0.80)

    against_control = {
        contrast["arms"][0]: contrast
        for contrast in results["contrasts"]
        if CONTROL in contrast["arms"]
    }
    assert set(against_control) == set(REAL_ARMS)
    for arm, contrast in against_control.items():
        assert contrast["arms"] == [arm, CONTROL]
        assert contrast["family"] == "primary"
        assert contrast["outcome"] == "computed"
        assert contrast["unit"] == "sample group"
        assert contrast["pairs"] == folds["counts"]["splittable_groups"]
        assert 0.0 <= contrast["p_value"] <= contrast["p_value_holm"] <= 1.0
        assert contrast["family_size"] == 3
    assert results["families"]["primary"] == 3


# --- minimum_detectable_effect_is_reported_for_every_contrast -----------------


def _verdict_rows():
    """Every row of the verdict's tables that carries an effect and a reading.

    Read by header rather than by position, because the three tables — the
    primary family, the secondary one and the ablation — order their columns
    differently.
    """
    rows = []
    header = None
    for line in VERDICT.read_text(encoding="utf-8").splitlines():
        if not line.startswith("|"):
            header = None
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if header is None:
            header = [cell.lower() for cell in cells]
            continue
        if set("".join(cells)) <= set("-: "):
            continue
        by_name = dict(zip(header, cells))
        effect = next((by_name[name] for name in header if "minimum detectable" in name), None)
        observed = next(
            (by_name[name] for name in header if name in ("observed difference", "difference")),
            None,
        )
        reading = next(
            (by_name[name] for name in header if name in ("reading", "carries signal?")),
            None,
        )
        if effect is not None and observed is not None and reading is not None:
            rows.append((cells[0], observed, effect, reading))
    return rows


def _number(cell):
    """A cell's value, or None where the verdict says there is none."""
    text = cell.replace("*", "").replace("+", "").strip()
    return None if text.lower() == "none" else float(text)


def test_minimum_detectable_effect_is_reported_for_every_contrast(folds):  # noqa: F811
    """Each contrast carries the effect its own discordance could detect, and
    the verdict describes no difference below it as a difference."""
    predictions = {
        "cnn": fabricate(folds, correct_rate=0.55, seed=5),
        "descriptors": fabricate(folds, correct_rate=0.9, seed=6),
        "encoder_probe": fabricate(folds, correct_rate=0.7, seed=7),
        CONTROL: fabricate(folds, correct_rate=0.3, seed=8),
    }
    results = contrast_results(registry(), predictions, folds, alpha=0.05, power=0.80)

    computed = [c for c in results["contrasts"] if c["outcome"] == "computed"]
    assert len(computed) == len(registry())
    for contrast in computed:
        own = mcnemar_minimum_detectable_effect(
            contrast["pairs"], contrast["discordant_rate"], 0.05, 0.80
        )
        # `None` is a recorded fact — no rejection region at this discordance —
        # so it has to be the recorded value too, not a key left out.
        assert "minimum_detectable_effect" in contrast, contrast["name"]
        if own is None:
            assert contrast["minimum_detectable_effect"] is None, contrast["name"]
        else:
            assert contrast["minimum_detectable_effect"] == pytest.approx(own), (
                contrast["name"]
            )
    assert len({c["discordant_rate"] for c in computed}) > 1, (
        "every contrast had the same discordance, so a shared effect would pass"
    )

    rows = _verdict_rows()
    assert len(rows) >= 8, f"read {len(rows)} row(s) of the verdict's tables"
    for name, observed, effect, reading in rows:
        below = _number(effect) is None or _number(observed) < _number(effect)
        if below:
            assert re.search(r"\b(no|neither|not)\b", reading.lower()), (
                f"{name}: {observed} is below its effect {effect} and reads {reading!r}"
            )


# --- an_arm_scored_against_another_manifest_is_refused_by_name ----------------


def _write_arm(arm_dir, fold_manifest, digest_of=lambda repeat, fold: None):
    """Every fold of an arm, under the fold manifest's digest unless told otherwise."""
    predictions = fabricate(fold_manifest)
    for (repeat, fold), records in predictions.items():
        write_fold_predictions(
            arm_dir,
            repeat=repeat,
            fold=fold,
            arm=arm_dir.name,
            classes=fold_manifest["classes"],
            records=records,
            shuffled_control=False,
            manifest_digest=digest_of(repeat, fold) or fold_manifest["manifest_digest"],
        )


def test_an_arm_scored_against_another_manifest_is_refused_by_name(tmp_path, folds):  # noqa: F811
    arm_dir = tmp_path / "models" / "v1" / "descriptors"
    _write_arm(arm_dir, folds)
    predictions, _ = load_arm_predictions(arm_dir, folds)
    assert len(predictions) == folds["repeats"] * folds["k"]

    stale = "a" * 64
    _write_arm(arm_dir, folds, digest_of=lambda repeat, fold: stale if (repeat, fold) == (0, 1) else None)
    with pytest.raises(ValueError) as raised:
        load_arm_predictions(arm_dir, folds)
    message = str(raised.value)
    assert "repeat 0 fold 1" in message
    assert "descriptors" in message
    assert stale[:12] in message
    assert folds["manifest_digest"][:12] in message

    _write_arm(arm_dir, folds)
    path = fold_directory(arm_dir, 0, 2) / PREDICTIONS_FILENAME
    record = json.loads(path.read_text())
    del record["manifest_digest"]
    path.write_text(json.dumps(record))
    with pytest.raises(ValueError, match="repeat 0 fold 2.*no manifest digest"):
        load_arm_predictions(arm_dir, folds)


# --- every_spec_0044_criterion_has_a_named_test -------------------------------


def test_every_spec_0044_criterion_has_a_named_test():
    """SPEC 0043 keeps the repository-wide verdict a warning, so that a criterion
    added tomorrow cannot fail a test written today. SPEC 0044's criteria are
    fixed, and now every one has a test, so for them the verdict is asserted."""
    report = audit(SPECS_DIR, ML_TESTS_DIR)
    stated = [
        entry
        for entry in report.covered + report.gated_only + report.unmatched
        if GATE_SPEC in entry.spec
    ]
    assert len(stated) >= 13, f"the audit read {len(stated)} SPEC 0044 criteria"

    unmatched = sorted(entry.criterion for entry in report.unmatched if GATE_SPEC in entry.spec)
    assert not unmatched, "SPEC 0044 criteria with no named test: " + ", ".join(unmatched)
