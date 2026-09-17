"""The descriptor ablation the E0 gate reports (SPEC 0065).

Each test name matches a criterion in
`docs/specs/0065-the-descriptor-ablation-the-gate-reports.md`.

Nothing here is gated on the ingested archive. The arms are resolved by name and
the reading is arithmetic over correctness maps, so every criterion is checkable
where the project ships (SPEC 0043).
"""

import json

import pytest

from src.ablation import (
    ABLATION_ARMS,
    ABLATION_DIRNAME,
    ABLATION_REPORT_FILENAME,
    BASE_ARM,
    READING_RULE,
    ablation_arm_name,
    ablation_contrasts,
    reading_cell,
    remaining_groups,
    write_ablation_report,
)
from src.config import load_config
from src.crossval import (
    COST_FILENAME,
    fold_directory,
    fold_trainer_for,
    load_arm_predictions,
    write_fold_predictions,
)
from src.dataset import create_folds, fold_split
from src.descriptors import GROUPS
from src.manifest import class_images, read_manifest, sample_ids_by_image
from tests.support import CLASSES, write_version

K = 5
REPEATS = 2
SEED = 42
FIXTURE_DIGEST = "a" * 64

ALPHA = 0.05
POWER = 0.8


@pytest.fixture
def folds(tmp_path):
    """A fold manifest over a synthetic version, as every arm reads one."""
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    return create_folds(
        class_images(manifest, CLASSES),
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(tmp_path / "splits"),
        dataset_root=str(root),
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
    )


def correctness(groups, wrong=()):
    """One arm's group-level correctness, with `wrong` the groups it missed."""
    return {group: group not in set(wrong) for group in groups}


# --- ablation_removes_one_group_per_arm --------------------------------------


def test_ablation_removes_one_group_per_arm():
    """Four arms, each missing exactly one group, covering every group once."""
    assert set(ABLATION_ARMS.values()) == set(GROUPS)
    assert len(ABLATION_ARMS) == len(GROUPS)

    for arm, group in ABLATION_ARMS.items():
        assert arm == ablation_arm_name(group)
        assert group not in remaining_groups(group)
        assert set(remaining_groups(group)) == set(GROUPS) - {group}


def test_the_removed_group_names_the_arm_it_is_removed_from():
    """The name says what is missing, so a fold directory is self-describing."""
    for group in GROUPS:
        assert ablation_arm_name(group) == f"{BASE_ARM}_without_{group}"


# --- ablation_arm_runs_through_the_orchestrator ------------------------------


def test_ablation_arm_runs_through_the_orchestrator():
    """`fold_trainer_for` resolves every ablation arm rather than refusing it."""
    for arm in ABLATION_ARMS:
        assert callable(fold_trainer_for(arm))


def test_an_ablation_fold_loads_through_the_protocols_own_loader(tmp_path, folds):
    """A finished fold is read by `load_arm_predictions` like any other arm's."""
    arm = ablation_arm_name(GROUPS[0])
    arm_dir = tmp_path / "models" / "v1" / arm

    for repeat in range(folds["repeats"]):
        for fold in range(folds["k"]):
            entries = fold_split(folds, repeat, fold)["test"]
            records = [
                {
                    "path": entry["path"],
                    "group": entry["group"],
                    "label": entry["label"],
                    "probabilities": [1.0 / len(folds["classes"])] * len(folds["classes"]),
                }
                for entry in entries
            ]
            write_fold_predictions(
                arm_dir,
                repeat=repeat,
                fold=fold,
                arm=arm,
                classes=folds["classes"],
                records=records,
                shuffled_control=False,
                manifest_digest=folds["manifest_digest"],
            )
            (fold_directory(arm_dir, repeat, fold) / COST_FILENAME).write_text(
                json.dumps({"trainings": 4, "wall_clock_seconds": [1.0, 2.0, 3.0, 4.0]}),
                encoding="utf-8",
            )

    loaded, costs = load_arm_predictions(arm_dir, folds)

    assert len(loaded) == folds["repeats"] * folds["k"]
    assert costs[(0, 0)]["trainings"] == 4


# --- ablation_registers_no_contrast ------------------------------------------


def test_ablation_registers_no_contrast():
    """The gate's pre-registered families stay exactly what SPEC 0044 fixed."""
    contrasts = load_config()["evaluation"]["contrasts"]
    registered = {entry["name"] for entry in contrasts}

    assert registered == {
        "cnn_vs_control",
        "descriptors_vs_control",
        "encoder_probe_vs_control",
        "encoder_probe_vs_descriptors",
    }

    named_arms = {arm for entry in contrasts for arm in entry["arms"]}
    assert named_arms.isdisjoint(ABLATION_ARMS)


def test_no_ablation_contrast_carries_a_registered_family():
    """A family name would put a diagnostic inside the gate's correction."""
    groups = [f"g{index}" for index in range(12)]
    scored = {
        BASE_ARM: correctness(groups, wrong=groups[:2]),
        **{arm: correctness(groups, wrong=groups[:4]) for arm in ABLATION_ARMS},
    }

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    assert report["contrasts"]
    for contrast in report["contrasts"]:
        assert contrast["family"] == "ablation"


# --- ablation_is_corrected_within_its_own_family -----------------------------


