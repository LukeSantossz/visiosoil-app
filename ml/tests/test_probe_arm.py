"""The fold trainer both new E0 arms are built on (SPEC 0054).

`src.arms.probe.probe_fold` is `train.train_fold`'s signature with a featuriser
in it, so the classical-descriptor arm and the frozen-encoder arm are thin
wrappers around one implementation of the protocol. A contrast between them is
then a statement about the features, and not about which arm's author
remembered to nest the selection.

These tests are written against the featuriser *contract* rather than against
either featuriser: the fake below is arithmetic over a photograph's path, so
nothing here decodes an image, computes a descriptor or loads an encoder.

The failures they exist to make impossible are all silent. A scaler fitted on
everything flatters every arm by the same amount and therefore hides in the
contrasts; a selection that reads its own fold's test groups returns a number
shaped exactly like an honest one; and features pooled across a photograph's
patches write a file of the right length under the right labels.
"""

import hashlib
import json
from pathlib import Path

import numpy as np
import pytest

from src.arms import probe
from src.config import load_config
from src.crossval import (
    COST_FILENAME,
    PREDICTIONS_FILENAME,
    RUNTIME_FILENAME,
    SELECTION_AUDIT_FILENAME,
    fold_directory,
    load_arm_predictions,
    read_fold_metadata,
)
from src.dataset import create_folds, fold_split, inner_folds
from tests.support import configured_classes, requires_tensorflow

#: Two outer folds of one repeat. The protocol runs five by five; what these
#: tests assert is what one fold does and what a completed arm reads back as,
#: neither of which changes with the grid size, and twenty-five folds of a
#: fixture would buy nothing but wall clock.
K = 2
REPEATS = 1
SEED = 42

#: Eight sample groups per class, so each fold's test side holds four of each
#: and its training side still has four — one per inner fold at the configured
#: `inner_k` of four.
GROUPS_PER_CLASS = 8

#: Width of the fake feature vector. Wider than the class count, so a column
#: that carries no class signal exists and standardisation has something to do.
FEATURE_WIDTH = 6

#: Patch counts the fake featuriser hands out, cycled by a photograph's path.
#: Deliberately unequal: every archive photograph yields the same 25 patches, so
#: a constant count cannot fail an off-by-one, a fixed stride, or a slice that
#: reads one photograph's rows twice.
PATCH_COUNTS = (3, 5, 4)

#: The counts the hand-computed aggregation is written for, ascending on
#: purpose. A fixed stride taken from the first photograph's count reads *past*
#: a later photograph's block and is caught; taken from a larger first count it
#: reads past the end of the array instead, numpy clips the slice, and the
#: arithmetic comes out right for the wrong reason.
UNEQUAL_COUNTS = (2, 3, 4)

#: How far apart the fake featuriser puts two classes, against a unit spread.
#: Separable enough that the probe converges, close enough that the choice of
#: `C` is not a foregone conclusion.
CLASS_SEPARATION = 2.5

#: The offset the scaler test gives every test-side photograph. Nothing a real
#: featuriser would produce, which is the point: a scaler that had seen one of
#: these rows could not hide it in a mean.
TEST_SIDE_OFFSET = 1_000_000.0


def _stable_seed(path: str) -> int:
    """A seed for one photograph that does not move between interpreters.

    `hash()` on a string is salted per process, so a fixture built on it would
    give a different feature matrix on every run and the determinism test would
    pass by describing two runs of the same process and nothing else.
    """
    digest = hashlib.blake2b(path.encode("utf-8"), digest_size=8).digest()
    return int.from_bytes(digest, "big")


def _class_of(path: str, classes) -> int:
    """The class index a fake photograph's path encodes.

    Read from the path and never from ``entry["label"]``. A featuriser that
    reached for the label would be reading the answer, and a fixture that did it
    would make every test below pass for the wrong reason.
    """
    slug = Path(path).stem.split("-")[0]
    return [name.replace(" ", "_") for name in classes].index(slug)


