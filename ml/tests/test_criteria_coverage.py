"""SPEC 0043: no acceptance criterion is covered only where the suite skips.

A criterion can hold a passing test that never runs in the configuration the
project ships. `folds_are_stratified_and_group_aware` was verified only against
the git-ignored archive, so it skipped in every CI run and the defect it existed
to prevent reached `main`'s branch.

This module reads the criterion names out of `docs/specs/`, matches them to the
test functions named after them under `ml/tests/`, and fails when every matching
test is gated on the dataset being present. TensorFlow gating is deliberately
not audited: it is absent locally and present in CI, so a TensorFlow-gated test
does run where the project ships.

The rules below are pure and are exercised against fixture specs and fixture
test modules written to temporary directories, so the parser and the matcher are
tested rather than trusted. The verdict over this repository's own specs is
reported as a warning by `test_the_real_spec_verdict_is_reported`, not asserted:
a criterion legitimately added tomorrow must not fail a test written today.
"""

import warnings
from pathlib import Path

import pytest

# --- Fixture documents, so every rule below is exercised on known input ------

FIXTURE_SPEC = """# SPEC: test(ml): a fixture specification

## Scope

- `not_a_criterion_because_it_sits_in_another_section`

## Acceptance Criteria

- `a_backticked_criterion`: the shape most specs use.
- a_bare_criterion_before_a_colon: the other shape specs use.
1. `a_numbered_criterion` - the shape SPEC 0040 uses.
- `pubspec.yaml` declares something; prose, not a criterion.
- `mf check` passes; prose, not a criterion.
- The archive is source material; prose, not a criterion.

## Reproducibility

- `also_not_a_criterion`
"""

FIXTURE_CRITERION = "a_fixture_criterion"

FIXTURE_CRITERION_SPEC = """# SPEC: test(ml): one criterion

## Acceptance Criteria

- `{}`: exercised by the fixture modules below.
""".format(FIXTURE_CRITERION)

GATED_MODULE = '''"""A fixture test module whose only test reads the archive."""


def test_a_fixture_criterion(tmp_path):
    _, folds = real_folds(tmp_path)
    assert folds
'''

UNGATED_COMPANION_MODULE = '''"""A fixture companion that runs without the archive."""


def test_a_fixture_criterion_on_a_synthetic_version(tmp_path):
    assert tmp_path is not None
'''

TENSORFLOW_GATED_MODULE = '''"""A fixture test module gated on TensorFlow alone."""

from tests.support import requires_tensorflow


@requires_tensorflow
def test_a_fixture_criterion():
    assert True
'''


def write(directory, name, text):
    """Write ``text`` to ``name`` under ``directory``, creating it if needed."""
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / name
    path.write_text(text, encoding="utf-8")
    return path


def spec_and_tests(tmp_path, spec, modules):
    """Lay out a fixture spec archive and test tree, and return both roots."""
    specs_dir = tmp_path / "specs"
    tests_dir = tmp_path / "tests"
    write(specs_dir, "0001-fixture.md", spec)
    for name, text in modules.items():
        write(tests_dir, name, text)
    tests_dir.mkdir(parents=True, exist_ok=True)
    return specs_dir, tests_dir


# --- The criteria, one test each --------------------------------------------


def test_criteria_are_read_from_the_spec_archive(tmp_path):
    """The parser is tested against a fixture, not trusted against the repo."""
    specs_dir = tmp_path / "specs"
    write(specs_dir, "0001-fixture.md", FIXTURE_SPEC)

    criteria = criteria_in(specs_dir)

    assert set(criteria) == {
        "a_backticked_criterion",
        "a_bare_criterion_before_a_colon",
        "a_numbered_criterion",
    }
    assert criteria["a_backticked_criterion"] == "0001-fixture.md"


def test_a_criterion_tested_only_behind_the_dataset_gate_fails(tmp_path):
    """One criterion, one test, and that test only runs where the archive is."""
    specs_dir, tests_dir = spec_and_tests(
        tmp_path, FIXTURE_CRITERION_SPEC, {"test_gated.py": GATED_MODULE}
    )

    report = audit(specs_dir, tests_dir)

    assert [entry.criterion for entry in report.gated_only] == [FIXTURE_CRITERION]
    assert report.gated_only[0].tests == ("test_gated.py::test_a_fixture_criterion",)
    message = coverage_failure_message(report)
    assert FIXTURE_CRITERION in message
    assert "test_gated.py::test_a_fixture_criterion" in message
    assert "real_folds" in message


def test_a_criterion_with_one_ungated_test_passes(tmp_path):
    """One ungated test is enough: the criterion is checked where it ships."""
    specs_dir, tests_dir = spec_and_tests(
        tmp_path,
        FIXTURE_CRITERION_SPEC,
        {
            "test_gated.py": GATED_MODULE,
            "test_companion.py": UNGATED_COMPANION_MODULE,
        },
    )

    report = audit(specs_dir, tests_dir)

    assert report.gated_only == []
    assert [entry.criterion for entry in report.covered] == [FIXTURE_CRITERION]
    assert len(report.covered[0].tests) == 2


