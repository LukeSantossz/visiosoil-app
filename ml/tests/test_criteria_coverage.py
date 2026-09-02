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
tested rather than trusted.

The verdict over this repository's own specs is reported as a warning by
`test_the_real_spec_verdict_is_reported`, not asserted. Two reasons, both from
SPEC 0043: a criterion legitimately added tomorrow must not fail a test written
today, and its Scope excludes fixing what the audit names, so an assertion here
would red the suite over work this change is forbidden to do. The change that
fixes those criteria turns that `warnings.warn` into an assertion; no switch is
added for it now, since a switch nothing sets is configuration that has never
been exercised.

Two things here do assert against the repository, because neither can be
falsified by adding a criterion: `test_the_repository_has_no_unaudited_dataset_skip`,
which fails when a fourth gating mechanism appears, and
`test_the_audit_reads_the_real_specs_and_the_real_gates`, which fails when the
audit would report a clean archive because it parsed nothing.
"""

import ast
import re
import warnings
from pathlib import Path
from typing import NamedTuple

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SPECS_DIR = REPOSITORY_ROOT / "docs" / "specs"
ML_TESTS_DIR = Path(__file__).resolve().parent

CRITERIA_HEADING = "## acceptance criteria"

#: The three mechanisms that gate a test on the ingested archive, which is
#: git-ignored per ADR 0019 and therefore absent in CI. `real_folds` wraps
#: `real_manifest_or_skip`, so naming both is what lets the audit read a test
#: that reaches the archive through either one without resolving calls.
DATASET_GATES = ("real_manifest_or_skip", "real_folds", "real_only")

#: Vocabulary that marks a skip reason as being about the archive. A fourth
#: gating mechanism would have to describe itself in one of these words to say
#: honestly what it gates on, which is what makes the companion assertion in
#: `test_the_repository_has_no_unaudited_dataset_skip` worth having.
DATASET_WORDS = ("dataset", "manifest.csv", "ingested", "archive")

SKIP_CALLS = (
    "pytest.skip",
    "pytest.mark.skip",
    "pytest.mark.skipif",
    "pytest.importorskip",
)

#: A criterion is the leading identifier of a list item in the Acceptance
#: Criteria section, either backticked or bare before a colon. Both shapes are
#: in use across `docs/specs/`. Requiring the closing backtick, or the colon, is
#: what keeps a prose bullet such as "`mf check` passes" from reading as one.
CRITERION_ITEM = re.compile(
    r"^\s*(?:[-*]|\d+[a-z]?\.)\s+(?:`([a-z][a-z0-9_]{2,})`|([a-z][a-z0-9_]{2,})(?=:))"
)


class CriteriaCoverageWarning(UserWarning):
    """Carries the audit's verdict over this repository's own specs."""


class SuiteFunction(NamedTuple):
    """A test function and the dataset gates it names."""

    module: str
    name: str
    gates: tuple


class Coverage(NamedTuple):
    """One criterion, the spec that states it, and the tests named after it."""

    criterion: str
    spec: str
    tests: tuple
    gates: tuple


class CoverageReport(NamedTuple):
    """Criteria split by whether a test checks them where the project ships."""

    gated_only: list
    unmatched: list
    covered: list


# --- Pure rules, exercised on the fixtures below rather than trusted --------


def criterion_names(text):
    """The criterion names stated in ``text``'s Acceptance Criteria section."""
    names = []
    in_section = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_section = line.strip().lower() == CRITERIA_HEADING
            continue
        if not in_section:
            continue
        match = CRITERION_ITEM.match(line)
        if match:
            names.append(match.group(1) or match.group(2))
    return names


def criteria_in(specs_dir):
    """Map every criterion under ``specs_dir`` to the spec files stating it."""
    criteria = {}
    for path in sorted(Path(specs_dir).glob("*.md")):
        for name in criterion_names(path.read_text(encoding="utf-8")):
            stated_in = criteria.get(name)
            if stated_in is None:
                criteria[name] = path.name
            elif path.name not in stated_in.split(", "):
                criteria[name] = stated_in + ", " + path.name
    return criteria


def dotted_name(node):
    """The dotted name of ``node`` when it is one, otherwise an empty string."""
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if not isinstance(node, ast.Name):
        return ""
    parts.append(node.id)
    return ".".join(reversed(parts))