def fake_featuriser(entry, cfg):
    """A photograph's patches, as a deterministic function of its path.

    One row per patch and a class-dependent centre, which is what a real
    featuriser produces and all this lane needs to be true of it.
    """
    seed = _stable_seed(entry["path"])
    generator = np.random.default_rng(seed % (2**32))
    count = PATCH_COUNTS[seed % len(PATCH_COUNTS)]
    centre = np.zeros(FEATURE_WIDTH)
    centre[_class_of(entry["path"], cfg["classes"])] = CLASS_SEPARATION
    return centre + generator.normal(0.0, 1.0, size=(count, FEATURE_WIDTH))


def counting_featuriser(counts):
    """A featuriser whose blocks have exactly ``counts`` rows, in entry order."""
    remaining = list(counts)

    def featurise(entry, cfg):
        count = remaining.pop(0)
        return np.full((count, FEATURE_WIDTH), float(count))

    return featurise


def offset_featuriser(offset_paths):
    """`fake_featuriser`, with the named photographs moved far off the others."""

    def featurise(entry, cfg):
        block = fake_featuriser(entry, cfg)
        if entry["path"] in offset_paths:
            block = block + TEST_SIDE_OFFSET
        return block

    return featurise


def _class_images(classes):
    """Fake image paths per class, and the sample each one photographs.

    No file is written and none is opened: `create_folds` groups paths and
    `probe_fold` is called with ``verify=False``, exactly as `run_arm` calls it
    once the images have been verified for the whole run.
    """
    images: dict[str, list[str]] = {}
    sample_ids: dict[str, str] = {}
    for name in classes:
        slug = name.replace(" ", "_")
        paths = []
        for index in range(GROUPS_PER_CLASS):
            sample = f"{slug}-{index}"
            for setting in ("dish", "paper"):
                path = f"images/{sample}_{setting}.jpg"
                paths.append(path)
                sample_ids[path] = sample
        images[name] = paths
    return images, sample_ids


@pytest.fixture
def cfg():
    """The production configuration, read as training reads it.

    Not a fixture dictionary: `probe_fold` reads the seed, the determinism flag,
    `inner_k` and the class list out of it, and a test against a hand-made
    config would stop saying that the shipped one supports the arm.
    """
    return load_config()


@pytest.fixture
def folds(tmp_path, cfg):
    """A fold manifest over synthetic groups of the configured classes."""
    images, sample_ids = _class_images(cfg["classes"])
    return create_folds(
        images,
        k=K,
        repeats=REPEATS,
        seed=SEED,
        splits_dir=str(tmp_path / "splits"),
        sample_ids=sample_ids,
        dataset_version="v-fixture",
        manifest_digest="0" * 64,
    )


@pytest.fixture
def arm_dir(tmp_path):
    return tmp_path / "models" / "v-fixture" / "probe"


def _spy_on_fit(monkeypatch):
    """Record every matrix the probe was fitted on, and fit it for real."""
    calls = []
    real = probe.fit_probe

    def spy(features, labels, **kwargs):
        calls.append(
            {
                "features": np.asarray(features, dtype=np.float64),
                "labels": np.asarray(labels),
                "kwargs": dict(kwargs),
            }
        )
        return real(features, labels, **kwargs)

    monkeypatch.setattr(probe, "fit_probe", spy)
    return calls


def _run(cfg, folds, arm_dir, fold=0, **kwargs):
    """One outer fold of the fixture, with the fake featuriser."""
    kwargs.setdefault("featuriser", fake_featuriser)
    return probe.probe_fold(
        cfg,
        folds,
        arm_dir=arm_dir,
        arm="probe",
        repeat=0,
        fold=fold,
        verify=False,
        **kwargs,
    )


def _read(arm_dir, fold, filename):
    with open(fold_directory(arm_dir, 0, fold) / filename) as handle:
        return json.load(handle)