def test_an_unknown_dataset_skip_reason_fails(tmp_path):
    """A fourth gating mechanism cannot appear and go silently unaudited."""
    tests_dir = tmp_path / "tests"
    write(
        tests_dir,
        "test_unknown_gate.py",
        '''"""A fixture module gating on the archive by its own means."""

import pytest


def test_something(tmp_path):
    if not tmp_path.exists():
        pytest.skip("the ingested dataset is absent from this machine")
''',
    )
    write(
        tests_dir,
        "support.py",
        '''"""A fixture support module holding two of the known mechanisms."""

import pytest

real_only = pytest.mark.skipif(
    True, reason="the ingested version is not present; its images are untracked"
)


def real_manifest_or_skip():
    pytest.skip("no ingested dataset here; it is git-ignored per ADR 0019")
''',
    )
    write(
        tests_dir,
        "test_tensorflow.py",
        '''"""A fixture module skipping for a reason that is not the dataset."""

import pytest


def test_something():
    pytest.skip("TensorFlow is not installed; CI runs these on Python 3.12")
''',
    )

    unaudited = unaudited_dataset_skips_in(tests_dir)

    assert len(unaudited) == 1, unaudited
    assert "test_unknown_gate.py" in unaudited[0]
    assert "the ingested dataset is absent" in unaudited[0]


def test_tensorflow_gating_alone_does_not_fail(tmp_path):
    """CI installs TensorFlow, so a TensorFlow-gated test runs where it ships."""
    specs_dir, tests_dir = spec_and_tests(
        tmp_path,
        FIXTURE_CRITERION_SPEC,
        {"test_tf.py": TENSORFLOW_GATED_MODULE},
    )

    report = audit(specs_dir, tests_dir)

    assert report.gated_only == []
    assert [entry.criterion for entry in report.covered] == [FIXTURE_CRITERION]


def test_a_criterion_with_no_matching_test_is_reported_not_failed(tmp_path):
    """Reporting, not failing, keeps this change from becoming a spec sweep."""
    specs_dir, tests_dir = spec_and_tests(tmp_path, FIXTURE_CRITERION_SPEC, {})

    report = audit(specs_dir, tests_dir)

    assert report.gated_only == []
    assert [entry.criterion for entry in report.unmatched] == [FIXTURE_CRITERION]
    assert coverage_failure_message(report) == ""


def test_the_audit_reports_every_offender_at_once(tmp_path):
    """One failure naming both, as `manifest.py` and `ingest.py` report."""
    spec = """# SPEC: test(ml): two criteria

## Acceptance Criteria

- `first_fixture_criterion`: gated by the helper.
- `second_fixture_criterion`: gated by the marker.
"""
    module = '''"""Two fixture tests, each gated by a different mechanism."""

from tests.support import real_only


def test_first_fixture_criterion(tmp_path):
    _, folds = real_folds(tmp_path)
    assert folds


@real_only
def test_second_fixture_criterion():
    assert True
'''
    specs_dir, tests_dir = spec_and_tests(tmp_path, spec, {"test_two.py": module})

    report = audit(specs_dir, tests_dir)

    message = coverage_failure_message(report)
    assert [entry.criterion for entry in report.gated_only] == [
        "first_fixture_criterion",
        "second_fixture_criterion",
    ]
    assert "first_fixture_criterion" in message
    assert "second_fixture_criterion" in message
    assert "real_only" in message


def test_the_audit_runs_without_the_dataset_and_without_tensorflow():
    """The audit is never the thing that skips, so its verdict is always given.

    Asserted against this module's own source rather than against
    `sys.modules`, which carries whatever the rest of the suite imported.
    """
    source = Path(__file__).read_text(encoding="utf-8")
    modules = imported_modules(source)

    assert "tensorflow" not in modules
    assert not [name for name in modules if name.split(".")[0] in {"src", "tests"}], (
        "importing the pipeline or tests.support would give this module the "
        "dataset dependency it exists to audit"
    )
    assert skip_constructs(source) == []


# --- This repository, which the audit reports on rather than asserts over ----


def test_the_repository_has_no_unaudited_dataset_skip():
    """The companion assertion, run for real: `an_unknown_dataset_skip_reason_fails`."""
    unaudited = unaudited_dataset_skips_in(ML_TESTS_DIR)

    assert unaudited == [], (
        "a skip under ml/tests/ names the dataset without using "
        + ", ".join(DATASET_GATES)
        + ", so the audit cannot see it:\n"
        + "\n".join(unaudited)
    )


def test_the_audit_reads_the_real_specs_and_the_real_gates():
    """Guards against a vacuous pass: renaming a gate would check nothing.

    Without this the audit could report a clean archive because it parsed no
    criterion, found no test, or no longer recognised the helper that gates
    them — three ways to pass while checking nothing.
    """
    criteria = criteria_in(SPECS_DIR)
    functions = test_functions_in(ML_TESTS_DIR)

    assert len(criteria) > 100, "no criteria were parsed out of docs/specs/"
    assert len(functions) > 100, "no test functions were parsed out of ml/tests/"
    gated = {gate for function in functions for gate in function.gates}
    assert gated == set(DATASET_GATES), (
        "the audit recognises dataset gating by name; a helper that no test "
        f"uses has been renamed or removed. Found: {sorted(gated)}"
    )


def test_the_real_spec_verdict_is_reported():
    """The verdict is a warning, never a failure.

    A criterion added tomorrow must not fail a test written today, and fixing
    what the audit names is a separate change per this spec's Scope. Warnings
    are rendered by pytest in every run, including CI's `pytest tests/ -v`.
    """
    report = audit(SPECS_DIR, ML_TESTS_DIR)

    warnings.warn(real_spec_verdict(report), CriteriaCoverageWarning, stacklevel=1)
