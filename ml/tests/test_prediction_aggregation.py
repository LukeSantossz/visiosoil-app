"""A photograph is the unit of a prediction, not a patch (SPEC 0053).

Since SPEC 0053 the model scores a grid of patches, so `build_dataset` yields
several rows per photograph and `_predict` has to fold them back into one
distribution before `predictions.json` is written. Everything downstream —
`evaluate.py`, the fold manifest, the contrasts, SPEC 0042's intervals — reads
that file as one row per photograph, so the aggregation is what keeps those
numbers meaning what they say.

The failure these tests exist to make impossible is silent. `zip` over a longer
sequence of model rows stops at the shorter one, so a per-photograph loop over
per-patch rows writes a file of the right shape, full of the first photographs'
first patches, under every photograph's label. Nothing in the artifact says so.
"""

import numpy as np
import pytest

# The training stack is pinned to Python 3.12 and has no wheel for every
# interpreter this repository is developed on, so this module skips rather than
# failing to collect. In CI, where `ml/requirements.txt` is installed, it runs.
tf = pytest.importorskip("tensorflow")

from src import train as train_module  # noqa: E402

#: Placeholder names, not the model's class list. `_predict` never reads one:
#: it slices rows and averages columns, so only the width is load-bearing, and
#: the hand-computed means below are written for this width. Reading the
#: configured list here would tie an arithmetic fixture to a vocabulary that has
#: nothing to say about it (SPEC 0048).
CLASSES = ["A", "B", "C", "D"]

#: Patch counts no archive photograph produces, which is why they are faked
#: here rather than measured. Every dish in the archive is 90 mm and every
#: photograph is resampled to one canonical scale, so the real counts are 25 for
#: all of them — and a constant count cannot fail an off-by-one, a fixed stride,
#: or a slice that reads the same rows twice.
UNEQUAL_COUNTS = (25, 9, 21)


class _FakeModel:
    """Returns a fixed block of patch distributions.

    A real fit would take minutes and would make the rows unpredictable, and
    what is under test is the arithmetic between `model.predict` and the record
    that gets written — not the model.
    """

    def __init__(self, rows):
        self.rows = np.asarray(rows, dtype=np.float64)

    def predict(self, dataset, verbose=0):
        return self.rows


def _entries(count):
    """``count`` test-side entries in the shape the fold manifest yields."""
    return [
        {
            "path": f"images/sample-{index}_dish.jpg",
            "group": f"Arenosa|sample-{index}",
            "label": index % len(CLASSES),
            "class": CLASSES[index % len(CLASSES)],
        }
        for index in range(count)
    ]


def _config():
    return {"classes": list(CLASSES)}


def _stub_patch_counts(monkeypatch, counts):
    """Report ``counts`` instead of measuring a dish, recording what was asked.

    The real function reads a dish diameter out of the dataset manifest, so a
    fixture that let it run would have to carry images and a measured manifest
    to say the one thing these tests need: how many rows belong to which
    photograph.
    """
    calls = []

    def _counts(split_entries, cfg):
        calls.append((split_entries, cfg))
        return list(counts)

    monkeypatch.setattr(train_module, "photograph_patch_counts", _counts)
    return calls


def _stub_build_dataset(monkeypatch):
    """Replace the tf.data pipeline, recording the arguments it was built with."""
    calls = []

    def _build(split_entries, cfg, augment=False, shuffle=False):
        calls.append(
            {
                "entries": split_entries,
                "cfg": cfg,
                "augment": augment,
                "shuffle": shuffle,
            }
        )
        return object()

    monkeypatch.setattr(train_module, "build_dataset", _build)
    return calls


def _rows_per_photograph(distributions, counts):
    """Stack each photograph's distribution ``count`` times, in entry order."""
    rows = []
    for distribution, count in zip(distributions, counts, strict=True):
        rows.extend([list(distribution)] * count)
    return rows


# --- a_prediction_is_written_per_photograph_not_per_patch ------------------


