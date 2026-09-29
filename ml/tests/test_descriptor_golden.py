"""The descriptor golden the Dart port is held to (SPEC 0077).

`scripts/generate_descriptor_golden.py` writes `test/fixtures/descriptors/
golden.json`, and the Dart suite asserts its port reproduces it. These tests
assert the other half: that the Python reference still reproduces the committed
file, so a change on either side fails the other side's suite.
"""

from __future__ import annotations

import base64
import json
from pathlib import Path

import numpy as np
import pytest

import scripts.generate_descriptor_golden as generator
from src.descriptors import (
    MIN_CYCLES_PER_PATCH,
    SPECTRAL_BANDS,
    describe_patch,
    feature_names,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "descriptors" / "golden.json"

#: SPEC 0030's tolerance, which SPEC 0077 adopts.
RELATIVE = 1e-9
ABSOLUTE = 1e-12


def _golden() -> dict:
    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"{GOLDEN_PATH} is missing; run "
            "`cd ml && python scripts/generate_descriptor_golden.py`"
        )
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


def _plane(entry: dict) -> np.ndarray:
    raw = base64.b64decode(entry["pixels"])
    return np.frombuffer(raw, dtype=np.uint8).reshape(entry["height"], entry["width"])


def _close(actual: float, expected: float) -> bool:
    return abs(actual - expected) <= RELATIVE * abs(expected) + ABSOLUTE


def _mismatches(actual, expected, path: str = "golden") -> list:
    """Where `actual` departs from `expected` (SPEC 0080).

    Floats may differ within the tolerance, because numpy's `log10` and `power`
    give other last digits on another CPU. Everything else, types included, must
    be equal exactly.
    """
    if type(actual) is not type(expected):
        return [f"{path}: {type(actual).__name__} where {type(expected).__name__} was"]
    if isinstance(expected, dict):
        if actual.keys() != expected.keys():
            return [f"{path}: keys {sorted(actual)} against {sorted(expected)}"]
        return [
            found
            for key in expected
            for found in _mismatches(actual[key], expected[key], f"{path}.{key}")
        ]
    if isinstance(expected, list):
        if len(actual) != len(expected):
            return [f"{path}: length {len(actual)} against {len(expected)}"]
        return [
            found
            for index, (item, want) in enumerate(zip(actual, expected))
            for found in _mismatches(item, want, f"{path}[{index}]")
        ]
    same = _close(actual, expected) if isinstance(expected, float) else actual == expected
    return [] if same else [f"{path}: {actual!r} against {expected!r}"]


def test_python_reproduces_the_golden():
    golden = _golden()
    assert golden["feature_names"] == list(feature_names())
    for entry in golden["fixtures"]:
        features = describe_patch(_plane(entry))
        assert len(entry["features"]) == len(features), entry["name"]
        for name, actual, expected in zip(golden["feature_names"], features, entry["features"]):
            assert _close(float(actual), expected), f"{entry['name']}.{name}"
    for shape in golden["band_edges"]:
        edges = generator.band_edges(shape["height"], shape["width"])
        assert len(shape["edges"]) == SPECTRAL_BANDS + 1
        for actual, expected in zip(edges, shape["edges"]):
            assert _close(float(actual), expected), shape


def _nudged(value, ulps: int):
    """`value` with every float moved `ulps` units in the last place."""
    if isinstance(value, dict):
        return {key: _nudged(item, ulps) for key, item in value.items()}
    if isinstance(value, list):
        return [_nudged(item, ulps) for item in value]
    if isinstance(value, float):
        for _ in range(ulps):
            value = float(np.nextafter(value, np.inf))
    return value


def test_golden_comparison_tolerates_last_digit_drift():
    golden = _golden()
    assert _mismatches(_nudged(golden, 3), golden) == []


_SAMPLE = {
    "edges": [2.0, 12.649110640673515],
    "fixtures": [{"name": "ramp", "height": 160, "pixels": "AAEC"}],
}


@pytest.mark.parametrize(
    "change",
    [
        pytest.param(lambda d: d["edges"].__setitem__(1, 12.6491107), id="float"),
        pytest.param(lambda d: d["fixtures"][0].__setitem__("pixels", "AAED"), id="string"),
        pytest.param(lambda d: d["fixtures"][0].__setitem__("height", 161), id="integer"),
        pytest.param(lambda d: d["edges"].__setitem__(0, 2), id="integer_for_a_float"),
        pytest.param(lambda d: d["edges"].append(80.0), id="length"),
        pytest.param(lambda d: d["fixtures"][0].pop("name"), id="missing_key"),
        pytest.param(lambda d: d.__setitem__("spec", "0077"), id="extra_key"),
    ],
)
def test_golden_comparison_catches_a_real_change(change):
    changed = json.loads(json.dumps(_SAMPLE))
    change(changed)
    assert _mismatches(changed, _SAMPLE)


def test_golden_generation_is_deterministic():
    first = generator.render(generator.build_golden())
    second = generator.render(generator.build_golden())
    assert first == second
    mismatches = _mismatches(json.loads(first), _golden())
    assert not mismatches, (
        "the committed golden is not what the generator writes; rerun it: "
        + "; ".join(mismatches[:5])
    )


def _band_map(entry: dict) -> np.ndarray:
    return np.frombuffer(base64.b64decode(entry["bands"]), dtype=np.int8)


def test_python_band_map_follows_the_tie_rule():
    golden = _golden()
    on_an_edge = False
    for shape in golden["band_edges"]:
        height, width = shape["height"], shape["width"]
        reference = generator.python_band_map(height, width)
        assert np.array_equal(reference, generator.tie_rule_band_map(height, width)), shape
        assert np.array_equal(_band_map(shape), reference), shape
        if (height, width) == (160, 160):
            on_an_edge = generator.bins_on_an_interior_edge(height, width) > 0
    assert on_an_edge, "the 160x160 shape puts no bin on an interior edge"


def test_no_fixture_radius_sits_in_the_ambiguous_gap():
    golden = _golden()
    for shape in golden["band_edges"]:
        height, width = shape["height"], shape["width"]
        assert generator.ambiguous_radii(height, width) == 0, shape


def test_golden_exercises_every_degenerate_branch():
    golden = _golden()
    names = golden["feature_names"]
    std = names.index("first_order.std")
    spectral = [names.index(f"spectral.band_{band}") for band in range(SPECTRAL_BANDS)]

    planes = [(_plane(entry), entry["features"]) for entry in golden["fixtures"]]
    assert any(features[std] == 0.0 for _, features in planes), "no zero deviation"
    assert any(
        all(features[index] == 0.0 for index in spectral) for _, features in planes
    ), "no zero banded energy"
    assert any(
        len(np.unique(plane // 16)) == 1 for plane, _ in planes
    ), "no zero GLCM variance"
    assert any(plane.shape[0] != plane.shape[1] for plane, _ in planes), "no non-square"
    smallest = min(min(plane.shape) for plane, _ in planes)
    assert smallest / 2.0 > MIN_CYCLES_PER_PATCH, "a fixture with no band"
