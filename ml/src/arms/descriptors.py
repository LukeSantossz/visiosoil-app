"""The classical-descriptor arm of the E0 gate (SPEC 0054, from SPEC 0044).

The cheapest of the three real arms and the one the gate defaults to shipping:
four groups of texture descriptors over the scale-normalised greyscale patches
of [ADR 0018](../../../docs/adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md),
then a regularised linear classifier over them.

It is a thin binding and nothing more. The descriptors are
:mod:`src.descriptors`, and the selection, the standardisation, the aggregation
back to one prediction per photograph and every fold artifact are
:func:`src.arms.probe.probe_fold`, shared with the frozen-encoder arm. Two arms
that differed in any of those would not be comparable, and comparing them is the
only reason either exists.
"""

from __future__ import annotations

from functools import partial
from typing import Mapping, Sequence

import numpy as np

from ..descriptors import GROUPS, describe_patch
from .probe import probe_fold


def descriptor_features(
    entry: Mapping, cfg: Mapping, groups: Sequence[str] = GROUPS
) -> np.ndarray:
    """Describe every patch of one photograph, one row per patch.

    ``groups`` is what makes the ablation possible: running the arm with one
    group removed is running it with a shorter ``groups``, and nothing else
    about the arm changes. SPEC 0044 asks for that ablation because "what
    carries the signal" is the diagnostic this arm exists to give — an arm that
    wins on ``first_order`` alone learned brightness, not texture.
    """
    # Imported here rather than at module scope: `_photograph_patches` is where
    # the resample, the EXIF transpose and the grid live, and reaching them
    # through `dataset` keeps one implementation of the cut rather than a second
    # that could drift from it.
    from ..dataset import _measurement_of, _photograph_patches, photograph_scale

    # Through `_measurement_of` rather than by indexing the mapping: a path the
    # manifest does not hold is a fold manifest and a dataset version
    # disagreeing about which photographs exist, and that helper says so and
    # names the command that fixes it. Direct indexing raises a bare `KeyError`
    # carrying a path and no explanation.
    measurement = _measurement_of(entry, photograph_scale(cfg))
    patches = _photograph_patches(entry, measurement, cfg)
    return np.stack([describe_patch(patch, groups=groups) for patch in patches])


#: The arm's fold trainer, with `train.train_fold`'s signature.
descriptor_fold = partial(probe_fold, featuriser=descriptor_features)
