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


def test_golden_generation_is_deterministic():
    first = generator.render(generator.build_golden())
    second = generator.render(generator.build_golden())
    assert first == second
    assert first == GOLDEN_PATH.read_text(encoding="utf-8"), (
        "the committed golden is not what the generator writes; rerun it"
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
