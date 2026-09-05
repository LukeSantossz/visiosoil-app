"""Does the transported population change the answer? (SPEC 0057)

Each test name matches a criterion in
`docs/specs/0057-measure-whether-the-transported-population-changes-the-answer.md`.

The rule is arithmetic over two correctness maps, so almost everything here runs
without a dataset. The dataset-gated tests at the end assert the two properties
the design rests on against the real `v1`: that the two arms of a pair are scored
on identical test sides, and that `B` is in none of them.
"""

import json
from pathlib import Path

import pytest

from src.manifest import ARCHIVE_CLASSES, TRAIN_ONLY_SOURCE_GROUPS, read_manifest
from src.sensitivity import (
    CNN_PAIR,
    DESCRIPTOR_PAIR,
    READING_RULE,
    WITHHELD_POPULATION,
    reading_cell,
    sensitivity_contrast,
    write_sensitivity_report,
)

ML_ROOT = Path(__file__).resolve().parents[1]
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested version is not present; its images are not tracked",
)


# --- the reading rule, exhaustive over four cells ----------------------------


def test_the_reading_rule_is_exhaustive():
    """All four combinations of significance and MDE have a defined reading.

    Two of them were undefined in this spec's first draft, which would have left
    the report with no branch to take and ADR 0021 with an undefined input.
    """
    cells = {
        reading_cell(significant=s, observed=o, mde=0.16)["cell"]
        for s, o in ((True, 0.20), (True, 0.02), (False, 0.20), (False, 0.02))
    }

    assert len(cells) == 4


def test_only_a_significant_difference_at_or_above_the_mde_reopens_d6():
    """Both clauses, which is SPEC 0044's discipline applied here."""
    reopened = reading_cell(significant=True, observed=0.20, mde=0.16)
    assert reopened["d6"] == "re-opened"

    for significant, observed in ((True, 0.02), (False, 0.20), (False, 0.02)):
        stands = reading_cell(significant=significant, observed=observed, mde=0.16)
        assert stands["d6"] == "stands", (significant, observed)


def test_the_three_cells_that_leave_d6_standing_are_not_one_finding():
    """Only one is a clean null; the others are the experiment's own ceiling."""
    clean = reading_cell(significant=False, observed=0.02, mde=0.16)
    ceiling = reading_cell(significant=False, observed=0.20, mde=0.16)
    unsized = reading_cell(significant=True, observed=0.02, mde=0.16)

    assert clean["cell"] != ceiling["cell"] != unsized["cell"]
    assert clean["demonstrated_absence"] is True
    assert ceiling["demonstrated_absence"] is False
    assert unsized["demonstrated_absence"] is False


def test_an_experiment_that_can_detect_nothing_reads_as_below_the_mde():
    """A null MDE is no rejection region at all, not a threshold of zero."""
    cell = reading_cell(significant=True, observed=0.5, mde=None)

    assert cell["d6"] == "stands"
    assert cell["demonstrated_absence"] is False


def test_the_sign_is_reported_and_does_not_change_the_branch():
    favouring_with = reading_cell(significant=True, observed=0.20, mde=0.16)
    favouring_without = reading_cell(significant=True, observed=-0.20, mde=0.16)

    assert favouring_with["d6"] == favouring_without["d6"] == "re-opened"
    assert favouring_with["favours"] != favouring_without["favours"]


# --- the contrast itself ------------------------------------------------------


def _correctness(right, total):
    """A correctness map over ``total`` groups with the first ``right`` correct."""
    return {f"g{index}": index < right for index in range(total)}


def test_the_contrast_is_mcnemar_on_groups_with_its_own_mde():
    contrast = sensitivity_contrast(
        "descriptors_sensitivity",
        _correctness(60, 77),
        _correctness(55, 77),
        alpha=0.05,
        power=0.8,
    )

    assert contrast["pairs"] == 77
    assert contrast["unit"] == "sample group"
    assert "p_value" in contrast
    assert "minimum_detectable_effect" in contrast
    assert contrast["family"] is None, "a diagnostic belongs to no corrected family"


def test_a_contrast_over_different_groups_is_refused():
    """A paired test needs one set of groups; the arms share a partition by
    design, so a mismatch means the design was violated somewhere upstream."""
    with pytest.raises(ValueError, match="same groups"):
        sensitivity_contrast(
            "descriptors_sensitivity",
            {"g0": True, "g1": False},
            {"g0": True, "g2": False},
            alpha=0.05,
            power=0.8,
        )


