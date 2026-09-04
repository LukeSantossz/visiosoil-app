"""Acceptance criteria for the capture-population probe (SPEC 0055).

Each test name matches a criterion in
`docs/specs/0055-probe-whether-the-capture-population-is-predictable.md`.

The probe asks whether the capture population is recoverable from the same
patches the texture arms see. Its fixtures are rendered dishes, so the whole
suite runs without the archive; the two dataset-gated tests at the end assert the
real `v1` against what the spec's design rests on, and no criterion is covered
only by those.
"""

import json
from pathlib import Path

import pytest

from src.manifest import ARCHIVE_CLASSES, read_manifest
from src.population_probe import (
    POPULATION_PROBE_ARM,
    population_images,
    probe_verdict,
    relabel_by_population,
)

ML_ROOT = Path(__file__).resolve().parents[1]
REAL_VERSION = ML_ROOT / "data" / "datasets" / "v1"

real_only = pytest.mark.skipif(
    not (REAL_VERSION / "manifest.csv").is_file(),
    reason="the ingested version is not present; its images are not tracked",
)


# --- the reading rule, fixed before the run ---------------------------------


def test_the_reading_rule_is_recorded_before_the_run():
    """The predicate is arithmetic, not a judgement made after the number.

    At or below the prior the probe has not demonstrated recoverability and
    SPEC 0040 D6 stands; above it, D6 is a mitigation of unproven sufficiency
    and the record re-opens it. The comparison is on the Wilson lower bound
    because the question is whether predictability was *demonstrated*.
    """
    prior = 0.649

    at_prior = probe_verdict(correct=63, total=97, prior=prior)
    assert at_prior["lower_bound"] <= prior
    assert at_prior["predictable"] is False
    assert "stands" in at_prior["reading"]

    perfect = probe_verdict(correct=97, total=97, prior=prior)
    assert perfect["lower_bound"] > prior
    assert perfect["predictable"] is True
    assert "D6" in perfect["reading"]


def test_a_point_estimate_above_the_prior_is_not_enough():
    """The interval is what makes a small sample honest.

    Seventy of ninety-seven is 72 %, comfortably above the prior as a point
    estimate, and its Wilson lower bound is not. Reading the point estimate
    would re-open SPEC 0040 D6 on a difference this sample cannot resolve.
    """
    verdict = probe_verdict(correct=70, total=97, prior=0.649)

    assert verdict["accuracy"] > 0.649
    assert verdict["lower_bound"] <= 0.649
    assert verdict["predictable"] is False


def test_accuracy_is_reported_against_the_population_prior():
    verdict = probe_verdict(correct=80, total=97, prior=0.649)

    assert set(verdict) >= {
        "accuracy",
        "lower_bound",
        "upper_bound",
        "prior",
        "correct",
        "total",
        "predictable",
        "reading",
    }
    assert verdict["prior"] == 0.649
    assert verdict["correct"] == 80


# --- the population is read, never inferred ---------------------------------


def _version_with_populations(tmp_path, cycle=("A", "B", "C")):
    """A fixture version whose rows carry a capture population.

    `tests.support.write_version` leaves `source_group` empty, and the probe
    refuses that by design, so the column is written here rather than the shared
    fixture being changed for one caller.
    """
    import csv

    from tests.support import write_version

    root = write_version(tmp_path)
    path = root / "manifest.csv"
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
        fields = list(rows[0])
    if "source_group" not in fields:
        fields.append("source_group")
    for index, row in enumerate(rows):
        row["source_group"] = cycle[index % len(cycle)]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    return root



def test_the_population_comes_from_the_manifest_and_is_never_inferred(tmp_path):
    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    for row in manifest.rows:
        assert row.source_group, "the fixture must carry a capture population"

    images = population_images(manifest, refused=())

    assert set(images) == {row.source_group for row in manifest.rows}
    assert sum(len(paths) for paths in images.values()) == len(manifest.rows)


def test_a_photograph_without_a_population_is_refused_by_name(tmp_path):
    """Guessing one from the pixel dimensions is how a diagnostic becomes a
    guess about the thing it is diagnosing."""
    from dataclasses import replace

    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    blanked = replace(manifest, rows=[replace(manifest.rows[0], source_group="")])

    with pytest.raises(ValueError, match="source_group"):
        population_images(blanked, refused=())


def test_a_refused_photograph_is_not_probed_either(tmp_path):
    """The probe reads the patches the arms see, which excludes the refused."""
    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    victim = str(manifest.root / manifest.rows[0].image)

    images = population_images(manifest, refused=(victim,))

    assert victim not in {path for paths in images.values() for path in paths}
    assert sum(len(paths) for paths in images.values()) == len(manifest.rows) - 1


# --- the label is the population --------------------------------------------


def test_relabelling_replaces_the_texture_class_with_the_population():
    entries = [
        {"path": "a.png", "label": 0, "class": "Arenosa", "group": "g1"},
        {"path": "b.png", "label": 3, "class": "Argilosa", "group": "g2"},
    ]
    populations = {"a.png": "C", "b.png": "B"}

    relabelled = relabel_by_population(entries, populations, ["A", "B", "C"])

    assert [entry["label"] for entry in relabelled] == [2, 1]
    assert [entry["class"] for entry in relabelled] == ["C", "B"]
    assert [entry["group"] for entry in relabelled] == ["g1", "g2"]
    assert entries[0]["label"] == 0, "the caller's entries must not be mutated"