def _labels_per_photograph(fitted_labels, entries, cfg):
    """Collapse the patch rows the probe was fitted on back to one label each.

    Asserts on the way through that a photograph's patches all carry that
    photograph's label, which is the other half of "patches are the training
    rows": a block whose rows disagreed would mean the labels were assembled out
    of step with the features.
    """
    labels = []
    start = 0
    for entry in entries:
        count = len(fake_featuriser(entry, cfg))
        block = set(fitted_labels[start : start + count])
        assert len(block) == 1, f"{entry['path']} was fitted under {block}"
        labels.append(block.pop())
        start += count
    assert start == len(fitted_labels), "the probe was fitted on unexplained rows"
    return labels


# --- every_arm_writes_the_artifacts_the_protocol_reads ----------------------


@requires_tensorflow
def test_every_arm_writes_the_artifacts_the_protocol_reads(cfg, folds, arm_dir):
    """A completed arm loads back through the protocol's own reader.

    Asserted by reading it, not by listing the files: `load_arm_predictions` is
    what `run_arm` and `evaluate` call, and an artifact that exists but does not
    parse is an arm the gate cannot contrast.
    """
    for fold in range(K):
        runtime = _run(cfg, folds, arm_dir, fold=fold)
        assert set(runtime) >= {"deterministic_ops", "device", "library_versions"}

    for fold in range(K):
        directory = fold_directory(arm_dir, 0, fold)
        for filename in (
            PREDICTIONS_FILENAME,
            COST_FILENAME,
            RUNTIME_FILENAME,
            SELECTION_AUDIT_FILENAME,
        ):
            assert (directory / filename).exists(), (
                f"fold {fold} is missing {filename}; SPEC 0054 requires every "
                "arm to write the four artifacts the protocol reads"
            )

    predictions, costs = load_arm_predictions(arm_dir, folds)

    assert set(predictions) == {(0, fold) for fold in range(K)}
    assert set(costs) == {(0, fold) for fold in range(K)}
    for fold in range(K):
        records = predictions[(0, fold)]
        assert records, "a fold's test side cannot be empty"
        for record in records:
            assert set(record) == {"path", "group", "label", "probabilities"}
            assert isinstance(record["label"], int)
            assert len(record["probabilities"]) == len(cfg["classes"])
            assert all(isinstance(value, float) for value in record["probabilities"])
            np.testing.assert_allclose(sum(record["probabilities"]), 1.0, atol=1e-9)
        assert costs[(0, fold)]["trainings"] >= 1
        assert len(costs[(0, fold)]["wall_clock_seconds"]) == costs[(0, fold)][
            "trainings"
        ]

    metadata = read_fold_metadata(arm_dir, 0, 0)
    assert metadata["arm"] == "probe"
    assert metadata["shuffled_control"] is False
    assert metadata["classes"] == list(cfg["classes"])


@requires_tensorflow
def test_every_photograph_of_the_test_side_is_predicted_exactly_once(
    cfg, folds, arm_dir
):
    """The fold's test side and the fold's predictions are the same photographs."""
    _run(cfg, folds, arm_dir)

    expected = [entry["path"] for entry in fold_split(folds, 0, 0)["test"]]
    written = [record["path"] for record in _read(arm_dir, 0, PREDICTIONS_FILENAME)[
        "predictions"
    ]]

    assert written == expected


# --- each_arm_averages_patch_distributions_into_one_prediction --------------


class _FakeProbe:
    """Returns a fixed block of patch distributions.

    A fitted probe would make the rows unpredictable, and what is under test is
    the arithmetic between `predict_proba` and the record that gets written.
    """

    def __init__(self, rows, classes):
        self.rows = np.asarray(rows, dtype=np.float64)
        self.classes_ = np.asarray(classes)
        self.seen = []

    def predict_proba(self, features):
        self.seen.append(np.asarray(features, dtype=np.float64))
        return self.rows


