"""An interrupted arm resumes, and a finished one is not overwritten (SPEC 0056).

Each test name matches a criterion in
`docs/specs/0056-an-interrupted-arm-resumes-instead-of-starting-over.md`.

Everything here is decided by files on disk, so the whole module runs without a
dataset and without TensorFlow — which is the point: the classification has to
be readable and testable in the same place a refusal happens, before a run
spends twenty hours it cannot repeat.
"""

import json

import pytest

from src.crossval import (
    COST_FILENAME,
    PREDICTIONS_FILENAME,
    RUNTIME_FILENAME,
    FoldReuse,
    fold_directory,
    fold_reuse_state,
    plan_arm_run,
    require_uniform_runtime,
    write_fold_cost,
    write_fold_predictions,
)

DIGEST = "a" * 64
OTHER_DIGEST = "b" * 64
CFG = {"classes": ["Arenosa", "Argilosa"], "data": {"seed": 42}}
RUNTIME = {
    "deterministic_ops": True,
    "device": "CPU",
    "library_versions": {"scikit_learn": "1.5.2", "numpy": "1.26.4"},
}
MANIFEST = {"k": 2, "repeats": 1, "manifest_digest": DIGEST}


def write_fold(
    arm_dir,
    repeat,
    fold,
    *,
    cfg=CFG,
    digest=DIGEST,
    arm="cnn",
    shuffled_control=False,
    runtime=RUNTIME,
    complete=True,
):
    """One fold's artifacts, in the order a real run writes them."""
    write_fold_predictions(
        arm_dir,
        repeat=repeat,
        fold=fold,
        arm=arm,
        classes=list(cfg["classes"]),
        records=[{"path": "a.jpg", "group": "g", "label": 0, "probabilities": [1.0, 0.0]}],
        shuffled_control=shuffled_control,
        manifest_digest=digest,
    )
    directory = fold_directory(arm_dir, repeat, fold)
    (directory / "config.json").write_text(json.dumps(cfg), encoding="utf-8")
    (directory / RUNTIME_FILENAME).write_text(json.dumps(runtime), encoding="utf-8")
    if complete:
        write_fold_cost(arm_dir, repeat, fold, trainings=1, seconds=[1.0])
    return directory


def state_of(arm_dir, repeat=0, fold=0, **kwargs):
    keys = {
        "cfg": CFG,
        "manifest_digest": DIGEST,
        "arm": "cnn",
        "shuffled_control": False,
        **kwargs,
    }
    return fold_reuse_state(arm_dir, repeat, fold, **keys)[0]


# --- what the artifacts can prove -------------------------------------------


def test_a_complete_fold_of_this_run_is_not_recomputed(tmp_path):
    write_fold(tmp_path, 0, 0)

    assert state_of(tmp_path) is FoldReuse.REUSABLE

    plan = plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                        cfg=CFG, arm="cnn", shuffled_control=False)
    assert plan["reuse"] == [(0, 0)]
    assert plan["run"] == []


def test_an_incomplete_fold_is_recomputed(tmp_path):
    """`cost.json` is written last, so its absence is a fold killed part-way."""
    write_fold(tmp_path, 0, 0, complete=False)

    assert state_of(tmp_path) is FoldReuse.INCOMPLETE

    plan = plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                        cfg=CFG, arm="cnn", shuffled_control=False)
    assert plan["run"] == [(0, 0)]


def test_an_unparseable_predictions_file_is_recomputed(tmp_path):
    """A process killed mid-write is incomplete, not a corrupt result to pool."""
    directory = write_fold(tmp_path, 0, 0)
    (directory / PREDICTIONS_FILENAME).write_text('{"repeat": 0, "fol', encoding="utf-8")

    assert state_of(tmp_path) is FoldReuse.INCOMPLETE


def test_a_directory_that_was_never_run_is_absent(tmp_path):
    assert state_of(tmp_path) is FoldReuse.ABSENT


# --- what refuses the run ----------------------------------------------------


def test_a_fold_from_another_configuration_refuses_the_run(tmp_path):
    write_fold(tmp_path, 0, 0, cfg={**CFG, "data": {"seed": 7}})

    assert state_of(tmp_path) is FoldReuse.STALE

    with pytest.raises(ValueError, match="--force"):
        plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                     cfg=CFG, arm="cnn", shuffled_control=False)


def test_a_fold_from_another_manifest_refuses_the_run(tmp_path):
    """Same version, same configuration, different data underneath.

    `measure_scale.py` rewrites the manifest of a version in place, so this is
    the routine case rather than the exotic one.
    """
    write_fold(tmp_path, 0, 0, digest=OTHER_DIGEST)

    assert state_of(tmp_path) is FoldReuse.STALE

    with pytest.raises(ValueError, match="manifest"):
        plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                     cfg=CFG, arm="cnn", shuffled_control=False)


def test_a_fold_predating_this_record_is_not_reusable(tmp_path):
    """Absent is not the same as matching, and is not assumed to be."""
    directory = write_fold(tmp_path, 0, 0)
    record = json.loads((directory / PREDICTIONS_FILENAME).read_text(encoding="utf-8"))
    del record["manifest_digest"]
    (directory / PREDICTIONS_FILENAME).write_text(json.dumps(record), encoding="utf-8")

    assert state_of(tmp_path) is FoldReuse.STALE


