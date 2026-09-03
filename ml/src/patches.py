"""The scale-normalised greyscale patch grid (SPEC 0053, from SPEC 0037).

The model does not see a photograph. It sees a grid of square patches, each
covering the same **physical area of soil** — about 21 mm across — cut from
inside the dish, converted to greyscale, and scored independently
([ADR 0018](../../docs/adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)).

Two properties make that mean anything, and both are arithmetic:

**Every photograph is first resampled to one canonical millimetres per pixel**,
the value `ml/measurements/dish-scale-v1.json` records. Resampling is
one-directional: toward a coarser scale it discards detail a more distant camera
would also not have resolved, while toward a finer one it invents grain that was
never photographed, and a model trained on interpolated grain learns the
interpolator. So a photograph coarser than the canonical is **refused by name**.

**The grid is inset from the region boundary by a patch half-diagonal**, so no
patch can contain a pixel of glass, bench or paper. SPEC 0037's prose said
half-width; that is not enough, because a square inset by half its width still
puts its corners outside a circle, and it yields 37 patches on a 90 mm dish
against the 25 ADR 0018 tabulates. The half-diagonal satisfies both, and
SPEC 0053 carries the correction.

Everything here is pure arithmetic over pixels: no model, no TensorFlow, no
randomness and no seed.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Tuple

import numpy as np
from PIL import Image

from src.image_quality import LUMA_B, LUMA_G, LUMA_R

#: Below this many patches the region is refused rather than padded with
#: background. The floor is on the dispersion measure the application computes
#: over patches, not on the classification: a mean over four patches is usable,
#: an entropy over four is too coarse to raise a warning with (ADR 0018).
DEFAULT_MIN_PATCHES = 9

#: The grid strides by half a patch, so patches overlap by 50 %. Squares do not
#: tile a circle to its boundary, so a non-overlapping grid steps between 1, 4
#: and 9 as the disc grows; half-patch stride gives a count that varies smoothly
#: and enough points for the dispersion measure at the small end.
DEFAULT_STRIDE_FRACTION = 0.5


class PatchRefusal(str, Enum):
    """Why a photograph produced no patches. Never a fallback, always a name."""

    TOO_COARSE = "too_coarse_to_normalise"
    REGION_TOO_SMALL = "region_too_small_for_the_patch_floor"


@dataclass(frozen=True)
class PatchGeometry:
    """Where the patches of one region sit, and how big they are."""

    patch_px: int
    patch_mm: float
    stride_px: float
    inset_px: float
    region_radius_px: float
    #: Patch centres as ``(dy, dx)`` from the region centre, sorted so the grid
    #: is a deterministic sequence rather than whatever order it was built in.
    offsets: Tuple[Tuple[float, float], ...]

    @property
    def count(self) -> int:
        return len(self.offsets)


def resample_to_canonical(
    image: Image.Image, measured_mm_per_px: float, canonical_mm_per_px: float
) -> tuple[Image.Image, float]:
    """Return the image at the canonical scale, or refuse to upsample it.

    Raises:
        ValueError: If the photograph is coarser than the canonical, naming
            `PatchRefusal.TOO_COARSE`. Reaching the canonical would mean
            inventing detail, and a model trained on it learns the interpolator.
    """
    if measured_mm_per_px <= 0.0 or canonical_mm_per_px <= 0.0:
        raise ValueError(
            f"a scale must be positive; got measured {measured_mm_per_px} and "
            f"canonical {canonical_mm_per_px}"
        )
    if measured_mm_per_px > canonical_mm_per_px:
        raise ValueError(
            f"{PatchRefusal.TOO_COARSE.value}: the photograph measures "
            f"{measured_mm_per_px:.4f} mm/px and the canonical is "
            f"{canonical_mm_per_px:.4f}, so reaching it would upsample by "
            f"{measured_mm_per_px / canonical_mm_per_px:.2f}x"
        )
    if measured_mm_per_px == canonical_mm_per_px:
        return image, canonical_mm_per_px

    ratio = measured_mm_per_px / canonical_mm_per_px
    width, height = image.size
    resized = image.resize(
        (max(1, round(width * ratio)), max(1, round(height * ratio))),
        # Pillow scales a resampling filter's support by the reduction factor,
        # so this downsample is low-passed rather than point-sampled. That is
        # the anti-aliasing #180 is about, on the path that matters.
        Image.BILINEAR,
    )
    return resized, canonical_mm_per_px


def patch_geometry(
    region_diameter_px: float,
    input_size: int,
    canonical_mm_per_px: float,
    min_patches: int = DEFAULT_MIN_PATCHES,
    stride_fraction: float = DEFAULT_STRIDE_FRACTION,
) -> PatchGeometry:
    """Return the grid a region of this size carries, or refuse it.

    Raises:
        ValueError: If the region holds fewer than `min_patches`, naming
            `PatchRefusal.REGION_TOO_SMALL` and the count it could produce.
    """
    if region_diameter_px <= 0.0:
        raise ValueError(f"region diameter must be positive; got {region_diameter_px}")
    if input_size <= 0:
        raise ValueError(f"input size must be positive; got {input_size}")

    radius = region_diameter_px / 2.0
    stride = input_size * stride_fraction
    # A patch is inside the circle when its farthest corner is, which is its
    # half-diagonal from the centre — not its half-width.
    inset = input_size * math.sqrt(2.0) / 2.0
    limit = radius - inset

    offsets: list[tuple[float, float]] = []
    if limit >= 0.0:
        steps = int(limit // stride)
        for row in range(-steps, steps + 1):
            for column in range(-steps, steps + 1):
                dy, dx = row * stride, column * stride
                if math.hypot(dy, dx) <= limit + 1e-9:
                    offsets.append((dy, dx))

    if len(offsets) < min_patches:
        raise ValueError(
            f"{PatchRefusal.REGION_TOO_SMALL.value}: a region of "
            f"{region_diameter_px:.1f} px carries {len(offsets)} patch(es) of "
            f"{input_size} px at half-patch stride, and the floor is "
            f"{min_patches}"
        )

    return PatchGeometry(
        patch_px=input_size,
        patch_mm=input_size * canonical_mm_per_px,
        stride_px=stride,
        inset_px=inset,
        region_radius_px=radius,
        offsets=tuple(sorted(offsets)),
    )


def cut_patches(
    image: Image.Image,
    centre_y: float,
    centre_x: float,
    region_diameter_px: float,
    input_size: int,
    canonical_mm_per_px: float,
    min_patches: int = DEFAULT_MIN_PATCHES,
    stride_fraction: float = DEFAULT_STRIDE_FRACTION,
) -> list[np.ndarray]:
    """Cut the grid out of `image`, greyscale, three identical channels.

    The image is expected to be **already at the canonical scale**; this
    function does no resampling, so the geometry it cuts is the geometry
    `patch_geometry` reports for the same arguments.
    """
    geometry = patch_geometry(
        region_diameter_px=region_diameter_px,
        input_size=input_size,
        canonical_mm_per_px=canonical_mm_per_px,
        min_patches=min_patches,
        stride_fraction=stride_fraction,
    )

    rgb = np.asarray(image.convert("RGB"), dtype=np.float64)
    luma = LUMA_R * rgb[..., 0] + LUMA_G * rgb[..., 1] + LUMA_B * rgb[..., 2]
    grey = np.rint(luma).clip(0.0, 255.0).astype(np.uint8)

    height, width = grey.shape
    half = input_size / 2.0
    patches: list[np.ndarray] = []
    for dy, dx in geometry.offsets:
        top = int(round(centre_y + dy - half))
        left = int(round(centre_x + dx - half))
        if top < 0 or left < 0 or top + input_size > height or left + input_size > width:
            raise ValueError(
                f"a patch at offset ({dy:.1f}, {dx:.1f}) falls outside the "
                f"{width}x{height} frame; the region is not wholly photographed"
            )
        window = grey[top : top + input_size, left : left + input_size]
        patches.append(np.repeat(window[:, :, None], 3, axis=2))

    return patches