def _entries(count, classes):
    """``count`` test-side entries in the shape the fold manifest yields."""
    return [
        {
            "path": f"images/{classes[index % len(classes)].replace(' ', '_')}"
            f"-{index}_dish.jpg",
            "group": f"group-{index}",
            "label": index % len(classes),
            "class": classes[index % len(classes)],
        }
        for index in range(count)
    ]


def test_each_arm_averages_patch_distributions_into_one_prediction(cfg):
    """One row per photograph, its distribution the mean over that photograph's
    patches, against a hand-computed value and unequal patch counts.

    Unequal because every archive photograph yields the same 25 patches: a
    fixed stride, an off-by-one and a slice that reads a neighbour's rows all
    survive a constant count and all write a plausible file.
    """
    classes = list(cfg["classes"])
    entries = _entries(3, classes)
    model = _FakeProbe(
        [
            # Photograph 0: columns sum to 1.0, 0.2, 0.4, 0.4 over two patches.
            [0.6, 0.2, 0.1, 0.1],
            [0.4, 0.0, 0.3, 0.3],
            # Photograph 1: columns sum to 1.2, 0.6, 0.6, 0.6 over three.
            [0.9, 0.1, 0.0, 0.0],
            [0.3, 0.3, 0.2, 0.2],
            [0.0, 0.2, 0.4, 0.4],
            # Photograph 2: columns sum to 0.8, 2.2, 0.4, 0.6 over four.
            [0.0, 1.0, 0.0, 0.0],
            [0.2, 0.6, 0.1, 0.1],
            [0.4, 0.2, 0.2, 0.2],
            [0.2, 0.4, 0.1, 0.3],
        ],
        classes=range(len(classes)),
    )

    records = probe._predict(
        model, entries, cfg, counting_featuriser(UNEQUAL_COUNTS)
    )

    assert len(records) == len(entries)
    assert [record["path"] for record in records] == [e["path"] for e in entries]
    assert [record["group"] for record in records] == [e["group"] for e in entries]
    assert [record["label"] for record in records] == [e["label"] for e in entries]
    np.testing.assert_allclose(records[0]["probabilities"], [0.5, 0.1, 0.2, 0.2])
    np.testing.assert_allclose(records[1]["probabilities"], [0.4, 0.2, 0.2, 0.2])
    np.testing.assert_allclose(records[2]["probabilities"], [0.2, 0.55, 0.1, 0.15])


def test_a_photographs_patches_are_scored_and_never_pooled(cfg):
    """Every patch reaches the probe as its own row.

    SPEC 0054 rejects pooling features across a photograph's patches: the
    incumbent averages *distributions*, and an arm that averaged *features*
    would differ from it in the aggregation as well as in the method, so a
    contrast could not attribute a difference to either.
    """
    classes = list(cfg["classes"])
    entries = _entries(3, classes)
    model = _FakeProbe(
        np.full((sum(UNEQUAL_COUNTS), len(classes)), 0.25),
        classes=range(len(classes)),
    )

    probe._predict(model, entries, cfg, counting_featuriser(UNEQUAL_COUNTS))

    assert len(model.seen) == 1
    assert model.seen[0].shape == (sum(UNEQUAL_COUNTS), FEATURE_WIDTH)


def test_a_class_absent_from_the_training_side_is_a_zero_and_not_a_shift(cfg):
    """`predict_proba` has one column per class the probe was fitted on.

    A fold whose training side never saw a class gets a narrower matrix back,
    and writing it as-is would slide every class's probability one column left
    — a wrong distribution under the right label, in a file of the right shape.
    """
    classes = list(cfg["classes"])
    entries = _entries(1, classes)
    model = _FakeProbe([[0.5, 0.3, 0.2]], classes=[0, 2, 3])

    records = probe._predict(model, entries, cfg, counting_featuriser((1,)))

    np.testing.assert_allclose(records[0]["probabilities"], [0.5, 0.0, 0.3, 0.2])


