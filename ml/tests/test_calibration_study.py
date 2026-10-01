"""The cross-fitted calibration study over an arm's stored predictions (SPEC 0098).

The study fits a temperature and conformal thresholds for each fold on the other
folds of its repeat, then scores the fold with them. These tests build
predictions by hand, so what each fold was fitted on can be computed here
independently and compared.
"""

import pytest

from src.calibration import fit_temperature
from src.calibration_study import ALPHAS, calibration_study
from tests.support import configured_classes

CLASSES = configured_classes()
K = 3


def _manifest(repeats=1):
    return {"repeats": repeats, "k": K, "classes": CLASSES}


def _record(group, label, distribution):
    return {"path": f"{group}.jpg", "group": group, "label": label, "probabilities": distribution}


def _predictions(repeats=1):
    """Three folds whose distributions differ, so a fit that saw fold k would
    land somewhere else than one that did not."""
    folds = [
        # Fold 0: confident and right.
        [
            _record("a1", 0, [0.85, 0.05, 0.05, 0.05]),
            _record("a1", 0, [0.80, 0.10, 0.05, 0.05]),
            _record("a2", 1, [0.10, 0.75, 0.10, 0.05]),
            _record("a3", 2, [0.05, 0.10, 0.80, 0.05]),
        ],
        # Fold 1: hesitant and mostly right.
        [
            _record("b1", 3, [0.20, 0.20, 0.20, 0.40]),
            _record("b2", 0, [0.40, 0.30, 0.20, 0.10]),
            _record("b3", 1, [0.30, 0.35, 0.20, 0.15]),
            _record("b3", 1, [0.25, 0.45, 0.15, 0.15]),
        ],
        # Fold 2: confident and often wrong.
        [
            _record("c1", 2, [0.70, 0.10, 0.10, 0.10]),
            _record("c2", 3, [0.10, 0.70, 0.10, 0.10]),
            _record("c3", 0, [0.75, 0.10, 0.10, 0.05]),
            _record("c4", 1, [0.10, 0.10, 0.10, 0.70]),
        ],
    ]
    return {
        (repeat, fold): records
        for repeat in range(repeats)
        for fold, records in enumerate(folds)
    }


def test_nothing_is_scored_on_what_fitted_it():
    predictions = _predictions()
    study = calibration_study(_manifest(), predictions)

    for fold in range(K):
        others = [r for f in range(K) if f != fold for r in predictions[(0, f)]]
        everything = [r for f in range(K) for r in predictions[(0, f)]]
        record = study["repeats"][0]["folds"][fold]

        expected = fit_temperature(
            [r["label"] for r in others], [r["probabilities"] for r in others]
        )
        assert record["temperature"] == pytest.approx(expected)
        assert record["fitted_on"]["photographs"] == len(others)
        assert record["fitted_on"]["groups"] == len({r["group"] for r in others})
        # And the fixture is one where seeing the fold would have mattered.
        leaked = fit_temperature(
            [r["label"] for r in everything], [r["probabilities"] for r in everything]
        )
        assert leaked != pytest.approx(expected), fold


def test_the_study_reports_every_level_and_both_distributions():
    study = calibration_study(_manifest(repeats=2), _predictions(repeats=2))

    assert len(study["repeats"]) == 2
    for repeat in study["repeats"]:
        assert repeat["photographs"] == 12
        assert repeat["groups"] == 10

        calibration = repeat["calibration"]
        for key in ("raw", "scaled"):
            assert calibration[key]["bins"] == 10
            assert 0.0 <= calibration[key]["expected_calibration_error"] <= 1.0

        conformal = repeat["conformal"]
        assert [level["alpha"] for level in conformal["levels"]] == list(ALPHAS)
        for level in [*conformal["levels"], conformal["matched"]]:
            assert 0.0 <= level["coverage"] <= 1.0
            assert 0.0 <= level["mean_set_size"] <= len(CLASSES)
            shares = level["verdicts"]
            assert set(shares) == {"conclusive", "ambiguous", "insufficient"}
            assert sum(shares.values()) == pytest.approx(1.0)
        assert len(conformal["matched"]["alphas"]) == K

        for key in ("raw", "scaled"):
            incumbent = repeat["incumbent"][key]
            assert 0.0 <= incumbent["coverage"] <= 1.0
            assert sum(incumbent["verdicts"].values()) == pytest.approx(1.0)

    summary = study["summary"]
    assert set(summary["expected_calibration_error"]) == {"raw", "scaled"}
    assert summary["pooled_temperature"]["photographs"] == 24
    assert summary["pooled_temperature"]["temperature"] > 0


def test_the_incumbent_verdicts_read_as_sets_of_the_photographs():
    # One repeat whose every photograph is a clear, right leader: ADR 0011 calls
    # all of them conclusive, the sets are single classes, and all are covered.
    clear = {
        (0, fold): [_record(f"g{fold}{i}", i, [0.97 if j == i else 0.01 for j in range(4)]) for i in range(4)]
        for fold in range(K)
    }
    incumbent = calibration_study(_manifest(), clear)["repeats"][0]["incumbent"]["raw"]

    assert incumbent["verdicts"] == {"conclusive": 1.0, "ambiguous": 0.0, "insufficient": 0.0}
    assert incumbent["coverage"] == 1.0
    assert incumbent["mean_set_size"] == 1.0
    assert incumbent["conclusive_accuracy"] == 1.0
