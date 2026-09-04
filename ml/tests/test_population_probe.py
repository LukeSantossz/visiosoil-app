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

    images = population_images(manifest, refused=(), classes=ARCHIVE_CLASSES)

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
        population_images(blanked, refused=(), classes=ARCHIVE_CLASSES)


def test_a_refused_photograph_is_not_probed_either(tmp_path):
    """The probe reads the patches the arms see, which excludes the refused."""
    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    victim = str(manifest.root / manifest.rows[0].image)

    images = population_images(
        manifest, refused=(victim,), classes=ARCHIVE_CLASSES
    )

    assert victim not in {path for paths in images.values() for path in paths}
    assert sum(len(paths) for paths in images.values()) == len(manifest.rows) - 1


# --- the label is the population --------------------------------------------


def test_the_partition_labels_a_group_by_its_capture_population(tmp_path):
    """`create_folds` takes the population as the key, so it is the label.

    Nothing relabels the entries afterwards, and nothing should: a second
    labelling step that agreed with this one would be redundant and one that
    disagreed would be silent.
    """
    from src.config import load_config, resolve_paths
    from src.population_probe import probe_partition

    cfg = resolve_paths(load_config())
    root = _version_with_populations(tmp_path, cycle=("A", "B"))
    manifest = read_manifest(root, ARCHIVE_CLASSES)

    partition = probe_partition(
        cfg, manifest, str(tmp_path / "splits"), refused={}, classes=ARCHIVE_CLASSES
    )

    labels = {group["class"]: group["label"] for group in partition["groups"].values()}
    assert labels == {"A": 0, "B": 1}


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

    fold_manifest = probe_partition(
        cfg, manifest, str(tmp_path), refused={}, classes=cfg["classes"]
    )

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


# --- the probe sees what the arms see, and nothing else ----------------------


def test_a_class_the_model_never_emits_is_not_probed(tmp_path):
    """The archive holds five groups and the model emits four (ADR 0016).

    `create_folds_for_config` partitions `manifest_class_images(manifest,
    cfg["classes"])`, so no Siltosa photograph is in any arm's fold. A probe
    over the archive vocabulary would score three sample groups the arms never
    see, and would then be answering a question about a larger set than the one
    it exists to describe.
    """
    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    emitted = [name for name in ARCHIVE_CLASSES if name != "Siltosa"]
    unseen = {
        str(manifest.root / row.image)
        for row in manifest.rows
        if row.texture_class == "Siltosa"
    }
    assert unseen, "the fixture must hold a class the model does not emit"

    images = population_images(manifest, refused=(), classes=emitted)

    probed = {path for paths in images.values() for path in paths}
    assert probed.isdisjoint(unseen)
    assert len(probed) == len(manifest.rows) - len(unseen)


def test_the_prior_is_the_share_of_groups_not_of_photographs():
    """The accuracy's unit is the group, so the prior's must be too.

    Here `A` holds five photographs in one group and `B` holds two groups of one.
    Counting photographs makes `A` the majority at 5/7; counting groups — which
    is what the pooled accuracy is over — makes `B` the majority at 2/3.
    Comparing a group-level accuracy against a photograph-level prior compares
    two different quantities, and SPEC 0055 fixed the group-level one.
    """
    from src.population_probe import majority_prior

    fold_manifest = {
        "groups": {
            "A::s1": {"class": "A", "images": ["a1", "a2", "a3", "a4", "a5"]},
            "B::s2": {"class": "B", "images": ["b1"]},
            "B::s3": {"class": "B", "images": ["b2"]},
        }
    }

    assert majority_prior(fold_manifest) == pytest.approx(2 / 3)


def test_the_partition_records_which_photographs_the_grid_refused(tmp_path):
    """A partition short of the version it names has to say which ones left.

    The refusals are filtered out of the images before the draw, so passing them
    on changes no fold. What it changes is the record: without it the probe's
    `splits.json` reports zero refusals over a version that lost eleven
    photographs, and a later reader cannot tell that from a version that lost
    none.
    """
    from src.config import load_config, resolve_paths
    from src.population_probe import probe_partition

    cfg = resolve_paths(load_config())
    root = _version_with_populations(tmp_path)
    manifest = read_manifest(root, ARCHIVE_CLASSES)
    victim = str(manifest.root / manifest.rows[0].image)

    partition = probe_partition(
        cfg,
        manifest,
        str(tmp_path / "splits"),
        {victim: "too_coarse"},
        classes=ARCHIVE_CLASSES,
    )

    assert partition["counts"]["refused_photographs"] == 1
    assert partition["refused"] == {victim: "too_coarse"}
    assert victim not in {
        image
        for group in partition["groups"].values()
        for image in group["images"]
    }


@real_only
def test_the_probe_scores_the_same_sample_groups_the_arms_do(tmp_path):
    """Asserted over the real archive, because that is where the two diverged.

    The arms' partition and the probe's must cover one set of sample groups.
    They differ in what they stratify on and in which groups are splittable —
    that is the whole design — and in nothing else.
    """
    from src.config import load_config, resolve_paths
    from src.dataset import create_folds_for_config
    from src.population_probe import probe_partition, probe_refusals

    cfg = resolve_paths(load_config())
    manifest = read_manifest(REAL_VERSION, ARCHIVE_CLASSES)

    arms = create_folds_for_config(cfg, str(tmp_path / "arms"), manifest=manifest)
    probe = probe_partition(
        cfg,
        manifest,
        str(tmp_path / "probe"),
        probe_refusals(cfg, manifest, cfg["classes"]),
        classes=cfg["classes"],
    )

    assert {group["sample_id"] for group in probe["groups"].values()} == {
        group["sample_id"] for group in arms["groups"].values()
    }