def test_a_featuriser_that_returns_no_patch_for_a_photograph_is_refused(cfg):
    """An empty block averages to NaN, which reads downstream as a prediction."""
    entries = _entries(2, list(cfg["classes"]))
    model = _FakeProbe(np.full((3, len(cfg["classes"])), 0.25), classes=range(4))

    with pytest.raises(ValueError, match="at least one row"):
        probe._predict(model, entries, cfg, counting_featuriser((3, 0)))


def test_a_featuriser_that_changes_its_feature_width_is_refused(cfg):
    """Two widths in one fold cannot both be the feature space the probe fitted."""
    entries = _entries(2, list(cfg["classes"]))

    def ragged(entry, cfg):
        width = FEATURE_WIDTH if entry["group"] == "group-0" else FEATURE_WIDTH + 1
        return np.zeros((2, width))

    model = _FakeProbe(np.full((4, len(cfg["classes"])), 0.25), classes=range(4))

    with pytest.raises(ValueError, match="feature"):
        probe._predict(model, entries, cfg, ragged)


# --- the_probe_is_selected_inside_the_fold ----------------------------------


@requires_tensorflow
def test_the_probe_is_selected_inside_the_fold(cfg, folds, arm_dir):
    """The audit's group ids and the fold's test groups are disjoint."""
    _run(cfg, folds, arm_dir)

    audit = _read(arm_dir, 0, SELECTION_AUDIT_FILENAME)
    test_groups = {entry["group"] for entry in fold_split(folds, 0, 0)["test"]}

    assert audit["leaked_groups"] == []
    assert set(audit["groups_read_during_selection"]) & test_groups == set()
    assert set(audit["test_groups"]) == test_groups
    assert audit["inner_k"] == cfg["evaluation"]["inner_k"]
    assert audit["chosen"]["C"] in audit["chosen"]["c_grid"]
    assert audit["refit_groups"] == len(
        {entry["group"] for entry in fold_split(folds, 0, 0)["train"]}
    )


def test_the_probe_is_selected_inside_the_fold_by_the_criterion_it_records():
    """The tie-break the audit names, checked where a tie can be constructed.

    A run over the fixture separates the classes well enough that the grid
    rarely ties, and the rule only shows itself when it does — so it is pinned
    here rather than left to whichever fold happened to exercise it.
    """
    grid = (0.01, 0.1, 1.0, 10.0)

    assert probe._select(grid, [0.4, 0.9, 0.5, 0.9]) == 0.1
    assert probe._select(grid, [0.5, 0.5, 0.5, 0.5]) == 0.01
    assert probe._select(grid, [0.1, 0.2, 0.3, 0.9]) == 10.0


@requires_tensorflow
def test_the_probe_is_selected_inside_the_fold_without_reading_a_test_group(
    cfg, folds, arm_dir, monkeypatch
):
    """What selection read, and not what the audit says it read.

    The audit is written from the inner splits `inner_folds` returned, so an arm
    that built them honestly and then scored its candidates on the outer test
    side would file a clean audit over groups it had already looked at — the
    optimistic bias ADR 0020 exists to remove, wearing the evidence that it
    did not happen.

    This watches the featurisation instead: every set of photographs the fold
    turns into rows, in call order. Only the last of them, the prediction the
    fold is scored on, may be the test side.
    """
    seen: list[set[str]] = []
    real = probe._patch_matrix

    def spy(entries, config, featuriser, cache=None):
        seen.append({entry["group"] for entry in entries})
        return real(entries, config, featuriser, cache)

    monkeypatch.setattr(probe, "_patch_matrix", spy)

    _run(cfg, folds, arm_dir)

    test_groups = {entry["group"] for entry in fold_split(folds, 0, 0)["test"]}
    assert len(seen) > 2, "the fold selected nothing, so this test asserts nothing"
    assert seen[-1] == test_groups, "the last featurisation is the fold's test side"
    for index, groups in enumerate(seen[:-1]):
        leaked = sorted(groups & test_groups)
        assert not leaked, (
            f"featurisation {index + 1} of {len(seen)} read {leaked} from this "
            "fold's test side; everything before the final prediction is "
            "selection or the refit, and both are the training side's"
        )