def test_a_photograph_with_no_recorded_population_cannot_be_relabelled():
    entries = [{"path": "a.png", "label": 0, "class": "Arenosa", "group": "g1"}]

    with pytest.raises(ValueError, match="a.png"):
        relabel_by_population(entries, {}, ["A", "B", "C"])


# --- what the probe is, and is not ------------------------------------------


def test_the_probe_is_reported_outside_the_contrast_family():
    """A diagnostic about the data takes no correction budget from the arms."""
    from src.config import load_config

    registered = {
        arm
        for contrast in load_config()["evaluation"]["contrasts"]
        for arm in contrast["arms"]
    }

    assert POPULATION_PROBE_ARM not in registered


def test_the_probe_runs_on_the_same_patches_the_arms_see():
    """Asserted by identity rather than by resemblance."""
    from src.arms.descriptors import descriptor_features
    from src.population_probe import probe_featuriser

    assert probe_featuriser is descriptor_features


# --- the real archive, which is what the design rests on --------------------


@real_only
def test_no_sample_group_spans_two_capture_populations():
    """Grouping on `sample_id` can then leak no population across a fold."""
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)

    populations = {}
    for row in manifest.rows:
        populations.setdefault(row.sample_id, set()).add(row.source_group)

    spanning = {
        sample: groups for sample, groups in populations.items() if len(groups) > 1
    }
    assert spanning == {}


@real_only
def test_the_probe_partition_makes_every_population_splittable(tmp_path):
    """Population B is in no E0 fold's test side, which is why this exists.

    All twenty of its groups are train-only under SPEC 0040 D6, so a probe on
    the E0 folds could never be scored on the population it exists to ask about
    — it would answer "can A be told from C", which is not the question.
    """
    from src.config import load_config, resolve_paths
    from src.population_probe import probe_partition

    cfg = resolve_paths(load_config())
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)

    fold_manifest = probe_partition(cfg, manifest, str(tmp_path), refused=())

    assert fold_manifest["counts"]["train_only_groups"] == 0
    scored = set()
    for repeat in range(fold_manifest["repeats"]):
        for group_id, index in fold_manifest["folds"][str(repeat)].items():
            if index is not None:
                scored.add(fold_manifest["groups"][group_id]["class"])
    assert scored == {"A", "B", "C"}


# --- the report the probe commits -------------------------------------------


def test_the_report_carries_each_populations_recall_by_name():
    """A pooled accuracy at the prior hides the finding that would matter.

    A probe that recovers B perfectly and confuses A with C scores about the
    prior overall, and B is the population the whole question is about. So the
    recall of each population is reported by name beside the pooled figure.
    """
    from src.population_probe import population_recall

    pairs = [(1, 1), (1, 1), (1, 1), (0, 2), (2, 0), (2, 2)]

    recall = population_recall(pairs, ["A", "B", "C"])

    assert recall["B"] == pytest.approx(1.0)
    assert recall["A"] == pytest.approx(0.0)
    assert recall["C"] == pytest.approx(0.5)


def test_a_population_with_no_scored_group_is_reported_as_absent():
    """Zero would read as "recovered none of them", which is a different fact."""
    from src.population_probe import population_recall

    recall = population_recall([(0, 0), (2, 2)], ["A", "B", "C"])

    assert recall["B"] is None


def test_the_verdict_is_committed_whichever_way_it_returns(tmp_path):
    """Including when the probe reads at or below the prior."""
    from src.population_probe import write_probe_report

    report = write_probe_report(
        tmp_path,
        version="v1",
        manifest_digest="d" * 64,
        populations=["A", "B", "C"],
        pairs=[(2, 2)] * 63 + [(0, 2)] * 14 + [(1, 2)] * 20,
        prior=0.649,
        seeds={"0": 7},
        library_versions={"scikit-learn": "1.5.2"},
    )

    written = json.loads((tmp_path / "probe.json").read_text(encoding="utf-8"))
    assert written["verdict"]["predictable"] is False
    assert written["recall"]["B"] == pytest.approx(0.0)
    assert written["recall"]["C"] == pytest.approx(1.0)
    assert written["manifest_digest"] == "d" * 64
    assert written["seeds"] == {"0": 7}
    assert written["library_versions"] == {"scikit-learn": "1.5.2"}
    assert written == report


def test_the_report_states_the_reading_rule_it_applied(tmp_path):
    """The predicate travels with the number, so a later reader cannot
    substitute a different one."""
    from src.population_probe import write_probe_report

    report = write_probe_report(
        tmp_path,
        version="v1",
        manifest_digest="d" * 64,
        populations=["A", "B", "C"],
        pairs=[(0, 0)] * 97,
        prior=0.649,
        seeds={},
        library_versions={},
    )

    assert report["verdict"]["predictable"] is True
    assert "Wilson" in report["reading_rule"]
    assert "0.649" in report["reading_rule"] or "prior" in report["reading_rule"]