def test_a_prediction_is_written_per_photograph_not_per_patch(monkeypatch):
    """N photographs in, N records out, whatever the patch count.

    The distributions are asserted alongside the count because the count alone
    does not separate the two behaviours: a loop over photographs reading
    per-patch rows also produces three records, and they are the first three
    patches of the first photograph.
    """
    entries = _entries(3)
    distributions = [
        [0.7, 0.1, 0.1, 0.1],
        [0.1, 0.7, 0.1, 0.1],
        [0.1, 0.1, 0.7, 0.1],
    ]
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    _stub_build_dataset(monkeypatch)
    model = _FakeModel(_rows_per_photograph(distributions, UNEQUAL_COUNTS))

    records = train_module._predict(model, entries, _config())

    assert len(records) == len(entries), (
        "predictions.json must hold one row per photograph; it held "
        f"{len(records)} for {len(entries)} photograph(s) over "
        f"{sum(UNEQUAL_COUNTS)} patch(es)"
    )
    assert [record["path"] for record in records] == [e["path"] for e in entries]
    assert [record["group"] for record in records] == [e["group"] for e in entries]
    assert [record["label"] for record in records] == [e["label"] for e in entries]
    for record, expected in zip(records, distributions, strict=True):
        assert len(record["probabilities"]) == len(CLASSES)
        assert all(isinstance(value, float) for value in record["probabilities"])
        np.testing.assert_allclose(record["probabilities"], expected, atol=1e-12)


# --- the distribution written is the mean over that photograph's patches ---


def test_the_distribution_is_the_arithmetic_mean_over_the_patches(monkeypatch):
    """Checked against a hand-computed mean, not against a second run of the code."""
    entries = _entries(2)
    _stub_patch_counts(monkeypatch, (3, 2))
    _stub_build_dataset(monkeypatch)
    model = _FakeModel(
        [
            # Photograph 0: columns sum to 0.9, 0.9, 0.6, 0.6 over three patches.
            [0.6, 0.2, 0.1, 0.1],
            [0.2, 0.4, 0.2, 0.2],
            [0.1, 0.3, 0.3, 0.3],
            # Photograph 1: columns sum to 1.0, 0.0, 0.4, 0.6 over two patches.
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 0.0, 0.4, 0.6],
        ]
    )

    records = train_module._predict(model, entries, _config())

    np.testing.assert_allclose(records[0]["probabilities"], [0.3, 0.3, 0.2, 0.2])
    np.testing.assert_allclose(records[1]["probabilities"], [0.5, 0.0, 0.2, 0.3])


def test_each_photographs_rows_are_sliced_in_order_and_without_overlap(monkeypatch):
    """Unequal counts, so a fixed stride or an off-by-one mixes two photographs.

    Every patch of one photograph carries that photograph's distribution
    exactly, so a slice that starts or ends a row out of place averages in a
    neighbour and the recorded distribution moves off its literal.
    """
    entries = _entries(3)
    distributions = [
        [0.7, 0.1, 0.1, 0.1],
        [0.1, 0.7, 0.1, 0.1],
        [0.1, 0.1, 0.7, 0.1],
    ]
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    _stub_build_dataset(monkeypatch)
    model = _FakeModel(_rows_per_photograph(distributions, UNEQUAL_COUNTS))

    records = train_module._predict(model, entries, _config())

    for record, expected in zip(records, distributions, strict=True):
        np.testing.assert_allclose(record["probabilities"], expected, atol=1e-12)


def test_the_aggregated_distribution_still_sums_to_one(monkeypatch):
    """A mean of distributions is a distribution; nothing renormalises it later."""
    entries = _entries(3)
    generator = np.random.default_rng(11)
    rows = generator.dirichlet(np.ones(len(CLASSES)), size=sum(UNEQUAL_COUNTS))
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    _stub_build_dataset(monkeypatch)

    records = train_module._predict(_FakeModel(rows), entries, _config())

    for record in records:
        assert sum(record["probabilities"]) == pytest.approx(1.0, abs=1e-9)


