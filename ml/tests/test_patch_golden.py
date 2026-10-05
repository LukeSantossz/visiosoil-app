"""The patch-grid golden the Dart port is held to (SPEC 0081, ADR 0025).

`scripts/generate_patch_golden.py` writes `test/fixtures/patches/golden.json`,
and the Dart suite asserts its port reproduces it byte for byte. These tests
assert the other half: that `src.patches` and `src.dataset`'s
`_photograph_patches` still reproduce the committed file from its own inputs.
"""

from __future__ import annotations

import base64
import json
import math
from pathlib import Path

import numpy as np
import pytest

import scripts.generate_patch_golden as generator
from src.patches import patch_geometry, resample_to_canonical
from tests.test_descriptor_golden import _mismatches

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "patches" / "golden.json"

#: A patch centre this close to its limit is where Dart's `sqrt` and CPython's
#: `hypot` could disagree about keeping it (SPEC 0081).
HYPOT_MARGIN = 1e-6


def _golden() -> dict:
    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"{GOLDEN_PATH} is missing; run "
            "`cd ml && python scripts/generate_patch_golden.py`"
        )
    return json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))


def _bytes(text: str) -> bytes:
    return base64.b64decode(text)


def test_python_reproduces_the_patch_golden():
    golden = _golden()

    for case in golden["resample"]:
        resized, _ = resample_to_canonical(
            generator.frame_image(case),
            case["measured_mm_per_px"],
            case["canonical_mm_per_px"],
        )
        assert resized.size == (case["out_width"], case["out_height"]), case["name"]
        assert np.asarray(resized).tobytes() == _bytes(case["resampled"]), case["name"]

    for case in golden["luma"]:
        assert generator.python_grey(case["rgb"]) == case["grey"], case

    for case in golden["geometry"]:
        try:
            geometry = patch_geometry(
                region_diameter_px=case["region_diameter_px"],
                input_size=case["patch_px"],
                canonical_mm_per_px=case["canonical_mm_per_px"],
                min_patches=case["min_patches"],
                stride_fraction=case["stride_fraction"],
            )
        except ValueError as refusal:
            assert generator.refusal_name(refusal) == case.get("refusal"), case["name"]
            continue
        assert "refusal" not in case, case["name"]
        assert geometry.count == case["count"], case["name"]
        assert [list(offset) for offset in geometry.offsets] == case["offsets"], case["name"]

    for case in golden["pipeline"]:
        outcome = generator.python_patches(case)
        if isinstance(outcome, str):
            assert outcome == case.get("refusal"), case["name"]
            continue
        assert "refusal" not in case, case["name"]
        assert [patch.tobytes() for patch in outcome] == [
            _bytes(patch) for patch in case["patches"]
        ], case["name"]


def test_patch_golden_generation_is_deterministic():
    first = generator.render(generator.build_golden())
    second = generator.render(generator.build_golden())
    assert first == second
    mismatches = _mismatches(json.loads(first), _golden())
    assert not mismatches, (
        "the committed golden is not what the generator writes; rerun it: "
        + "; ".join(mismatches[:5])
    )


def test_no_geometry_case_sits_on_the_hypot_boundary():
    golden = _golden()
    shapes = [
        (case["region_diameter_px"], case["patch_px"], case["stride_fraction"])
        for case in golden["geometry"]
    ] + [
        (generator.canonical_diameter(case), case["patch_px"], case["stride_fraction"])
        for case in golden["pipeline"]
    ]
    for diameter, patch_px, stride_fraction in shapes:
        stride = patch_px * stride_fraction
        limit = diameter / 2.0 - patch_px * math.sqrt(2.0) / 2.0
        steps = int(abs(limit) // stride) + 1
        # The centred lattice and the half-stride one (SPEC 0141).
        for half in (0.0, 0.5):
            for row in range(-steps - 1, steps + 1):
                for column in range(-steps - 1, steps + 1):
                    distance = math.hypot((row + half) * stride, (column + half) * stride)
                    assert abs(distance - (limit + 1e-9)) > HYPOT_MARGIN, (
                        diameter,
                        row + half,
                        column + half,
                    )


def test_the_golden_exercises_what_dart_could_get_wrong():
    golden = _golden()
    ratios = [
        case["measured_mm_per_px"] / case["canonical_mm_per_px"]
        for case in golden["resample"]
    ]
    assert 1.0 in ratios, "no case leaves the frame at its scale"
    assert any(ratio < 0.5 for ratio in ratios), "no case reduces by more than half"
    assert any(
        (case["width"] * ratio) % 1.0 == 0.5 or (case["height"] * ratio) % 1.0 == 0.5
        for case, ratio in zip(golden["resample"], ratios)
    ), "no output side rounds half-way"
    assert any(
        (case["out_width"], case["out_height"]) == (case["width"], case["height"])
        and case["measured_mm_per_px"] != case["canonical_mm_per_px"]
        for case in golden["resample"]
    ), "no case resamples to the size it started at"
    assert any(
        (0.299 * r + 0.587 * g + 0.114 * b) % 1.0 == 0.5 for r, g, b in (
            case["rgb"] for case in golden["luma"]
        )
    ), "no luma case lands on .5"
    refusals = {case.get("refusal") for case in golden["pipeline"]}
    assert {
        "too_coarse_to_normalise",
        "region_too_small_for_the_patch_floor",
        "region_not_wholly_photographed",
    } <= refusals, refusals
    assert any("patches" in case for case in golden["pipeline"]), "no case cuts a patch"
