"""The real-photograph descriptor-pipeline golden (SPEC 0177)."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "descriptors" / "pipeline_golden.json"
RELATIVE = 1e-9
ABSOLUTE = 1e-12


def _golden() -> dict:
    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"{GOLDEN_PATH} is missing; run "
            "`cd ml && python scripts/generate_descriptor_pipeline_golden.py`"
        )
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


def test_a_real_photo_vector_has_twenty_six_features():
    golden = _golden()

    assert golden["patches"], "the real photograph produced no patches"
    assert len(golden["mean_features"]) == 26
    assert all(len(patch) == 26 for patch in golden["patches"])


def test_pipeline_golden_records_decoded_rgb_statistics():
    golden = _golden()

    statistics = golden["decoded_rgb_statistics"]
    assert statistics["pixel_count"] == golden["decoded_size"][0] * golden["decoded_size"][1]
    assert len(statistics["mean"]) == len(statistics["std"]) == 3


def test_python_pipeline_golden_reproduces_a_real_photograph():
    golden = _golden()

    from scripts.generate_descriptor_pipeline_golden import describe_pipeline

    actual = describe_pipeline()
    np.testing.assert_allclose(
        actual["patches"],
        golden["patches"],
        rtol=RELATIVE,
        atol=ABSOLUTE,
    )
    np.testing.assert_allclose(
        actual["mean_features"],
        golden["mean_features"],
        rtol=RELATIVE,
        atol=ABSOLUTE,
    )


def test_pipeline_golden_generation_is_deterministic():
    from scripts.generate_descriptor_pipeline_golden import describe_pipeline, render

    first = render(describe_pipeline())
    second = render(describe_pipeline())
    assert first == second
    assert first == GOLDEN_PATH.read_text(encoding="utf-8")