def test_the_mean_is_taken_rather_than_a_vote_over_the_patches(monkeypatch):
    """The mean and the majority vote disagree here, and the spec chose the mean.

    Two patches of three call Arenosa, and weakly; the third is certain it is
    Media. A vote answers Arenosa, the mean answers Media. SPEC 0053's
    Alternatives Considered is why the mean wins: a patch is a repeated
    measurement of one photograph, not a voter.
    """
    entries = _entries(1)
    patches = np.array(
        [
            [0.5, 0.4, 0.1, 0.0],
            [0.5, 0.4, 0.1, 0.0],
            [0.0, 1.0, 0.0, 0.0],
        ]
    )
    _stub_patch_counts(monkeypatch, (3,))
    _stub_build_dataset(monkeypatch)

    records = train_module._predict(_FakeModel(patches), entries, _config())

    votes = np.bincount(patches.argmax(axis=1), minlength=len(CLASSES))
    assert int(votes.argmax()) == 0, "the fixture no longer separates the two rules"
    assert int(np.argmax(records[0]["probabilities"])) == 1


# --- the row count is verified, never trusted ------------------------------


def test_a_row_count_that_disagrees_with_the_patch_counts_is_refused(monkeypatch):
    """Both directions raise, and the message names both numbers.

    Twenty-five rows is what a `zip` over the photographs would have consumed
    before stopping — the exact shape of the silent truncation.
    """
    entries = _entries(3)
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    _stub_build_dataset(monkeypatch)

    for row_count in (25, 56):
        model = _FakeModel([[0.25, 0.25, 0.25, 0.25]] * row_count)
        with pytest.raises(ValueError) as raised:
            train_module._predict(model, entries, _config())
        message = str(raised.value)
        assert str(row_count) in message
        assert str(sum(UNEQUAL_COUNTS)) in message
        assert "patch" in message.lower()


def test_a_missing_patch_count_is_refused_rather_than_dropping_a_photograph(
    monkeypatch,
):
    """One count per photograph, or the per-entry loop truncates in its turn."""
    entries = _entries(3)
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS[:2])
    _stub_build_dataset(monkeypatch)
    model = _FakeModel([[0.25, 0.25, 0.25, 0.25]] * sum(UNEQUAL_COUNTS[:2]))

    with pytest.raises(ValueError) as raised:
        train_module._predict(model, entries, _config())

    message = str(raised.value)
    assert str(list(UNEQUAL_COUNTS[:2])) in message
    assert str(len(entries)) in message


def test_a_photograph_with_no_patches_is_refused_rather_than_averaged(monkeypatch):
    """An empty slice means a mean over nothing, which is NaN and looks like data.

    The sums still agree here, so only a per-photograph check catches it.
    """
    counts = (25, 0, 21)
    entries = _entries(3)
    _stub_patch_counts(monkeypatch, counts)
    _stub_build_dataset(monkeypatch)
    model = _FakeModel([[0.25, 0.25, 0.25, 0.25]] * sum(counts))

    with pytest.raises(ValueError) as raised:
        train_module._predict(model, entries, _config())

    assert str(list(counts)) in str(raised.value)


# --- the counts come from the module that emits the rows -------------------


def test_the_counts_are_asked_of_the_module_that_emits_the_rows(monkeypatch):
    """`src.dataset` is asked, for these entries and this config.

    Not recomputed here: the count per photograph and the order `build_dataset`
    emits patches in are one guarantee, and a second implementation of the
    arithmetic could agree with the first for years and then not.
    """
    entries = _entries(3)
    cfg = _config()
    calls = _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    _stub_build_dataset(monkeypatch)
    model = _FakeModel([[0.25, 0.25, 0.25, 0.25]] * sum(UNEQUAL_COUNTS))

    train_module._predict(model, entries, cfg)

    assert len(calls) == 1
    asked_entries, asked_cfg = calls[0]
    assert list(asked_entries) == entries
    assert asked_cfg is cfg


def test_the_test_side_is_built_unshuffled_and_unaugmented(monkeypatch):
    """Entry order is the only thing tying a row block to a photograph.

    A shuffle here would leave the record shapes intact and every distribution
    attached to the wrong photograph, which no downstream check would notice.
    """
    entries = _entries(3)
    _stub_patch_counts(monkeypatch, UNEQUAL_COUNTS)
    calls = _stub_build_dataset(monkeypatch)
    model = _FakeModel([[0.25, 0.25, 0.25, 0.25]] * sum(UNEQUAL_COUNTS))

    train_module._predict(model, entries, _config())

    assert len(calls) == 1
    assert calls[0]["shuffle"] is False
    assert calls[0]["augment"] is False
    assert calls[0]["entries"] == entries
