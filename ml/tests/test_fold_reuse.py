"""An interrupted arm resumes, and a finished one is not overwritten (SPEC 0056).

Each test name matches a criterion in
`docs/specs/0056-an-interrupted-arm-resumes-instead-of-starting-over.md`.

Everything here is decided by files on disk, so the whole module runs without a
dataset and without TensorFlow — which is the point: the classification has to
be readable and testable in the same place a refusal happens, before a run
spends twenty hours it cannot repeat.
"""

import json
from pathlib import Path

import pytest

from src.crossval import (
    COST_FILENAME,
    PREDICTIONS_FILENAME,
    RUNTIME_FILENAME,
    FoldReuse,
    begin_fold,
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


def test_every_arm_trainer_accepts_the_forced_flag():
    """`run_arm` passes `forced` to whatever `fold_trainer_for` returns.

    A structural test rather than a behavioural one, because the failure is a
    `TypeError` raised twenty hours into a forced run — after the arm that does
    accept it has already finished, and on the arm nobody has run yet.
    """
    import inspect

    from src.crossval import ARM_TRAINERS, fold_trainer_for

    missing = [
        arm
        for arm in ARM_TRAINERS
        if "forced" not in inspect.signature(fold_trainer_for(arm)).parameters
    ]

    assert missing == []


# --- the completion marker is invalidated before it can lie ------------------


def test_a_recomputation_clears_the_completion_marker_first(tmp_path):
    """Otherwise an interrupted forced run leaves a fold that looks finished.

    A forced trainer overwrites `config.json` and `runtime.json` before it
    writes predictions. Killed in between, the fold keeps the **old**
    `predictions.json` and the **old** `cost.json` beside the **new**
    `config.json` — and the next run classifies it REUSABLE, pooling
    predictions from one configuration under the record of another. Clearing
    the marker first makes that state INCOMPLETE, which is what it is.
    """
    write_fold(tmp_path, 0, 0)
    assert state_of(tmp_path) is FoldReuse.REUSABLE

    begin_fold(tmp_path, 0, 0)

    assert state_of(tmp_path) is FoldReuse.INCOMPLETE


def test_clearing_the_marker_of_a_fold_that_never_ran_is_not_an_error(tmp_path):
    begin_fold(tmp_path, 0, 0)

    assert state_of(tmp_path) is FoldReuse.ABSENT


def test_no_trainer_starts_with_a_completion_marker_still_there(tmp_path, monkeypatch):
    """The property, asserted where it has to hold: inside the trainer call.

    `begin_fold` living in the loop is an implementation detail; that the marker
    is already gone when a fold begins is the contract, and it is what stops the
    window above from reopening if the loop is ever rearranged.
    """
    from src import crossval as crossval_module
    from tests.test_fold_provenance import build, write_config

    _, folds = build(tmp_path, k=2, repeats=1)
    config_path = write_config(tmp_path, k=2, repeats=1)
    arm_dir = Path(tmp_path) / "models" / "v1" / "cnn"
    write_fold(
        arm_dir, 0, 0, cfg=CFG, digest=folds["manifest_digest"], arm="cnn"
    )
    seen = []

    def fake_fold(cfg, fold_manifest, *, arm_dir, arm, repeat, fold, **kwargs):
        seen.append(
            (fold_directory(arm_dir, repeat, fold) / COST_FILENAME).exists()
        )
        write_fold(
            arm_dir,
            repeat,
            fold,
            cfg=cfg,
            digest=fold_manifest["manifest_digest"],
            arm=arm,
        )
        return {}

    monkeypatch.setattr(
        crossval_module, "ARM_TRAINERS", {"cnn": lambda: fake_fold}
    )
    # `run_arm` imports it inside the call, so the module it comes from is what
    # has to be patched; patching the importer would silently not take.
    from src import dataset as dataset_module

    monkeypatch.setattr(dataset_module, "verify_images", lambda *a, **k: None)

    crossval_module.run_arm("v1", "cnn", config_path, force=True)

    assert seen and not any(seen), "a trainer began on a fold still marked finished"


# --- the single-fold entry point is the path CI actually uses ---------------


def _single_fold_train(monkeypatch, tmp_path, *, force=False, calls=None):
    """Drive `train.train` with the trainer replaced, as test_crossval.py does."""
    from src import crossval as crossval_module
    from src import train as train_module

    def fake_fold(cfg, fold_manifest, **kwargs):
        (calls if calls is not None else []).append(kwargs)
        return {"ran": True}

    monkeypatch.setattr(
        crossval_module, "ARM_TRAINERS", {"cnn": lambda: fake_fold}
    )
    return train_module.train("v1", 0, 0, "cnn", str(tmp_path / "config.yaml"),
                              force=force)


def test_the_single_fold_entry_point_refuses_a_stale_fold(tmp_path, monkeypatch):
    """It is the path CI dispatches one job per fold to, so it is the path a
    published result comes from — and it had no overwrite protection at all."""
    from src import train as train_module
    from tests.test_fold_provenance import build, write_config

    _, folds = build(tmp_path, k=2, repeats=1)
    write_config(tmp_path, k=2, repeats=1)
    arm_dir = Path(tmp_path) / "models" / "v1" / "cnn"
    write_fold(arm_dir, 0, 0, digest=OTHER_DIGEST, arm="cnn")

    calls = []
    with pytest.raises(ValueError, match="--force"):
        _single_fold_train(monkeypatch, tmp_path, calls=calls)

    assert calls == [], "the trainer ran despite the refusal"
    assert train_module is not None


def test_the_single_fold_entry_point_reuses_a_matching_fold(tmp_path, monkeypatch):
    from tests.test_fold_provenance import build, write_config

    _, folds = build(tmp_path, k=2, repeats=1)
    config_path = write_config(tmp_path, k=2, repeats=1)
    arm_dir = Path(tmp_path) / "models" / "v1" / "cnn"

    from src.config import load_config, resolve_paths

    cfg = resolve_paths(load_config(config_path))
    write_fold(arm_dir, 0, 0, cfg=cfg, digest=folds["manifest_digest"], arm="cnn")

    calls = []
    _single_fold_train(monkeypatch, tmp_path, calls=calls)

    assert calls == [], "a matching fold was recomputed"


def test_a_fold_outside_the_partition_is_refused_rather_than_skipped(tmp_path):
    """An empty plan reads as "nothing to run", which here means "already done".

    `train --repeat 9 --fold 9` would then print that the fold was reused and
    train nothing, exiting zero. A dispatched CI job that trains nothing and
    succeeds is worse than one that fails.
    """
    with pytest.raises(ValueError, match="outside the partition"):
        plan_arm_run(
            tmp_path,
            MANIFEST,
            cfg=CFG,
            arm="cnn",
            shuffled_control=False,
            only=(9, 9),
        )


def test_planning_can_be_restricted_to_one_fold(tmp_path):
    """One rule, one implementation: the single-fold path asks the same planner."""
    write_fold(tmp_path, 0, 0)

    plan = plan_arm_run(
        tmp_path,
        MANIFEST,
        cfg=CFG,
        arm="cnn",
        shuffled_control=False,
        only=(0, 1),
    )

    assert plan["reuse"] == []
    assert plan["run"] == [(0, 1)]


# --- both loops, one rule ----------------------------------------------------


def test_the_probe_resumes_on_the_same_rule():
    """Asserted by identity: a second implementation could drift from this one."""
    import scripts.run_population_probe as probe_script

    assert probe_script.plan_arm_run is plan_arm_run


def _deterministic_arm(monkeypatch, tmp_path, *, dies_on=None, calls=None):
    """Wire `run_arm` to a trainer whose output depends only on the fold.

    A perfect arm, so two runs of one fold are byte-identical and any difference
    between a resumed arm and an uninterrupted one is the resume, not the model.
    """
    from src import crossval as crossval_module
    from src import dataset as dataset_module
    from src.dataset import fold_split

    def fake_fold(cfg, fold_manifest, *, arm_dir, arm, repeat, fold, **kwargs):
        if dies_on is not None and (repeat, fold) == dies_on:
            raise KeyboardInterrupt("the machine went away")
        if calls is not None:
            calls.append((repeat, fold))
        width = len(fold_manifest["classes"])
        records = []
        for entry in fold_split(fold_manifest, repeat, fold)["test"]:
            distribution = [0.0] * width
            distribution[entry["label"]] = 1.0
            records.append(
                {
                    "path": entry["path"],
                    "group": entry["group"],
                    "label": entry["label"],
                    "probabilities": distribution,
                }
            )
        directory = fold_directory(arm_dir, repeat, fold)
        directory.mkdir(parents=True, exist_ok=True)
        (directory / "config.json").write_text(json.dumps(cfg), encoding="utf-8")
        (directory / RUNTIME_FILENAME).write_text(
            json.dumps(RUNTIME), encoding="utf-8"
        )
        write_fold_predictions(
            arm_dir,
            repeat=repeat,
            fold=fold,
            arm=arm,
            classes=fold_manifest["classes"],
            records=records,
            shuffled_control=False,
            manifest_digest=fold_manifest["manifest_digest"],
            forced=kwargs.get("forced", False),
        )
        write_fold_cost(arm_dir, repeat, fold, trainings=1, seconds=[1.0])
        return {}

    monkeypatch.setattr(
        crossval_module, "ARM_TRAINERS", {"cnn": lambda: fake_fold}
    )
    monkeypatch.setattr(dataset_module, "verify_images", lambda *a, **k: None)


def test_a_resumed_arm_pools_the_same_predictions_as_an_uninterrupted_one(
    tmp_path, monkeypatch
):
    """The criterion says pooled predictions, so this asserts pooled predictions.

    An earlier version of this test asserted the plan and the untouched bytes of
    the reused folds, which is the mechanism rather than the claim: a regression
    in what a *recomputed* fold writes, or in how the arm is pooled afterwards,
    would have passed it while the stated equivalence was false.

    So: one arm run in a single pass, and a second run interrupted at its third
    fold and resumed, compared on what `load_arm_predictions` returns for the
    whole arm.
    """
    from src import crossval as crossval_module
    from tests.test_fold_provenance import build, write_config

    _, folds = build(tmp_path, k=2, repeats=2)
    config_path = write_config(tmp_path, k=2, repeats=2)

    one_pass = []
    _deterministic_arm(monkeypatch, tmp_path, calls=one_pass)
    crossval_module.run_arm("uninterrupted", "cnn", config_path)
    assert one_pass == [(0, 0), (0, 1), (1, 0), (1, 1)]
    whole, _ = crossval_module.load_arm_predictions(
        Path(tmp_path) / "models" / "uninterrupted" / "cnn", folds
    )

    _deterministic_arm(monkeypatch, tmp_path, dies_on=(1, 0))
    with pytest.raises(KeyboardInterrupt):
        crossval_module.run_arm("resumed", "cnn", config_path)

    resumed_dir = Path(tmp_path) / "models" / "resumed" / "cnn"
    assert (
        fold_directory(resumed_dir, 0, 0) / PREDICTIONS_FILENAME
    ).is_file(), "the interruption must leave earlier folds behind to resume from"

    after_resume = []
    _deterministic_arm(monkeypatch, tmp_path, calls=after_resume)
    crossval_module.run_arm("resumed", "cnn", config_path)

    # The point of the whole change: the two folds the interruption completed
    # are not trained again. Without this the test would pass just as well on a
    # run that recomputed everything, since the trainer is deterministic.
    assert after_resume == [(1, 0), (1, 1)]

    resumed, _ = crossval_module.load_arm_predictions(resumed_dir, folds)
    assert resumed == whole


def test_a_resumed_arm_equals_an_uninterrupted_one(tmp_path):
    """The mechanism underneath the criterion above: a reused fold is untouched.

    Narrower than `..._pools_the_same_predictions_as_an_uninterrupted_one`, and
    kept because it fails for a different reason — this one localises a quiet
    recomputation to the planner, where that test would only report that the
    arm came out different.
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