@requires_tensorflow
def test_a_leaked_selection_is_refused_before_a_probe_is_fitted(
    cfg, folds, arm_dir, monkeypatch
):
    """Refused before the inner loop, not when the audit is written.

    A check that only fired at write time would have spent the whole selection
    budget fitting on the groups it is about to refuse, and would leave an
    operator who interrupted the run with no record of why (ADR 0020).
    """
    honest = inner_folds(folds, 0, 0, cfg["evaluation"]["inner_k"])
    test_side = fold_split(folds, 0, 0)["test"]

    def leaking_inner_folds(fold_manifest, repeat, fold, inner_k):
        leaked = [dict(split) for split in honest]
        leaked[0] = {
            "train": list(honest[0]["train"]) + test_side[:1],
            "val": list(honest[0]["val"]),
        }
        return leaked

    monkeypatch.setattr(probe, "inner_folds", leaking_inner_folds)
    fits = _spy_on_fit(monkeypatch)

    with pytest.raises(ValueError, match="Nested selection"):
        _run(cfg, folds, arm_dir)

    assert fits == [], "the leak was found only after the probe had been fitted"
    assert not (
        fold_directory(arm_dir, 0, 0) / SELECTION_AUDIT_FILENAME
    ).exists(), "a refused fold must not leave a selection audit behind"


# --- the_scaler_is_fitted_on_the_training_side_only -------------------------


def test_the_standardisation_statistics_come_from_the_features_it_was_fitted_on():
    """The seam, checked against a hand-computed mean and spread."""
    features = np.array(
        [[0.0, 10.0], [2.0, 10.0], [4.0, 16.0], [6.0, 16.0]], dtype=np.float64
    )
    labels = np.array([0, 0, 1, 1])

    pipeline = probe.fit_probe(features, labels, c=1.0)
    scaler = pipeline.named_steps[probe.STANDARDISE_STEP]

    np.testing.assert_allclose(scaler.mean_, [3.0, 13.0])
    np.testing.assert_allclose(scaler.scale_, features.std(axis=0))


@requires_tensorflow
def test_the_scaler_is_fitted_on_the_training_side_only(
    cfg, folds, arm_dir, monkeypatch
):
    """The test side's distribution never reaches a standardisation statistic.

    Made able to fail rather than asserted by inspection: every test-side
    photograph is moved a million units away, so a scaler that had seen one of
    those rows could not produce a mean anywhere near the training side's, and
    the pooled mean is checked to be somewhere the fitted one is not.
    """
    split = fold_split(folds, 0, 0)
    test_paths = {entry["path"] for entry in split["test"]}
    featuriser = offset_featuriser(test_paths)
    fits = _spy_on_fit(monkeypatch)

    _run(cfg, folds, arm_dir, featuriser=featuriser)

    assert fits, "no probe was fitted, so this test asserts nothing"
    for call in fits:
        assert call["features"].max() < TEST_SIDE_OFFSET / 2, (
            "a standardisation statistic was computed over a test-side "
            "photograph; fitting the scaler on everything leaks the test "
            "distribution into every arm at once (SPEC 0054)"
        )

    # The same fixture, pooled, lands somewhere the fitted statistics are not —
    # which is what makes the assertion above a measurement and not a tautology.
    pooled = np.concatenate(
        [np.asarray(featuriser(entry, cfg)) for entry in split["train"] + split["test"]]
    )
    assert pooled.mean() > TEST_SIDE_OFFSET / 4


