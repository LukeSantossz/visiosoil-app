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
    RUNTIME_FILENAME,
    SELECTION_AUDIT_FILENAME,
    fold_directory,
    fold_trainer_for,
    load_arm_predictions,
    require_uniform_runtime,
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


def test_the_ablation_arm_binds_the_shortened_group_list():
    """It is `probe_fold` with one group taken out, and the test says which.

    White-box on purpose. An arm bound to `[group]` instead of every group but
    it would be leave-one-**in** — a different experiment, filed under a name
    saying the group was removed, and every downstream artifact would look
    right. Nothing else in the suite can tell the two apart.
    """
    from src.arms.descriptors import descriptor_features
    from src.arms.probe import probe_fold

    for arm, group in ABLATION_ARMS.items():
        trainer = fold_trainer_for(arm)
        assert trainer.func is probe_fold

        featuriser = trainer.keywords["featuriser"]
        assert featuriser.func is descriptor_features
        assert featuriser.keywords["groups"] == remaining_groups(group)


def test_registering_the_ablation_arms_overwrites_no_arm_beside_them():
    """The registry merges them in, and a merge is where a name silently wins.

    `descriptors_without_b` is one letter away from the shape these names take,
    so a descriptor group named after a capture population would replace the
    population arm's trainer and nothing would say so.
    """
    from src.crossval import ARM_TRAINERS, merge_arm_trainers

    named_elsewhere = set(ARM_TRAINERS) - set(ABLATION_ARMS)
    assert len(ARM_TRAINERS) == len(named_elsewhere) + len(ABLATION_ARMS)
    assert "descriptors_without_b" in named_elsewhere

    # The registry refuses the collision itself, rather than this test being the
    # only thing standing between a duplicate name and a silently wrong artifact.
    with pytest.raises(ValueError, match="descriptors_without_b"):
        merge_arm_trainers(
            {"descriptors_without_b": lambda: None},
            {"descriptors_without_b": lambda: None},
        )


def test_an_ablation_fold_loads_through_the_protocols_own_loader(tmp_path, folds):
    """A finished fold is read by `load_arm_predictions` like any other arm's.

    The fold is written here rather than trained, and that is what this asserts:
    the layout and the arm name. That an ablation arm *writes* the four
    artifacts is `probe_fold`'s own guarantee, asserted over a synthetic dish by
    `test_probe_arm.py::test_every_arm_writes_the_artifacts_the_protocol_reads`,
    and it transfers because
    `test_the_ablation_arm_binds_the_shortened_group_list` proves these arms are
    that function with a shorter group list.
    """
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
            directory = fold_directory(arm_dir, repeat, fold)
            (directory / COST_FILENAME).write_text(
                json.dumps({"trainings": 4, "wall_clock_seconds": [1.0, 2.0, 3.0, 4.0]}),
                encoding="utf-8",
            )
            # All four artifacts, and not the two `load_arm_predictions` reads.
            # The runner's read path is `require_uniform_runtime` *then* the
            # loader, and the first refuses a fold with no `runtime.json`
            # ("absent is not the same as matching"), so a fixture holding two
            # artifacts would be refused by the very runner this models.
            (directory / RUNTIME_FILENAME).write_text(
                json.dumps({"deterministic_ops": True, "device": "CPU", "gpu_count": 0}),
                encoding="utf-8",
            )
            (directory / SELECTION_AUDIT_FILENAME).write_text(
                json.dumps({"repeat": repeat, "fold": fold, "read_groups": []}),
                encoding="utf-8",
            )

    require_uniform_runtime(arm_dir, folds)
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

    # Against `holm_adjust` of the family's own raw p-values, and not the
    # tautology `p_value_holm >= p_value`: the smallest Holm multiplier is 1, so
    # that inequality holds for a family of one, of four or of forty, and it
    # would pass unchanged if this corrected over the wrong family. The fixture
    # gives each arm a different accuracy so the four p-values differ, which is
    # what makes a family-size error visible rather than a uniform shift.
    from src.stats import holm_adjust

    raw = [contrast["p_value"] for contrast in report["contrasts"]]
    assert len(set(raw)) == len(raw)
    assert [contrast["p_value_holm"] for contrast in report["contrasts"]] == holm_adjust(raw)
    for contrast in report["contrasts"]:
        assert contrast["family_size"] == len(ABLATION_ARMS)


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


# --- the direction a difference had, found by review of PR #241 --------------