def test_the_contrast_reuses_evaluates_machinery_rather_than_a_second_copy():
    """Asserted by identity: two implementations of one contrast disagree."""
    from src.evaluate import one_contrast
    from src.sensitivity import _CONTRAST_IMPLEMENTATION

    assert _CONTRAST_IMPLEMENTATION is one_contrast


# --- what the report says -----------------------------------------------------


def _report(tmp_path, **kwargs):
    contrasts = kwargs.pop("contrasts", None)
    if contrasts is None:
        contrasts = [
            sensitivity_contrast(
                "descriptors_sensitivity",
                _correctness(60, 77),
                _correctness(59, 77),
                alpha=0.05,
                power=0.8,
            ),
            sensitivity_contrast(
                "cnn_sensitivity",
                _correctness(62, 77),
                _correctness(61, 77),
                alpha=0.05,
                power=0.8,
            ),
        ]
    return write_sensitivity_report(
        tmp_path,
        version="v1",
        manifest_digest="d" * 64,
        contrasts=contrasts,
        seeds={"0": 42},
        library_versions={"scikit-learn": "1.5.2"},
        **kwargs,
    )


def test_each_contrast_reports_its_own_cell(tmp_path):
    """A null on one arm and a difference on the other is a readable outcome,
    and pooling the two would lose exactly the finding that matters most."""
    report = _report(tmp_path)

    assert len(report["contrasts"]) == 2
    for entry in report["contrasts"]:
        assert entry["reading"]["cell"]
        assert entry["reading"]["d6"] in {"stands", "re-opened"}


def test_d6_is_reopened_if_either_arm_lands_in_the_top_row(tmp_path):
    """An arm that is affected is affected whatever the other arm did."""
    affected = sensitivity_contrast(
        "cnn_sensitivity", _correctness(70, 77), _correctness(40, 77),
        alpha=0.05, power=0.8,
    )
    untouched = sensitivity_contrast(
        "descriptors_sensitivity", _correctness(60, 77), _correctness(60, 77),
        alpha=0.05, power=0.8,
    )

    report = _report(tmp_path, contrasts=[untouched, affected])

    assert report["verdict"]["d6"] == "re-opened"
    assert report["verdict"]["reopened_by"] == ["cnn_sensitivity"]


def test_the_reading_rule_is_recorded_before_the_run(tmp_path):
    report = _report(tmp_path)

    assert "McNemar" in READING_RULE
    assert report["reading_rule"] == READING_RULE


def test_the_licence_is_recorded_with_the_result(tmp_path):
    """Which arms the sensitivity was measured on, so the E0 verdict cannot
    cite it as a general clearance."""
    report = _report(tmp_path)

    assert set(report["measured_arms"]) == set(DESCRIPTOR_PAIR) | set(CNN_PAIR)
    assert "encoder" in report["licence"].lower()


def test_the_result_is_reported_outside_the_contrast_family(tmp_path):
    from src.config import load_config

    registered = {
        arm
        for contrast in load_config()["evaluation"]["contrasts"]
        for arm in contrast["arms"]
    }

    assert DESCRIPTOR_PAIR[1] not in registered
    assert CNN_PAIR[1] not in registered
    assert all(entry["family"] is None for entry in _report(tmp_path)["contrasts"])


def test_the_verdict_is_committed_whichever_way_it_returns(tmp_path):
    report = _report(tmp_path)

    written = json.loads(
        (tmp_path / "sensitivity.json").read_text(encoding="utf-8")
    )
    assert written == report
    assert written["verdict"]["d6"] == "stands"
    assert written["manifest_digest"] == "d" * 64
    assert written["seeds"] == {"0": 42}
    assert written["library_versions"] == {"scikit-learn": "1.5.2"}


# --- the withheld population --------------------------------------------------


def test_the_withheld_population_is_the_one_d6_restricts():
    """Read from the manifest's constant rather than spelled again here."""
    assert TRAIN_ONLY_SOURCE_GROUPS == frozenset({WITHHELD_POPULATION})