@requires_tensorflow
def test_a_photograph_contributes_every_one_of_its_patches_as_a_training_row(
    cfg, folds, arm_dir, monkeypatch
):
    """Patches are the rows, each carrying its photograph's label."""
    fits = _spy_on_fit(monkeypatch)

    _run(cfg, folds, arm_dir)

    train_entries = fold_split(folds, 0, 0)["train"]
    expected_rows = sum(
        len(fake_featuriser(entry, cfg)) for entry in train_entries
    )
    expected_labels = [
        entry["label"]
        for entry in train_entries
        for _ in range(len(fake_featuriser(entry, cfg)))
    ]

    refit = fits[-1]
    assert refit["features"].shape == (expected_rows, FEATURE_WIDTH)
    assert refit["labels"].tolist() == expected_labels


# --- the shuffled control permutes the training side only -------------------


@requires_tensorflow
def test_the_shuffled_control_permutes_the_training_side_only(
    cfg, folds, arm_dir, monkeypatch
):
    """The test side's labels are the manifest's, and the training side's are not."""
    fits = _spy_on_fit(monkeypatch)

    _run(cfg, folds, arm_dir, shuffled_control=True)

    split = fold_split(folds, 0, 0)
    records = _read(arm_dir, 0, PREDICTIONS_FILENAME)["predictions"]
    assert [record["label"] for record in records] == [
        entry["label"] for entry in split["test"]
    ], "the control permuted the labels it is scored against"

    # Read back at the photograph level, which is where the permutation acts.
    # The patch-level multiset is not preserved and should not be: photographs
    # yield different numbers of patches, so moving a label between two of them
    # moves a different number of rows with it.
    fitted = _labels_per_photograph(fits[-1]["labels"].tolist(), split["train"], cfg)
    honest = [entry["label"] for entry in split["train"]]

    assert sorted(fitted) == sorted(honest), "a permutation preserves the labels"
    assert fitted != honest, "the training side was not permuted at all"

    by_group: dict[str, set[int]] = {}
    for entry, label in zip(split["train"], fitted, strict=True):
        by_group.setdefault(entry["group"], set()).add(label)
    assert all(len(labels) == 1 for labels in by_group.values()), (
        "labels were permuted across photographs rather than across groups, so "
        "a group carries a mixture and 'these two belong together' is still "
        "learnable on a control that should hold no signal"
    )

    audit = _read(arm_dir, 0, SELECTION_AUDIT_FILENAME)
    assert audit["chosen"]["shuffled_control"] is True
    assert isinstance(audit["chosen"]["permutation_seed"], int)


@requires_tensorflow
def test_the_control_seed_cannot_coincide_with_the_fold_draw(cfg, folds, arm_dir):
    """The permutation is offset away from every repeat and fold seed."""
    from src.train import SHUFFLED_CONTROL_SEED_OFFSET, control_seed

    _run(cfg, folds, arm_dir, shuffled_control=True)

    audit = _read(arm_dir, 0, SELECTION_AUDIT_FILENAME)
    assert audit["chosen"]["permutation_seed"] == control_seed(
        cfg["data"]["seed"], 0, 0
    )
    assert audit["chosen"]["permutation_seed"] > SHUFFLED_CONTROL_SEED_OFFSET


# --- determinism ------------------------------------------------------------


@requires_tensorflow
def test_two_runs_of_one_fold_produce_identical_predictions(cfg, folds, tmp_path):
    """Same fold, same featuriser, same file — or nothing here is comparable."""
    first = tmp_path / "first"
    second = tmp_path / "second"

    _run(cfg, folds, first)
    _run(cfg, folds, second)

    assert _read(first, 0, PREDICTIONS_FILENAME) == _read(
        second, 0, PREDICTIONS_FILENAME
    )
    assert (
        _read(first, 0, SELECTION_AUDIT_FILENAME)["chosen"]
        == _read(second, 0, SELECTION_AUDIT_FILENAME)["chosen"]
    )
