"""Research-only 128 px descriptor candidate for small soil discs (SPEC 0143)."""

from __future__ import annotations

import copy
from typing import Mapping

import numpy as np

from .descriptors import GROUPS, describe_patch
from .small_disc import simulated_measurement


PATCH_PX = 128
DISC_MM = 47.2


def study_config(cfg: Mapping) -> dict:
    """Copy the released configuration with only the candidate patch size changed."""
    study = copy.deepcopy(dict(cfg))
    study["data"]["image_size"] = PATCH_PX
    return study


def candidate_features(entry: Mapping, cfg: Mapping) -> np.ndarray:
    """Describe the central nine patches of an entry's measured photograph."""
    from .dataset import _measurement_of, _photograph_patches, photograph_scale

    measurement = _measurement_of(entry, photograph_scale(cfg))
    simulated = simulated_measurement(measurement, DISC_MM)
    patches = _photograph_patches(entry, simulated, cfg)
    return np.stack([describe_patch(patch, groups=GROUPS) for patch in patches])