def test_a_group_whose_removal_improved_the_arm_does_not_carry_signal():
    """`carries_signal` is a claim about contribution, so it has a direction.

    The first draft read `abs(observed) >= mde` and never looked at the sign, so
    a group whose removal made the arm *better* came back as carrying signal,
    with the reading "the remaining groups do not replace what it contributed".
    The E0 verdict reads that list.
    """
    helped = reading_cell(significant=True, observed=0.30, mde=0.16)
    hurt = reading_cell(significant=True, observed=-0.30, mde=0.16)

    assert helped["carries_signal"] is True
    assert helped["favours"] == "full_arm"

    assert hurt["carries_signal"] is False
    assert hurt["favours"] == "ablated_arm"
    assert hurt["cell"] != helped["cell"]


def test_the_reading_says_which_way_a_resolved_difference_went():
    """A cell that resolved in the ablated arm's favour says so in its prose."""
    hurt = reading_cell(significant=True, observed=-0.30, mde=0.16)

    assert "without" in hurt["reading"] or "better" in hurt["reading"]
    assert "do not replace what it contributed" not in hurt["reading"]


def test_an_absent_arm_carries_the_reason_it_was_absent():
    """Three different failures reach this branch and the record must tell them apart.

    `require_uniform_runtime` refusing an arm whose predictions exist is not
    "no predictions were found for this arm", and the committed artifact is read
    on a machine where the stderr is long gone.
    """
    groups = [f"g{index}" for index in range(10)]
    absent = ablation_arm_name(GROUPS[1])
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        if arm != absent:
            scored[arm] = correctness(groups, wrong=groups[:5])

    report = ablation_contrasts(
        scored,
        alpha=ALPHA,
        power=POWER,
        absent_reasons={absent: "3 fold(s) ran under different libraries"},
    )

    entry = report["not_executed"][0]
    assert entry["arm"] == absent
    assert "different libraries" in entry["note"]


def test_an_absent_arm_with_no_reason_given_still_says_something_true():
    groups = [f"g{index}" for index in range(10)]
    absent = ablation_arm_name(GROUPS[1])
    scored = {BASE_ARM: correctness(groups, wrong=groups[:2])}
    for arm in ABLATION_ARMS:
        if arm != absent:
            scored[arm] = correctness(groups, wrong=groups[:5])

    report = ablation_contrasts(scored, alpha=ALPHA, power=POWER)

    assert report["not_executed"][0]["note"]


def test_the_report_records_what_each_arm_cost(tmp_path):
    """SPEC 0065's contention risk is mitigated by the artifact, or not at all.

    The spec says the report "records the wall clock it observed rather than
    claiming an uncontended figure". `runtimes` carries the device and the
    library versions and no timing, so without this the promise was unkept.
    """
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
        costs={BASE_ARM: {"wall_clock_seconds_total": 3600.0, "trainings": 125}},
    )

    assert report["costs"][BASE_ARM]["wall_clock_seconds_total"] == 3600.0
    assert "contention" in report["cost_note"]


def test_the_descriptor_vocabulary_is_pinned_to_what_the_ablation_covers():
    """A fifth descriptor group changes what every existing ablation fold means.

    `descriptors_without_lbp` means "the other three groups" today and would
    mean "the other four" tomorrow, and nothing a fold records would differ:
    `fold_reuse_state` compares the manifest digest, the arm name, the control
    flag, the partition and `config.json`, and the group list is in none of
    them. So the vocabulary is pinned here, and adding a group fails this test
    rather than silently pairing three-group predictions against a five-group
    base arm.
    """
    assert GROUPS == ("first_order", "spectral", "lbp", "glcm")


# --- the runner, found by review of PR #241 ----------------------------------


def _stub_runner(monkeypatch, tmp_path, *, failing=(), version="v1"):
    """Wire the runner to fake arms, so its control flow is testable without folds.

    Everything the script reads from disk is replaced; what stays real is the
    script's own sequencing, which is what these tests are about.
    """
    import scripts.run_descriptor_ablation as runner

    cfg = {
        "data": {"dataset_version": version, "splits_dir": str(tmp_path / "splits")},
        "evaluation": {"alpha": ALPHA, "power": POWER},
        "export": {"output_dir": str(tmp_path / "models")},
    }
    manifest = {"manifest_digest": FIXTURE_DIGEST, "seeds": {"0": 42}, "k": 1, "repeats": 1}
    groups = [f"g{index}" for index in range(12)]
    calls = []

    def fake_run_arm(run_version, arm, config_path, force=False):
        calls.append({"arm": arm, "force": force, "version": run_version})
        if arm in failing:
            raise failing[arm] if isinstance(failing, dict) else RuntimeError("died")
        return {}

    monkeypatch.setattr(runner, "load_config", lambda path=None: cfg)
    monkeypatch.setattr(runner, "resolve_paths", lambda c: c)
    monkeypatch.setattr(runner, "load_folds_for_config", lambda c, d: manifest)
    monkeypatch.setattr(runner, "run_arm", fake_run_arm)
    monkeypatch.setattr(runner, "require_uniform_runtime", lambda *a, **k: None)
    monkeypatch.setattr(
        runner,
        "load_arm_predictions",
        lambda arm_dir, folds: ({}, {(0, 0): {"trainings": 5, "wall_clock_seconds": [1.0]}}),
    )
    monkeypatch.setattr(runner, "first_runtime", lambda *a, **k: {"device": "CPU"})

    def fake_correctness(predictions, arm_dir=None):
        return correctness(groups, wrong=groups[:3])

    monkeypatch.setattr(runner, "pooled_group_correctness", fake_correctness)
    return runner, calls, tmp_path / "models" / version / ABLATION_DIRNAME


