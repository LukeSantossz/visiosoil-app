"""The descriptor contract: a fitted descriptor pipeline, written as numbers
(SPEC 0079, ADR 0024).

The application does not run this pipeline. It runs Dart arithmetic over the
numbers written here — `lib/core/services/descriptors/descriptor_contract.dart`
reads them — so this function is the one place the schema is defined, and B3's
release export calls it rather than writing its own.

A contract that describes the descriptors differently from how the app computes
them still produces plausible numbers, so the fixed points and the feature order
are written from `src.descriptors` itself and never retyped.
"""

from __future__ import annotations

from typing import Mapping

import numpy as np

from .arms.probe import PROBE_STEP, STANDARDISE_STEP
from .descriptors import (
    GLCM_LEVELS,
    GLCM_OFFSETS,
    LBP_POINTS,
    MIN_CYCLES_PER_PATCH,
    SPECTRAL_BANDS,
    feature_names,
)

#: Version 1 was SPEC 0035's network contract, which never shipped.
CONTRACT_SPEC_VERSION = 2

#: `src.descriptors.LBP_NEIGHBOURS` is the ring of the eight adjacent pixels.
LBP_RADIUS = 1
LBP_MAPPING = "rotation_invariant_uniform"

#: `arms.probe._predict`'s rule: the mean of a photograph's patch distributions.
AGGREGATION = "mean"


def descriptor_contract(
    pipeline, cfg: Mapping, *, model_version: str, dataset_version: str
) -> dict:
    """The JSON-ready contract of one fitted `arms.probe.fit_probe` pipeline.

    Raises:
        ValueError: If the pipeline was fitted on a class set other than
            ``cfg["classes"]``, as indices ``0..n-1``. Its rows would then name
            the wrong class, and the file would still look right.
    """
    scaler = pipeline.named_steps[STANDARDISE_STEP]
    regression = pipeline.named_steps[PROBE_STEP]
    classes = list(cfg["classes"])
    fitted = np.asarray(regression.classes_)
    if fitted.tolist() != list(range(len(classes))):
        raise ValueError(
            f"the pipeline was fitted on class labels {fitted.tolist()}, and the "
            f"contract names {len(classes)} class(es) {classes}; every class "
            "index has to be fitted for a row to mean its class"
        )

    names = list(feature_names())
    coefficients = np.asarray(regression.coef_, dtype=np.float64)
    if coefficients.shape != (len(classes), len(names)):
        raise ValueError(
            f"the regression has shape {coefficients.shape}, and the contract "
            f"needs one row per class over {len(names)} features"
        )

    preprocessing = cfg["preprocessing"]
    return {
        "spec_version": CONTRACT_SPEC_VERSION,
        "classifier": "descriptors",
        "model_version": str(model_version),
        "dataset_version": str(dataset_version),
        "classes": classes,
        "geometry": {
            "canonical_mm_per_px": float(preprocessing["canonical_mm_per_px"]),
            "patch_px": int(cfg["data"]["image_size"]),
            "patch_stride_fraction": float(preprocessing["patch_stride_fraction"]),
            "min_patches": int(preprocessing["min_patches"]),
        },
        "descriptors": {
            "glcm_levels": GLCM_LEVELS,
            "glcm_offsets": [list(offset) for offset in GLCM_OFFSETS],
            "lbp_points": LBP_POINTS,
            "lbp_radius": LBP_RADIUS,
            "lbp_mapping": LBP_MAPPING,
            "spectral_bands": SPECTRAL_BANDS,
            "min_cycles_per_patch": float(MIN_CYCLES_PER_PATCH),
            "features": names,
        },
        "standardiser": {
            "mean": [float(value) for value in scaler.mean_],
            "scale": [float(value) for value in scaler.scale_],
        },
        "regression": {
            "coefficients": [[float(value) for value in row] for row in coefficients],
            "intercepts": [float(value) for value in regression.intercept_],
        },
        "aggregation": AGGREGATION,
    }
