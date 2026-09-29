"""The descriptor contract's Python half (SPEC 0079).

`src.contract.descriptor_contract` writes the numbers a fitted descriptor
pipeline is, and `lib/core/services/descriptors/descriptor_contract.dart` reads
them. These tests hold the writer to the pipeline it describes and to the
reference descriptors. The Dart suite holds the reader to the committed golden.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from src.arms.probe import fit_probe
from src.config import load_config
from src.contract import CONTRACT_SPEC_VERSION, descriptor_contract
from src.descriptors import (
    GLCM_LEVELS,
    GLCM_OFFSETS,
    LBP_NEIGHBOURS,
    LBP_POINTS,
    MIN_CYCLES_PER_PATCH,
    SPECTRAL_BANDS,
    feature_names,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "contract" / "golden.json"

#: SPEC 0030's tolerance, which SPEC 0079 adopts.
RELATIVE = 1e-9
ABSOLUTE = 1e-12


def _fitted(seed: int = 3, classes: int = 4):
    """A pipeline fitted on seeded synthetic features, one blob per class."""
    rng = np.random.default_rng(seed)
    width = len(feature_names())
    centres = rng.normal(0.0, 2.0, size=(classes, width))
    labels = np.repeat(np.arange(classes), 30)
    features = centres[labels] + rng.normal(0.0, 1.0, size=(len(labels), width))
    return fit_probe(features, labels, c=1.0), rng


def evaluate(contract: dict, patches: np.ndarray) -> np.ndarray:
    """The arithmetic SPEC 0079 fixes, in numpy: one distribution per block."""
    mean = np.asarray(contract["standardiser"]["mean"])
    scale = np.asarray(contract["standardiser"]["scale"])
    weights = np.asarray(contract["regression"]["coefficients"])
    intercepts = np.asarray(contract["regression"]["intercepts"])
    logits = ((np.asarray(patches) - mean) / scale) @ weights.T + intercepts
    logits -= logits.max(axis=1, keepdims=True)
    exponentials = np.exp(logits)
    probabilities = exponentials / exponentials.sum(axis=1, keepdims=True)
    return probabilities.mean(axis=0)


def _contract(pipeline) -> dict:
    return descriptor_contract(
        pipeline, load_config(), model_version="test", dataset_version="v1"
    )


def test_the_writer_reproduces_the_pipeline():
    pipeline, rng = _fitted()
    contract = _contract(pipeline)
    for _ in range(5):
        patches = rng.normal(0.0, 2.0, size=(rng.integers(1, 26), len(feature_names())))
        expected = pipeline.predict_proba(patches).mean(axis=0)
        np.testing.assert_allclose(
            evaluate(contract, patches), expected, rtol=RELATIVE, atol=ABSOLUTE
        )


def test_the_contract_carries_the_reference_fixed_points():
    cfg = load_config()
    contract = _contract(_fitted()[0])

    assert contract["spec_version"] == CONTRACT_SPEC_VERSION == 2
    assert contract["classifier"] == "descriptors"
    assert contract["aggregation"] == "mean"
    assert contract["classes"] == list(cfg["classes"])
    descriptors = contract["descriptors"]
    assert descriptors["glcm_levels"] == GLCM_LEVELS
    assert descriptors["glcm_offsets"] == [list(offset) for offset in GLCM_OFFSETS]
    assert descriptors["lbp_points"] == LBP_POINTS
    # The ring is the eight adjacent pixels, which is what radius 1 means.
    assert {max(abs(dy), abs(dx)) for dy, dx in LBP_NEIGHBOURS} == {descriptors["lbp_radius"]}
    assert descriptors["lbp_mapping"] == "rotation_invariant_uniform"
    assert descriptors["spectral_bands"] == SPECTRAL_BANDS
    assert descriptors["min_cycles_per_patch"] == MIN_CYCLES_PER_PATCH
    assert descriptors["features"] == list(feature_names())
    geometry = contract["geometry"]
    assert geometry["canonical_mm_per_px"] == cfg["preprocessing"]["canonical_mm_per_px"]
    assert geometry["patch_px"] == cfg["data"]["image_size"]
    assert geometry["patch_stride_fraction"] == cfg["preprocessing"]["patch_stride_fraction"]
    assert geometry["min_patches"] == cfg["preprocessing"]["min_patches"]
    # A contract is JSON: nothing numpy-typed survives into it.
    json.dumps(contract)


def test_the_writer_refuses_a_pipeline_fitted_on_other_classes():
    pipeline, _ = _fitted(classes=3)
    with pytest.raises(ValueError, match="class"):
        _contract(pipeline)


def test_the_committed_golden_is_self_consistent():
    if not GOLDEN_PATH.exists():
        pytest.fail(
            f"{GOLDEN_PATH} is missing; run "
            "`cd ml && python scripts/generate_contract_golden.py`"
        )
    golden = json.loads(GOLDEN_PATH.read_text(encoding="utf-8"))
    assert golden["photographs"], "the golden holds no photograph"
    for photograph in golden["photographs"]:
        np.testing.assert_allclose(
            evaluate(golden["contract"], photograph["patches"]),
            photograph["distribution"],
            rtol=RELATIVE,
            atol=ABSOLUTE,
            err_msg=photograph["name"],
        )