def test_force_never_recomputes_the_gates_own_descriptor_arm(monkeypatch, tmp_path):
    """`--force` on this runner must not reach a pre-registered gate arm.

    SPEC 0065's Scope excludes running the gate's own arms, and `descriptors` is
    one of SPEC 0044's four: `--force` reaching it overwrites finished folds and
    the `metrics.json` the gate's own contrast was computed from.
    """
    runner, calls, _ = _stub_runner(monkeypatch, tmp_path)

    assert runner.main(["--force"]) == 0

    forced = {call["arm"]: call["force"] for call in calls}
    assert forced[BASE_ARM] is False
    assert all(forced[arm] is True for arm in ABLATION_ARMS)


def test_an_arm_that_dies_of_any_exception_is_recorded_not_raised(monkeypatch, tmp_path):
    """The rule is "recorded, not raised", and it held for `ValueError` alone.

    A `FileNotFoundError` from a deleted image, or a `MemoryError` from the
    refit, aborted the whole four-hour diagnostic after burning three of them.
    """
    absent = ablation_arm_name(GROUPS[2])
    runner, _, directory = _stub_runner(
        monkeypatch, tmp_path, failing={absent: MemoryError("out of memory")}
    )

    assert runner.main([]) == 0

    report = json.loads((directory / ABLATION_REPORT_FILENAME).read_text(encoding="utf-8"))
    assert [entry["arm"] for entry in report["not_executed"]] == [absent]
    assert "out of memory" in report["not_executed"][0]["note"]


def test_measuring_nothing_is_not_a_null_result(monkeypatch, tmp_path):
    """Zero contrasts computed is "could not be run", which the exit code says.

    Otherwise the runner prints "groups whose removal changed a scored result:
    none" and exits 0, and a reader concludes the diagnostic found nothing when
    it measured nothing.
    """
    everything = {arm: RuntimeError("no") for arm in ABLATION_ARMS}
    runner, _, directory = _stub_runner(monkeypatch, tmp_path, failing=everything)

    assert runner.main([]) == 1

    report = json.loads((directory / ABLATION_REPORT_FILENAME).read_text(encoding="utf-8"))
    assert report["contrasts"] == []
    assert len(report["not_executed"]) == len(ABLATION_ARMS)


def test_a_partial_run_keeps_the_contrasts_the_previous_run_measured(monkeypatch, tmp_path):
    """`--groups` splits a four-hour run, and the second half must not truncate it.

    `run_d6_sensitivity.py` carries exactly this workflow and exactly this
    guard; the first draft of this runner mirrored the script and dropped it, so
    the second half overwrote the first half's contrasts with entries saying the
    arms were never run — while their predictions sat on disk.
    """
    first_group, second_group = GROUPS[0], GROUPS[1]
    runner, _, directory = _stub_runner(monkeypatch, tmp_path)

    assert runner.main(["--groups", first_group]) == 0
    assert runner.main(["--groups", second_group]) == 0

    report = json.loads((directory / ABLATION_REPORT_FILENAME).read_text(encoding="utf-8"))
    names = {contrast["name"] for contrast in report["contrasts"]}
    assert names == {f"without_{first_group}", f"without_{second_group}"}


def test_the_runner_refuses_a_version_the_configuration_does_not_carry(monkeypatch, tmp_path):
    """`run_arm` reloads the configuration from disk, so `--version` is a lie.

    The write-back reaches this script's own copy and nothing else: `run_arm`
    reads `dataset_version` out of the file. A `--version` that disagrees loads
    one version's folds and files the result under another's name, and the
    refusal it eventually produces names the manifest rather than the flag.
    """
    runner, _, _ = _stub_runner(monkeypatch, tmp_path, version="v1")

    assert runner.main(["--version", "v2"]) == 1


def test_the_runner_carries_forward_with_the_sensitivity_rule(monkeypatch, tmp_path):
    """Asserted by identity: a second implementation could drift from this one."""
    import scripts.run_descriptor_ablation as runner
    from src.sensitivity import carry_forward_contrasts

    assert runner.carry_forward_contrasts is carry_forward_contrasts