def gates_named_in(node):
    """The dataset gates ``node``'s subtree names, in decorators or in calls."""
    named = set()
    for child in ast.walk(node):
        if isinstance(child, ast.Name) and child.id in DATASET_GATES:
            named.add(child.id)
        elif isinstance(child, ast.Attribute) and child.attr in DATASET_GATES:
            named.add(child.attr)
    return tuple(sorted(named))


def named_test_functions(source, module):
    """Every ``test_``-prefixed function in ``source`` and the gates it names."""
    functions = []
    for node in ast.walk(ast.parse(source)):
        is_function = isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        if is_function and node.name.startswith("test_"):
            functions.append(SuiteFunction(module, node.name, gates_named_in(node)))
    return functions


def named_test_functions_in(tests_dir):
    """Every test function under ``tests_dir``, in file then declaration order."""
    functions = []
    for path in sorted(Path(tests_dir).glob("*.py")):
        functions += named_test_functions(path.read_text(encoding="utf-8"), path.name)
    return functions


def imported_modules(source):
    """The module names ``source`` imports, dotted paths included."""
    names = set()
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Import):
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            names.add(node.module)
    return names


def literal_text(node):
    """The literal string ``node`` spells, ignoring interpolated values."""
    if isinstance(node, ast.Constant):
        return node.value if isinstance(node.value, str) else ""
    if isinstance(node, ast.JoinedStr):
        return "".join(literal_text(part) for part in node.values)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return literal_text(node.left) + literal_text(node.right)
    return ""


def skip_reason(call):
    """The reason ``call`` states, or an empty string when it states none."""
    for keyword in call.keywords:
        if keyword.arg == "reason":
            return literal_text(keyword.value)
    if dotted_name(call.func) == "pytest.importorskip":
        # Its positional argument is the module name, not a reason.
        return ""
    return literal_text(call.args[0]) if call.args else ""


def skip_constructs(source):
    """Every pytest skip in ``source``, as ``(line, reason)`` pairs."""
    constructs = []
    for node in ast.walk(ast.parse(source)):
        if isinstance(node, ast.Call) and dotted_name(node.func) in SKIP_CALLS:
            constructs.append((node.lineno, skip_reason(node)))
    return sorted(constructs)


def known_gate_line_spans(source):
    """Line ranges of the definitions of the three known gating mechanisms."""
    spans = []
    for node in ast.walk(ast.parse(source)):
        defines_gate = (
            isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name in DATASET_GATES
        ) or (
            isinstance(node, ast.Assign)
            and any(
                isinstance(target, ast.Name) and target.id in DATASET_GATES
                for target in node.targets
            )
        )
        if defines_gate:
            spans.append((node.lineno, node.end_lineno or node.lineno))
    return spans


def mentions_dataset(reason):
    """Whether ``reason`` describes itself as gating on the archive."""
    lowered = reason.lower()
    return any(word in lowered for word in DATASET_WORDS)


def unaudited_dataset_skips(source, module):
    """Skips in ``source`` that name the dataset outside the known mechanisms."""
    spans = known_gate_line_spans(source)
    unaudited = []
    for line, reason in skip_constructs(source):
        if not mentions_dataset(reason):
            continue
        if any(start <= line <= end for start, end in spans):
            continue
        unaudited.append(
            "{}:{} skips on the dataset without {}: {}".format(
                module, line, " / ".join(DATASET_GATES), reason
            )
        )
    return unaudited


def unaudited_dataset_skips_in(tests_dir):
    """The unaudited dataset skips across every module under ``tests_dir``."""
    unaudited = []
    for path in sorted(Path(tests_dir).glob("*.py")):
        unaudited += unaudited_dataset_skips(
            path.read_text(encoding="utf-8"), path.name
        )
    return unaudited


def criterion_tests(criterion, functions):
    """The tests named after ``criterion``: the exact name, or a suffixed one."""
    prefix = "test_" + criterion
    return [
        function
        for function in functions
        if function.name == prefix or function.name.startswith(prefix + "_")
    ]