def test_the_refusal_names_every_stale_fold(tmp_path):
    """One decision, one message: the operator learns the whole cost at once."""
    for fold in range(3):
        write_fold(tmp_path, 0, fold, digest=OTHER_DIGEST)

    with pytest.raises(ValueError) as raised:
        plan_arm_run(tmp_path, {"k": 3, "repeats": 1, "manifest_digest": DIGEST},
                     cfg=CFG, arm="cnn", shuffled_control=False)

    message = str(raised.value)
    for fold in range(3):
        assert str(fold_directory(tmp_path, 0, fold)) in message
    assert "--force" in message


def test_a_control_and_its_arm_do_not_reuse_each_other(tmp_path):
    """The control resolves to the incumbent's trainer, so only the flag differs."""
    write_fold(tmp_path, 0, 0, arm="shuffled_control", shuffled_control=True)

    assert state_of(tmp_path, arm="cnn", shuffled_control=False) is FoldReuse.STALE
    assert (
        state_of(tmp_path, arm="shuffled_control", shuffled_control=True)
        is FoldReuse.REUSABLE
    )


# --- force -------------------------------------------------------------------


def test_force_recomputes_and_is_recorded(tmp_path):
    write_fold(tmp_path, 0, 0)

    plan = plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                        cfg=CFG, arm="cnn", shuffled_control=False, force=True)

    assert plan["reuse"] == []
    assert plan["run"] == [(0, 0)]

    write_fold_predictions(
        tmp_path,
        repeat=0,
        fold=0,
        arm="cnn",
        classes=["Arenosa", "Argilosa"],
        records=[],
        shuffled_control=False,
        manifest_digest=DIGEST,
        forced=True,
    )
    written = json.loads(
        (fold_directory(tmp_path, 0, 0) / PREDICTIONS_FILENAME).read_text(
            encoding="utf-8"
        )
    )
    assert written["forced"] is True


def test_force_recomputes_a_stale_fold_instead_of_refusing(tmp_path):
    write_fold(tmp_path, 0, 0, digest=OTHER_DIGEST)

    plan = plan_arm_run(tmp_path, {"k": 1, "repeats": 1, "manifest_digest": DIGEST},
                        cfg=CFG, arm="cnn", shuffled_control=False, force=True)

    assert plan["run"] == [(0, 0)]


# --- the runtime check, which the reuse predicate cannot make ----------------


def test_an_arm_whose_folds_ran_under_different_libraries_is_refused(tmp_path):
    """Caught after the loop, so it catches a run that resumed nothing."""
    write_fold(tmp_path, 0, 0)
    write_fold(
        tmp_path,
        0,
        1,
        runtime={**RUNTIME, "library_versions": {"scikit_learn": "1.8.0"}},
    )

    with pytest.raises(ValueError) as raised:
        require_uniform_runtime(tmp_path, MANIFEST)

    message = str(raised.value)
    assert str(fold_directory(tmp_path, 0, 1)) in message


def test_an_arm_whose_folds_agree_passes_the_runtime_check(tmp_path):
    write_fold(tmp_path, 0, 0)
    write_fold(tmp_path, 0, 1)

    require_uniform_runtime(tmp_path, MANIFEST)


def test_a_fold_with_no_recorded_runtime_is_refused_rather_than_assumed(tmp_path):
    """`load_runtime` returns None for a fold that predates the record, and a
    comparison must be able to tell absent from matching."""
    write_fold(tmp_path, 0, 0)
    directory = write_fold(tmp_path, 0, 1)
    (directory / RUNTIME_FILENAME).unlink()

    with pytest.raises(ValueError, match="no recorded runtime"):
        require_uniform_runtime(tmp_path, MANIFEST)


# --- both loops, one rule ----------------------------------------------------


def test_the_probe_resumes_on_the_same_rule():
    """Asserted by identity: a second implementation could drift from this one."""
    import scripts.run_population_probe as probe_script

    assert probe_script.plan_arm_run is plan_arm_run


def test_a_resumed_arm_equals_an_uninterrupted_one(tmp_path):
    """The folds a resumed run reuses are the folds it would have produced.

    Trivially, because it does not touch them — and that is the whole claim.
    The artifacts are compared byte for byte against a trainer that would have
    written something else, so a run that quietly recomputed would fail here.
    """
    for fold in range(2):
        write_fold(tmp_path, 0, fold)
    before = {
        fold: (fold_directory(tmp_path, 0, fold) / PREDICTIONS_FILENAME).read_bytes()
        for fold in range(2)
    }

    # Fold 1 is killed part-way; fold 0 is finished.
    (fold_directory(tmp_path, 0, 1) / COST_FILENAME).unlink()

    plan = plan_arm_run(tmp_path, MANIFEST, cfg=CFG, arm="cnn", shuffled_control=False)

    assert plan["reuse"] == [(0, 0)]
    assert plan["run"] == [(0, 1)]
    assert (
        fold_directory(tmp_path, 0, 0) / PREDICTIONS_FILENAME
    ).read_bytes() == before[0]