def test_withholding_removes_the_population_from_every_training_side():
    """The outer training side and both sides of every inner fold.

    An inner fold still holding a withheld entry would put it back into the
    selection the outer refit is chosen by, and the outer side would look clean
    while the choice was made on contaminated data.
    """
    from src.dataset import withhold_from_training

    def entry(path, group):
        return {"path": path, "group": group, "label": 0, "class": "Arenosa"}

    split = {
        "train": [entry("a.jpg", "g1"), entry("b.jpg", "g2")],
        "test": [entry("c.jpg", "g3")],
    }
    inner = [
        {"train": [entry("a.jpg", "g1")], "val": [entry("b.jpg", "g2")]},
    ]

    kept_split, kept_inner = withhold_from_training(
        split, inner, leaves=lambda e: e["path"] == "b.jpg"
    )

    assert [e["path"] for e in kept_split["train"]] == ["a.jpg"]
    assert [e["path"] for e in kept_split["test"]] == ["c.jpg"], "test side untouched"
    assert [e["path"] for e in kept_inner[0]["train"]] == ["a.jpg"]
    assert kept_inner[0]["val"] == []
    assert len(split["train"]) == 2, "the caller's split must not be mutated"


def test_withholding_nothing_leaves_the_split_alone():
    from src.dataset import withhold_from_training

    split = {"train": [{"path": "a.jpg"}], "test": [{"path": "c.jpg"}]}
    inner = [{"train": [{"path": "a.jpg"}], "val": []}]

    kept_split, kept_inner = withhold_from_training(
        split, inner, leaves=lambda e: False
    )

    assert kept_split == split
    assert kept_inner == inner


# --- both arms of a pair, registered and distinct -----------------------------


def test_every_sensitivity_arm_is_registered_with_a_trainer():
    from src.crossval import ARM_TRAINERS

    for arm in (*DESCRIPTOR_PAIR, *CNN_PAIR):
        assert arm in ARM_TRAINERS, arm


def test_the_two_arms_of_a_pair_are_not_the_same_trainer():
    """The withheld arm differs from its base by the filter and nothing else,
    which means it is a different callable, not the same one."""
    from src.crossval import fold_trainer_for

    assert fold_trainer_for(DESCRIPTOR_PAIR[0]) is not fold_trainer_for(
        DESCRIPTOR_PAIR[1]
    )
    assert fold_trainer_for(CNN_PAIR[0]) is not fold_trainer_for(CNN_PAIR[1])


# --- the real archive, which is what the design rests on ----------------------


@real_only
def test_population_b_is_in_no_test_side_of_either_arm(tmp_path):
    """Asserted rather than assumed: it is D6 that puts it there, and D6 is the
    thing under examination."""
    from src.config import load_config, resolve_paths
    from src.dataset import create_folds_for_config, fold_split

    cfg = resolve_paths(load_config())
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)
    populations = {
        str(manifest.root / row.image): row.source_group for row in manifest.rows
    }

    folds = create_folds_for_config(cfg, str(tmp_path), manifest=manifest)

    for repeat in range(folds["repeats"]):
        for fold in range(folds["k"]):
            scored = fold_split(folds, repeat, fold)["test"]
            assert not any(
                populations[entry["path"]] == WITHHELD_POPULATION for entry in scored
            ), (repeat, fold)


@real_only
def test_the_test_sides_are_identical_fold_by_fold(tmp_path):
    """Both arms read one fold manifest, so this holds by construction — and it
    is the construction the whole comparison rests on, so it is checked."""
    from src.config import load_config, resolve_paths
    from src.dataset import create_folds_for_config, fold_split, withhold_from_training
    from src.manifest import source_groups_by_image

    cfg = resolve_paths(load_config())
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)
    populations = source_groups_by_image(manifest)
    folds = create_folds_for_config(cfg, str(tmp_path), manifest=manifest)

    withheld = 0
    for repeat in range(folds["repeats"]):
        for fold in range(folds["k"]):
            split = fold_split(folds, repeat, fold)
            kept, _ = withhold_from_training(
                split,
                [],
                leaves=lambda e: populations[e["path"]] == WITHHELD_POPULATION,
            )
            assert [e["path"] for e in kept["test"]] == [
                e["path"] for e in split["test"]
            ], (repeat, fold)
            withheld += len(split["train"]) - len(kept["train"])

    assert withheld > 0, "the fixture must actually withhold something"