def test_ablation_is_corrected_within_its_own_family():
    """Holm runs over the four contrasts and says the size it corrected for."""
    groups = [f"g{index}" for index in range(30)]
    scored = {BASE_ARM: correctness(groups, wrong=groups[:3])}
    for offset, arm in enumerate(ABLATION_ARMS):
        scored[arm] = correctness(groups, wrong=groups[: 4 + offset * 3])

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    assert len(report["contrasts"]) == len(ABLATION_ARMS)
    for contrast in report["contrasts"]:
        assert contrast["family_size"] == len(ABLATION_ARMS)
        assert contrast["p_value_holm"] >= contrast["p_value"]


def test_the_correction_is_read_rather_than_the_raw_p_value():
    """Significance is decided on the corrected value, or the family is a fiction."""
    contrast = {
        "p_value": 0.01,
        "p_value_holm": 0.30,
        "alpha": ALPHA,
        "observed_difference": 0.30,
        "minimum_detectable_effect": 0.16,
    }

    from src.ablation import read_contrast

    assert read_contrast(contrast)["reading"]["cell"].startswith("not_significant")


# --- ablation_reads_a_difference_only_above_the_minimum_detectable_effect ----


def test_ablation_reads_a_difference_only_above_the_minimum_detectable_effect():
    """Both clauses, the discipline SPEC 0044 applies to every number it reads."""
    carries = reading_cell(significant=True, observed=0.30, mde=0.16)
    assert carries["carries_signal"] is True

    for significant, observed in ((True, 0.02), (False, 0.30), (False, 0.02)):
        cell = reading_cell(significant=significant, observed=observed, mde=0.16)
        assert cell["carries_signal"] is False


def test_a_contrast_with_no_rejection_region_is_not_a_measured_difference():
    """`None` is the experiment saying it can detect nothing, not a floor of zero."""
    cell = reading_cell(significant=True, observed=0.50, mde=None)

    assert cell["carries_signal"] is False


def test_every_contrast_records_its_own_minimum_detectable_effect():
    groups = [f"g{index}" for index in range(20)]
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        scored[arm] = correctness(groups, wrong=groups[:6])

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    for contrast in report["contrasts"]:
        assert "minimum_detectable_effect" in contrast
        assert contrast["pairs"] == len(groups)


# --- ablation_names_a_group_that_did_not_run ---------------------------------


def test_ablation_names_a_group_that_did_not_run():
    """An absent arm is recorded, and every other contrast is still computed."""
    groups = [f"g{index}" for index in range(15)]
    absent = ablation_arm_name(GROUPS[1])
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        if arm != absent:
            scored[arm] = correctness(groups, wrong=groups[:5])

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    assert [entry["arm"] for entry in report["not_executed"]] == [absent]
    assert report["not_executed"][0]["group"] == GROUPS[1]
    computed = {contrast["arms"][1] for contrast in report["contrasts"]}
    assert absent not in computed
    assert len(computed) == len(ABLATION_ARMS) - 1


def test_an_absent_base_arm_refuses_rather_than_reporting_nothing():
    """Without the full arm there is no pair to read, and silence would hide it."""
    groups = [f"g{index}" for index in range(10)]
    scored = {arm: correctness(groups) for arm in ABLATION_ARMS}

    with pytest.raises(ValueError, match=BASE_ARM):
        ablation_contrasts(scored, alpha=ALPHA, power=POWER)


def test_the_correction_is_applied_over_what_was_computed():
    """Holm's family is the contrasts that exist, not the arms that were planned."""
    groups = [f"g{index}" for index in range(15)]
    absent = ablation_arm_name(GROUPS[2])
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        if arm != absent:
            scored[arm] = correctness(groups, wrong=groups[:5])

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    for contrast in report["contrasts"]:
        assert contrast["family_size"] == len(ABLATION_ARMS) - 1


# --- ablation_report_names_what_it_does_not_clear ----------------------------


def test_ablation_report_names_what_it_does_not_clear(tmp_path):
    """The report says in its own words that no cell of it decides a ship."""
    groups = [f"g{index}" for index in range(12)]
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        scored[arm] = correctness(groups, wrong=groups[:5])
    computed = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    report = write_ablation_report(
        tmp_path / ABLATION_DIRNAME,
        version="v1",
        manifest_digest=FIXTURE_DIGEST,
        contrasts=computed["contrasts"],
        not_executed=computed["not_executed"],
        seeds={"0": 42},
        runtimes={BASE_ARM: {"device": "CPU"}},
    )

    assert report["spec"] == "0065"
    assert report["base_arm"] == BASE_ARM
    assert report["reading_rule"] == READING_RULE
    assert "decision rule" in report["licence"]
    assert "diagnostic" in report["licence"]

    written = json.loads(
        (tmp_path / ABLATION_DIRNAME / ABLATION_REPORT_FILENAME).read_text(
            encoding="utf-8"
        )
    )
    assert written == report


def test_the_report_is_written_whichever_way_it_reads(tmp_path):
    """A diagnostic that found nothing is still committed with its numbers."""
    groups = [f"g{index}" for index in range(12)]
    scored = {arm: correctness(groups) for arm in (BASE_ARM, *ABLATION_ARMS)}
    computed = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    report = write_ablation_report(
        tmp_path / ABLATION_DIRNAME,
        version="v1",
        manifest_digest=FIXTURE_DIGEST,
        contrasts=computed["contrasts"],
        not_executed=computed["not_executed"],
        seeds={"0": 42},
        runtimes={},
    )

    assert report["carries_signal"] == []
    assert (tmp_path / ABLATION_DIRNAME / ABLATION_REPORT_FILENAME).is_file()
