"""Pooling, reporting and contrasts over the k-fold protocol (SPEC 0042).

Every function under test reads stored predictions rather than a model, so the
whole reporting layer is checkable without TensorFlow. That is what lets the
criteria about what `metrics.json` says be asserted on a machine that cannot run
a training at all.
"""

import json
import re
from pathlib import Path

import numpy as np
import pytest

from src.crossval import (
    COST_FILENAME,
    PREDICTIONS_FILENAME,
    SELECTION_AUDIT_FILENAME,
    fold_directory,
    load_arm_predictions,
    read_fold_metadata,
    write_fold_cost,
    write_fold_predictions,
    write_selection_audit,
)
from src.dataset import create_folds, fold_split, selection_groups
from src.evaluate import (
    arm_metrics,
    contrast_results,
    require_registered_contrast,
)
from src.manifest import class_images, read_manifest, sample_ids_by_image
from src.stats import wilson_interval
from tests.support import CLASSES, write_version

K = 5
REPEATS = 3
SEED = 42


@pytest.fixture
def folds(tmp_path):
    """A fold manifest over a synthetic five-class version."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    return create_folds(
        class_images(manifest, CLASSES),
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(tmp_path / "splits"),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
    )


def fabricate(folds, correct_rate=1.0, seed=0):
    """Predictions for every fold of every repeat, at a chosen accuracy.

    ``correct_rate`` is applied per group so a wrong group is wrong in all of
    its photographs, which is what an arm that misreads a sample looks like.
    """
    generator = np.random.default_rng(seed)
    classes = len(folds["classes"])
    predictions = {}
    for repeat in range(folds["repeats"]):
        for fold in range(folds["k"]):
            entries = fold_split(folds, repeat, fold)["test"]
            verdict = {}
            records = []
            for entry in entries:
                if entry["group"] not in verdict:
                    right = generator.random() < correct_rate
                    verdict[entry["group"]] = (
                        entry["label"]
                        if right
                        else (entry["label"] + 1) % classes
                    )
                distribution = [0.05] * classes
                distribution[verdict[entry["group"]]] = 1.0 - 0.05 * (classes - 1)
                records.append(
                    {
                        "path": entry["path"],
                        "group": entry["group"],
                        "label": entry["label"],
                        "probabilities": distribution,
                    }
                )
            predictions[(repeat, fold)] = records
    return predictions


def fabricate_costs(folds, seconds=12.5):
    return {
        (repeat, fold): {
            "trainings": folds["k"] - 1,
            "wall_clock_seconds": [seconds] * (folds["k"] - 1),
        }
        for repeat in range(folds["repeats"])
        for fold in range(folds["k"])
    }


def metrics_for(folds, **kwargs):
    predictions = kwargs.pop("predictions", None)
    if predictions is None:
        predictions = fabricate(folds, **kwargs)
    return arm_metrics(
        folds,
        arm="cnn",
        version="v1",
        predictions=predictions,
        costs=fabricate_costs(folds),
    )


# --- photograph_level_macro_f1_is_the_primary_number ------------------------


def test_photograph_level_macro_f1_is_the_primary_number(folds):
    metrics = metrics_for(folds, correct_rate=0.7, seed=1)

    assert metrics["primary"]["metric"] == "photograph_macro_f1"
    assert len(metrics["primary"]["per_repeat"]) == REPEATS

    for record in metrics["repeats"]:
        assert record["photograph_macro_f1"] == pytest.approx(
            metrics["primary"]["per_repeat"][record["repeat"]]
        )
        assert 0.0 <= record["photograph_macro_f1"] <= 1.0
        assert record["photographs"] == folds["counts"]["photographs"]


def test_the_primary_number_is_pooled_over_the_k_test_sides_not_averaged(folds):
    """Pooling and averaging differ when folds hold unequal counts; pooling wins."""
    metrics = metrics_for(folds, correct_rate=1.0)

    for record in metrics["repeats"]:
        assert record["photograph_macro_f1"] == pytest.approx(1.0)
        assert sum(f["photographs"] for f in record["folds"]) == record["photographs"]


# --- group_level_prediction_is_mean_of_photograph_distributions -------------


def test_group_level_prediction_is_mean_of_photograph_distributions(folds):
    metrics = metrics_for(folds, correct_rate=0.6, seed=3)

    assert metrics["secondary"]["metric"] == "group_macro_f1"
    for record in metrics["repeats"]:
        assert record["groups"] == folds["counts"]["splittable_groups"]
        assert 0.0 <= record["group_macro_f1"] <= 1.0
        assert record["group_accuracy"] == pytest.approx(
            record["groups_correct"] / record["groups"]
        )


def test_a_group_is_scored_by_its_mean_distribution_not_a_photograph_vote(folds):
    """Two weak photographs and one certain one: the mean is what decides."""
    predictions = fabricate(folds, correct_rate=1.0)
    key = (0, 0)
    target = predictions[key][0]["group"]
    truth = predictions[key][0]["label"]
    other = (truth + 1) % len(folds["classes"])

    weak = [0.0] * len(folds["classes"])
    weak[truth], weak[other] = 0.51, 0.49
    certain = [0.0] * len(folds["classes"])
    certain[other] = 1.0

    photographs = [r for r in predictions[key] if r["group"] == target]
    for index, record in enumerate(photographs):
        record["probabilities"] = list(weak if index < len(photographs) - 1 else certain)

    metrics = arm_metrics(
        folds,
        arm="cnn",
        version="v1",
        predictions=predictions,
        costs=fabricate_costs(folds),
    )

    assert metrics["repeats"][0]["groups_correct"] == (
        folds["counts"]["splittable_groups"] - 1
    ), "the mean of the distributions must have moved the group to the wrong class"


# --- uncertainty_is_never_fold_spread_alone ---------------------------------


def test_uncertainty_is_never_fold_spread_alone(folds):
    metrics = metrics_for(folds, correct_rate=0.65, seed=5)

    for record in metrics["repeats"]:
        interval = record["wilson_interval_95_group_accuracy"]
        expected = wilson_interval(record["groups_correct"], record["groups"])
        assert interval["low"] == pytest.approx(expected[0])
        assert interval["high"] == pytest.approx(expected[1])

    across = metrics["uncertainty"]["across_repeats"]
    assert across["primary_median"] == pytest.approx(
        float(np.median(metrics["primary"]["per_repeat"]))
    )
    assert across["primary_range"] == [
        pytest.approx(min(metrics["primary"]["per_repeat"])),
        pytest.approx(max(metrics["primary"]["per_repeat"])),
    ]

    interval_key = re.compile(r"interval|confidence|\bci\b", re.IGNORECASE)
    for record in metrics["repeats"]:
        for fold_record in record["folds"]:
            offending = [key for key in fold_record if interval_key.search(key)]
            assert not offending, (
                f"fold record carries {offending}; no interval may be computed "
                "from per-fold values"
            )


def test_the_recorded_interval_is_not_the_spread_across_folds(folds):
    """Constructed so the two answers cannot coincide by accident."""
    metrics = metrics_for(folds, correct_rate=1.0)

    record = metrics["repeats"][0]
    fold_accuracies = [f["group_accuracy"] for f in record["folds"]]
    assert set(fold_accuracies) == {1.0}, "every fold is perfect in this fixture"

    interval = record["wilson_interval_95_group_accuracy"]
    assert interval["low"] < 1.0, (
        "a fold-spread interval would have zero width here; the Wilson interval "
        "on the pooled group count does not"
    )
    assert interval["high"] == pytest.approx(1.0)


# --- per_class_metrics_are_recorded_and_flagged -----------------------------


def test_per_class_metrics_are_recorded_and_flagged(folds):
    metrics = metrics_for(folds, correct_rate=0.6, seed=7)

    assert set(metrics["per_class"]) == set(folds["classes"])
    for name, record in metrics["per_class"].items():
        assert record["headline"] is False, f"{name} is not flagged"
        assert record["groups"] > 0
        assert record["photographs"] > 0
        for level in ("photograph", "group"):
            for key in ("precision", "recall", "f1"):
                assert 0.0 <= record[level][key] <= 1.0


# --- cost_is_recorded -------------------------------------------------------


def test_cost_is_recorded(folds):
    metrics = metrics_for(folds, correct_rate=0.8, seed=9)

    cost = metrics["cost"]
    expected_trainings = REPEATS * K * (K - 1)
    assert cost["trainings"] == expected_trainings
    assert len(cost["wall_clock_seconds_per_training"]) == expected_trainings
    assert cost["wall_clock_seconds_total"] == pytest.approx(
        sum(cost["wall_clock_seconds_per_training"])
    )
    assert cost["outer_folds"] == K
    assert cost["repeats"] == REPEATS


def test_cost_is_recorded_as_absent_rather_than_zero_when_nothing_measured(folds):
    """A missing measurement must not read as a run that cost nothing."""
    metrics = arm_metrics(
        folds, arm="cnn", version="v1", predictions=fabricate(folds), costs={}
    )

    assert metrics["cost"]["trainings"] is None
    assert metrics["cost"]["wall_clock_seconds_per_training"] == []


# --- contrasts_are_pre_registered -------------------------------------------


def test_contrasts_are_pre_registered():
    registry = [
        {"name": "cnn_vs_control", "arms": ["cnn", "control"], "family": "primary"}
    ]

    assert require_registered_contrast(registry, "cnn_vs_control")["arms"] == [
        "cnn",
        "control",
    ]

    with pytest.raises(ValueError) as raised:
        require_registered_contrast(registry, "cnn_vs_whatever_cleared")

    message = str(raised.value)
    assert "cnn_vs_whatever_cleared" in message
    assert "cnn_vs_control" in message


def test_an_empty_registry_refuses_every_contrast():
    with pytest.raises(ValueError, match="no contrast is registered"):
        require_registered_contrast([], "anything")


# --- paired_contrast_is_mcnemar_on_groups_with_holm -------------------------


def test_paired_contrast_is_mcnemar_on_groups_with_holm(folds):
    registry = [
        {"name": "strong_vs_control", "arms": ["strong", "control"], "family": "primary"},
        {"name": "weak_vs_control", "arms": ["weak", "control"], "family": "primary"},
    ]
    predictions_by_arm = {
        "strong": fabricate(folds, correct_rate=1.0),
        "weak": fabricate(folds, correct_rate=0.55, seed=11),
        "control": fabricate(folds, correct_rate=0.2, seed=13),
    }

    results = contrast_results(
        registry, predictions_by_arm, folds, alpha=0.05, power=0.80
    )

    assert [c["name"] for c in results["contrasts"]] == [
        "strong_vs_control",
        "weak_vs_control",
    ]
    for contrast in results["contrasts"]:
        first, second = contrast["arms"]
        counts = contrast["discordant"]
        assert set(counts) == {f"favouring_{first}", f"favouring_{second}"}
        assert contrast["pairs"] == folds["counts"]["splittable_groups"]
        assert 0.0 <= contrast["p_value"] <= 1.0
        assert contrast["p_value_holm"] >= contrast["p_value"] - 1e-12
        assert contrast["family"] == "primary"

    holm = [c["p_value_holm"] for c in results["contrasts"]]
    raw = [c["p_value"] for c in results["contrasts"]]
    assert holm != raw or len(set(raw)) == 1


def test_the_contrast_is_paired_on_the_group_not_the_photograph(folds):
    registry = [{"name": "a_vs_b", "arms": ["a", "b"], "family": "primary"}]
    predictions_by_arm = {
        "a": fabricate(folds, correct_rate=1.0),
        "b": fabricate(folds, correct_rate=0.0, seed=17),
    }

    results = contrast_results(
        registry, predictions_by_arm, folds, alpha=0.05, power=0.80
    )

    contrast = results["contrasts"][0]
    groups = folds["counts"]["splittable_groups"]
    assert contrast["pairs"] == groups
    assert contrast["discordant"]["favouring_a"] == groups
    assert contrast["discordant"]["favouring_b"] == 0
    assert contrast["observed_difference"] == pytest.approx(1.0)


def test_a_contrast_between_arms_run_on_different_groups_is_refused(folds):
    registry = [{"name": "a_vs_b", "arms": ["a", "b"], "family": "primary"}]
    truncated = fabricate(folds, correct_rate=1.0)
    dropped = truncated[(0, 0)][0]["group"]
    truncated = {
        key: [record for record in records if record["group"] != dropped]
        for key, records in truncated.items()
    }

    with pytest.raises(ValueError, match="same groups"):
        contrast_results(
            registry,
            {"a": fabricate(folds), "b": truncated},
            folds,
            alpha=0.05,
            power=0.80,
        )


def test_holm_is_applied_within_the_registered_family_only(folds):
    registry = [
        {"name": "primary_one", "arms": ["a", "control"], "family": "primary"},
        {"name": "primary_two", "arms": ["b", "control"], "family": "primary"},
        {"name": "the_secondary", "arms": ["a", "b"], "family": "secondary"},
    ]
    predictions_by_arm = {
        "a": fabricate(folds, correct_rate=0.9, seed=21),
        "b": fabricate(folds, correct_rate=0.8, seed=23),
        "control": fabricate(folds, correct_rate=0.25, seed=27),
    }

    results = contrast_results(
        registry, predictions_by_arm, folds, alpha=0.05, power=0.80
    )

    by_name = {c["name"]: c for c in results["contrasts"]}
    assert by_name["the_secondary"]["p_value_holm"] == pytest.approx(
        by_name["the_secondary"]["p_value"]
    ), "a family of one is not corrected"
    assert results["families"] == {"primary": 2, "secondary": 1}


# --- mde_is_computed_from_observed_discordance ------------------------------


def test_mde_is_computed_from_observed_discordance(folds):
    registry = [{"name": "a_vs_b", "arms": ["a", "b"], "family": "primary"}]
    predictions_by_arm = {
        "a": fabricate(folds, correct_rate=0.9, seed=31),
        "b": fabricate(folds, correct_rate=0.5, seed=37),
    }

    contrast = contrast_results(
        registry, predictions_by_arm, folds, alpha=0.05, power=0.80
    )["contrasts"][0]

    discordant = sum(contrast["discordant"].values())
    assert contrast["discordant_rate"] == pytest.approx(
        discordant / contrast["pairs"]
    )

    from src.stats import mcnemar_minimum_detectable_effect

    assert contrast["minimum_detectable_effect"] == pytest.approx(
        mcnemar_minimum_detectable_effect(
            contrast["pairs"], contrast["discordant_rate"], 0.05, 0.80
        )
    )
    assert contrast["alpha"] == 0.05
    assert contrast["power"] == 0.80
    assert "observed_difference" in contrast


def test_an_undetectable_contrast_records_a_null_mde_rather_than_a_number(folds):
    """No rejection region is a different fact from a large detectable effect."""
    registry = [{"name": "a_vs_b", "arms": ["a", "b"], "family": "primary"}]
    identical = fabricate(folds, correct_rate=0.6, seed=41)

    contrast = contrast_results(
        registry,
        {"a": identical, "b": identical},
        folds,
        alpha=0.05,
        power=0.80,
    )["contrasts"][0]

    assert sum(contrast["discordant"].values()) == 0
    assert contrast["minimum_detectable_effect"] is None
    assert contrast["p_value"] == 1.0


# --- the on-disk layout the orchestrator writes -----------------------------


def test_fold_predictions_round_trip_through_the_fold_directory(tmp_path, folds):
    arm_dir = tmp_path / "models" / "v1" / "cnn"
    predictions = fabricate(folds, correct_rate=0.7, seed=43)

    for (repeat, fold), records in predictions.items():
        write_fold_predictions(
            arm_dir,
            repeat=repeat,
            fold=fold,
            arm="cnn",
            classes=folds["classes"],
            records=records,
            shuffled_control=False,
        )
        directory = fold_directory(arm_dir, repeat, fold)
        assert directory == arm_dir / f"repeat-{repeat}" / f"fold-{fold}"
        (directory / COST_FILENAME).write_text(
            json.dumps({"trainings": 4, "wall_clock_seconds": [1.0, 2.0, 3.0, 4.0]}),
            encoding="utf-8",
        )

    loaded, costs = load_arm_predictions(arm_dir, folds)

    assert set(loaded) == set(predictions)
    assert loaded[(0, 0)] == predictions[(0, 0)]
    assert costs[(0, 0)]["trainings"] == 4
    assert (
        fold_directory(arm_dir, 0, 0) / PREDICTIONS_FILENAME
    ).is_file()


def test_loading_an_arm_with_a_missing_fold_names_it(tmp_path, folds):
    arm_dir = tmp_path / "models" / "v1" / "cnn"
    write_fold_predictions(
        arm_dir,
        repeat=0,
        fold=0,
        arm="cnn",
        classes=folds["classes"],
        records=fabricate(folds)[(0, 0)],
        shuffled_control=False,
    )

    with pytest.raises(FileNotFoundError, match="repeat 0 fold 1"):
        load_arm_predictions(arm_dir, folds)


# --- the artifacts that make the nesting checkable --------------------------


def test_the_selection_audit_records_what_was_read_and_what_was_chosen(
    tmp_path, folds
):
    """`selection_is_nested` and `refit_uses_the_whole_training_side` are both
    asserted against this file, so it has to carry both facts.
    """
    arm_dir = tmp_path / "models" / "v1" / "cnn"
    split = fold_split(folds, repeat=0, fold=0)
    read = sorted(selection_groups(folds, 0, 0, inner_k=4))
    test_groups = sorted({entry["group"] for entry in split["test"]})
    refit_groups = {entry["group"] for entry in split["train"]}

    path = write_selection_audit(
        arm_dir,
        0,
        0,
        selection_group_ids=read,
        test_group_ids=test_groups,
        inner_k=4,
        chosen={"epochs": 7, "shuffled_control": False, "permutation_seed": None},
        refit_group_count=len(refit_groups),
    )

    written = json.loads(path.read_text(encoding="utf-8"))
    assert path == fold_directory(arm_dir, 0, 0) / SELECTION_AUDIT_FILENAME
    assert written["groups_read_during_selection"] == read
    assert written["test_groups"] == test_groups
    assert written["leaked_groups"] == []
    assert written["chosen"]["epochs"] == 7
    assert written["refit_groups"] == len(refit_groups)
    assert written["inner_k"] == 4


def test_the_selection_audit_refuses_a_leak_it_would_otherwise_only_record(
    tmp_path, folds
):
    """Recording a leak and continuing would produce a number nobody may use."""
    arm_dir = tmp_path / "models" / "v1" / "cnn"
    split = fold_split(folds, repeat=0, fold=0)
    test_groups = sorted({entry["group"] for entry in split["test"]})

    with pytest.raises(ValueError, match="its own test groups"):
        write_selection_audit(
            arm_dir,
            0,
            0,
            selection_group_ids=test_groups[:1],
            test_group_ids=test_groups,
            inner_k=4,
            chosen={"epochs": 7},
            refit_group_count=0,
        )

    written = json.loads(
        (fold_directory(arm_dir, 0, 0) / SELECTION_AUDIT_FILENAME).read_text(
            encoding="utf-8"
        )
    )
    assert written["leaked_groups"] == test_groups[:1], (
        "the evidence must survive the refusal"
    )


def test_the_control_records_the_seed_its_permutation_was_drawn_from(
    tmp_path, folds
):
    """`shuffled_control_permutes_labels_at_group_level` requires the seed to be
    recorded, and the audit beside the fold is where it lives.
    """
    arm_dir = tmp_path / "models" / "v1" / "shuffled_control"
    split = fold_split(folds, repeat=0, fold=0)

    path = write_selection_audit(
        arm_dir,
        0,
        0,
        selection_group_ids=sorted(selection_groups(folds, 0, 0, inner_k=4)),
        test_group_ids=sorted({e["group"] for e in split["test"]}),
        inner_k=4,
        chosen={"epochs": 5, "shuffled_control": True, "permutation_seed": 500042},
        refit_group_count=len({e["group"] for e in split["train"]}),
    )

    written = json.loads(path.read_text(encoding="utf-8"))
    assert written["chosen"]["shuffled_control"] is True
    assert written["chosen"]["permutation_seed"] == 500042


def test_the_fold_cost_record_round_trips_into_the_metrics(tmp_path, folds):
    arm_dir = tmp_path / "models" / "v1" / "cnn"
    predictions = fabricate(folds, correct_rate=0.7, seed=51)

    for (repeat, fold), records in predictions.items():
        write_fold_predictions(
            arm_dir,
            repeat=repeat,
            fold=fold,
            arm="cnn",
            classes=folds["classes"],
            records=records,
            shuffled_control=False,
        )
        write_fold_cost(arm_dir, repeat, fold, trainings=5, seconds=[1.5] * 5)

    loaded, costs = load_arm_predictions(arm_dir, folds)
    metrics = arm_metrics(
        folds, arm="cnn", version="v1", predictions=loaded, costs=costs
    )

    assert metrics["cost"]["trainings"] == REPEATS * K * 5
    assert metrics["cost"]["wall_clock_seconds_total"] == pytest.approx(
        REPEATS * K * 5 * 1.5
    )


def test_the_arm_metadata_says_whether_it_was_the_shuffled_control(tmp_path, folds):
    """A control reported as a real arm is the mislabelling that inverts E0."""
    arm_dir = tmp_path / "models" / "v1" / "shuffled_control"
    write_fold_predictions(
        arm_dir,
        repeat=0,
        fold=0,
        arm="shuffled_control",
        classes=folds["classes"],
        records=fabricate(folds)[(0, 0)],
        shuffled_control=True,
    )

    metadata = read_fold_metadata(arm_dir, 0, 0)

    assert metadata["shuffled_control"] is True
    assert metadata["arm"] == "shuffled_control"
    assert "predictions" not in metadata
