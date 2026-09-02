"""The installed stack has to be the stack `requirements.txt` pins.

This exists because it did not, and CI found out first. `StratifiedGroupKFold`
assigns folds differently across scikit-learn versions, so a suite that passes
outside the pins has verified a configuration the project does not ship. A run
under a divergent stack is not wrong, but it is not evidence either, and it has
to say so rather than reporting a clean pass.

It skips rather than fails when the stack diverges: the pinned TensorFlow, and
therefore the pinned NumPy, have no wheel for every interpreter this repository
is developed on, and turning that into a red suite would hide real failures
behind an environment fact the developer already knows. The skip reason names
both versions, so `pytest -rs` reports it on every local run.
"""

import re
from pathlib import Path

import pytest

REQUIREMENTS = Path(__file__).resolve().parents[1] / "requirements.txt"

#: The two libraries whose version changes the fold assignment. Others in the
#: file matter to the training result; these two matter to which photographs a
#: result was computed on, which is a different kind of wrong.
PINNED_BY_FOLD_ASSIGNMENT = {
    "scikit-learn": "sklearn",
    "numpy": "numpy",
}


def parse_pins(text: str) -> dict[str, list[tuple[str, str]]]:
    """Read `name>=x,<y` lines into a mapping of distribution to constraints."""
    pins: dict[str, list[tuple[str, str]]] = {}
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        match = re.match(r"^([A-Za-z0-9_.\-]+)\s*(.*)$", line)
        if not match:
            continue
        name, rest = match.group(1), match.group(2)
        constraints = []
        for clause in rest.split(","):
            clause = clause.strip()
            if not clause:
                continue
            operator = re.match(r"^(==|>=|<=|!=|<|>|~=)\s*(.+)$", clause)
            if operator:
                constraints.append((operator.group(1), operator.group(2).strip()))
        pins[name.lower()] = constraints
    return pins


def release(version: str) -> tuple[int, ...]:
    """The numeric release part of a version, for ordering.

    Trailing non-numeric segments — a release candidate, a local tag — are
    dropped rather than parsed: `packaging` is not a dependency of this
    pipeline, and ordering the release numbers is all a pin check needs.
    """
    parts: list[int] = []
    for segment in version.split("."):
        digits = re.match(r"^(\d+)", segment)
        if not digits:
            break
        parts.append(int(digits.group(1)))
    return tuple(parts) or (0,)


def satisfies(version: str, constraints: list[tuple[str, str]]) -> bool:
    installed = release(version)
    for operator, bound in constraints:
        limit = release(bound)
        if operator in {"==", "~="} and installed[: len(limit)] != limit:
            return False
        if operator == ">=" and installed < limit:
            return False
        if operator == ">" and installed <= limit:
            return False
        if operator == "<=" and installed > limit:
            return False
        if operator == "<" and installed >= limit:
            return False
        if operator == "!=" and installed == limit:
            return False
    return True


def test_the_pins_this_check_reads_are_the_ones_in_the_file():
    """Guards the parser: a pin it silently failed to read would check nothing."""
    pins = parse_pins(REQUIREMENTS.read_text(encoding="utf-8"))

    for distribution in PINNED_BY_FOLD_ASSIGNMENT:
        assert distribution in pins, f"{distribution} is not pinned in requirements.txt"
        assert pins[distribution], f"{distribution} carries no version constraint"

    assert satisfies("1.5.2", pins["scikit-learn"])
    assert not satisfies("1.8.0", pins["scikit-learn"])
    assert satisfies("1.26.4", pins["numpy"])
    assert not satisfies("2.4.3", pins["numpy"])


def test_the_installed_stack_matches_the_requirements_pins():
    """The fold assignment depends on these versions, so the run has to name them."""
    import importlib

    pins = parse_pins(REQUIREMENTS.read_text(encoding="utf-8"))
    divergent = []
    for distribution, module_name in PINNED_BY_FOLD_ASSIGNMENT.items():
        expected = ",".join(f"{op}{bound}" for op, bound in pins[distribution])
        try:
            module = importlib.import_module(module_name)
        except ImportError:
            # Absent is the widest divergence there is, and it has to be
            # recorded as one rather than raised: an unhandled import error
            # here reports a broken test, not a stack that does not match.
            divergent.append(f"{distribution} is not installed; {expected} required")
            continue
        version = getattr(module, "__version__", "unknown")
        if not satisfies(version, pins[distribution]):
            divergent.append(f"{distribution} {version} does not satisfy {expected}")

    if divergent:
        pytest.skip(
            "the installed stack is outside ml/requirements.txt, so these "
            "results were obtained under a configuration the project does not "
            "ship, and the fold assignment depends on it: " + "; ".join(divergent)
        )