def audit(specs_dir, tests_dir):
    """Split every criterion by whether a test checks it where the app ships."""
    criteria = criteria_in(specs_dir)
    functions = named_test_functions_in(tests_dir)
    gated_only, unmatched, covered = [], [], []
    for criterion in sorted(criteria):
        matches = criterion_tests(criterion, functions)
        entry = Coverage(
            criterion,
            criteria[criterion],
            tuple("{}::{}".format(match.module, match.name) for match in matches),
            tuple(sorted({gate for match in matches for gate in match.gates})),
        )
        if not matches:
            unmatched.append(entry)
        elif all(match.gates for match in matches):
            gated_only.append(entry)
        else:
            covered.append(entry)
    return CoverageReport(gated_only, unmatched, covered)


def coverage_failure_message(report):
    """One message naming every offender, or empty when there is none."""
    if not report.gated_only:
        return ""
    lines = [
        "{} criteria are checked only where the dataset is present, so no CI "
        "run has ever verified them:".format(len(report.gated_only))
    ]
    for entry in report.gated_only:
        lines.append("  {} ({})".format(entry.criterion, entry.spec))
        lines.append("    gated by {}".format(", ".join(entry.gates)))
        lines += ["    {}".format(test) for test in entry.tests]
    return "\n".join(lines)


def real_spec_verdict(report):
    """The audit's reading of this repository, for the warnings summary."""
    lines = [
        "SPEC 0043 criteria coverage: {} covered, {} dataset-gated only, "
        "{} with no matching test.".format(
            len(report.covered), len(report.gated_only), len(report.unmatched)
        )
    ]
    if report.gated_only:
        lines.append(coverage_failure_message(report))
    if report.unmatched:
        lines.append(
            "Criteria with no test named after them under ml/tests/, reported "
            "and not failed per this spec's Scope. Most are owned by the Dart "
            "suite under test/, which the Scope excludes; the rest are the "
            "naming convention the Risks section says nothing enforces:"
        )
        by_spec = {}
        for entry in report.unmatched:
            by_spec.setdefault(entry.spec, []).append(entry.criterion)
        for spec in sorted(by_spec):
            lines.append("  {}".format(spec))
            lines += ["    {}".format(name) for name in by_spec[spec]]
    return "\n".join(lines)


# --- Fixture documents, so every rule below is exercised on known input ------

FIXTURE_SPEC = """# SPEC: test(ml): a fixture specification

## Scope

- `not_a_criterion_because_it_sits_in_another_section`

## Acceptance Criteria

- `a_backticked_criterion`: the shape most specs use.
- a_bare_criterion_before_a_colon: the other shape specs use.
1. `a_numbered_criterion` — the shape SPEC 0040 uses.
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
    tests_dir.mkdir(parents=True, exist_ok=True)
    write(specs_dir, "0001-fixture.md", spec)
    for name, text in modules.items():
        write(tests_dir, name, text)
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
    assert FIXTURE_CRITERION in real_spec_verdict(report), (
        "an unmatched criterion has to be printed; a silent one would make "
        "this change the spec sweep its Scope excludes"
    )


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
    functions = named_test_functions_in(ML_TESTS_DIR)

    assert len(criteria) > 100, "no criteria were parsed out of docs/specs/"
    assert len(functions) > 100, "no test functions were parsed out of ml/tests/"

    named_anywhere = set()
    for path in sorted(ML_TESTS_DIR.glob("*.py")):
        if path.name != Path(__file__).name:
            source = path.read_text(encoding="utf-8")
            named_anywhere.update(gates_named_in(ast.parse(source)))
    assert named_anywhere == set(DATASET_GATES), (
        "the audit recognises dataset gating by the three names in "
        "DATASET_GATES; one of them is no longer used under ml/tests/, so it "
        f"has been renamed or removed. Found: {sorted(named_anywhere)}"
    )

    gated_tests = [function for function in functions if function.gates]
    assert gated_tests, (
        "no test function names a dataset gate, so the audit would report "
        "every criterion as covered while checking nothing"
    )


def test_the_real_spec_verdict_is_reported():
    """The verdict is a warning, never a failure.

    A criterion added tomorrow must not fail a test written today, and fixing
    what the audit names is a separate change per this spec's Scope. Warnings
    are rendered by pytest in every run, including CI's `pytest tests/ -v`.
    """
    report = audit(SPECS_DIR, ML_TESTS_DIR)

    warnings.warn(real_spec_verdict(report), CriteriaCoverageWarning, stacklevel=1)
