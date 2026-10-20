"""Phone-camera augmentation of a region at the canonical scale (SPEC 0175).

The archive was photographed in a Petri dish on a fixed rig; the field is
photographed by a phone that exposes, white-balances, sharpens, denoises and
recompresses on its own. A variant draws those changes, seeded, on a region
that is already at the canonical scale, so it never changes how many
millimetres a pixel covers (ADR 0018). The patch grid is cut after it.

A quarter turn and a mirror are drawn too, and move the disc's centre with
them, in pixel-index coordinates: a pixel at (y, x) is the centre (y, x).
"""

from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageFilter

#: Each draw's range. Factors are multiplicative; the noise is a standard
#: deviation in grey levels; the JPEG quality is Pillow's.
RANGES = {
    "brightness": (0.85, 1.15),
    "contrast": (0.85, 1.15),
    "gamma": (0.85, 1.15),
    "white_balance": (0.93, 1.07),
    "noise_sigma": (0.0, 4.0),
    "jpeg_quality": (60, 95),
    "blur_sigma": (0.0, 0.8),
    "sharpen_amount": (0.0, 0.8),
}


@dataclass(frozen=True)
class Draw:
    brightness: float
    contrast: float
    gamma: float
    gains: tuple[float, float, float]
    noise_sigma: float
    jpeg_quality: int
    #: One of the two is zero: a phone sharpens or it does not.
    blur_sigma: float
    sharpen_amount: float
    #: Clockwise quarter turns.
    quarter_turns: int
    mirror: bool


def _generator(seed: int, key: str, k: int) -> np.random.Generator:
    digest = hashlib.blake2b(f"{seed}|{key}|{k}".encode("utf-8"), digest_size=8)
    return np.random.default_rng(int.from_bytes(digest.digest(), "big"))


def draw(seed: int, key: str, k: int) -> Draw:
    """The ``k``-th variant of the region named ``key``, under ``seed``."""
    rng = _generator(seed, key, k)

    def uniform(name: str) -> float:
        low, high = RANGES[name]
        return float(rng.uniform(low, high))

    sharpens = bool(rng.integers(0, 2))
    low_q, high_q = RANGES["jpeg_quality"]
    return Draw(
        brightness=uniform("brightness"),
        contrast=uniform("contrast"),
        gamma=uniform("gamma"),
        gains=tuple(uniform("white_balance") for _ in range(3)),
        noise_sigma=uniform("noise_sigma"),
        jpeg_quality=int(rng.integers(low_q, high_q + 1)),
        blur_sigma=0.0 if sharpens else uniform("blur_sigma"),
        sharpen_amount=uniform("sharpen_amount") if sharpens else 0.0,
        quarter_turns=int(rng.integers(0, 4)),
        mirror=bool(rng.integers(0, 2)),
    )


def turn(
    region: Image.Image, centre: tuple[float, float], quarter_turns: int, mirror: bool
) -> tuple[Image.Image, tuple[float, float]]:
    """``region`` turned clockwise ``quarter_turns`` times, then mirrored left to
    right if ``mirror``, and ``centre`` carried with it."""
    y, x = centre
    for _ in range(quarter_turns % 4):
        height = region.height
        region = region.transpose(Image.Transpose.ROTATE_270)
        y, x = x, height - 1 - y
    if mirror:
        region = region.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        x = region.width - 1 - x
    return region, (y, x)


def apply(
    region: Image.Image, centre: tuple[float, float], drawn: Draw, *, noise_seed: int
) -> tuple[Image.Image, tuple[float, float]]:
    """``drawn`` applied to ``region``: tone, white balance, noise, then a blur
    or a sharpening, then the recompression, then the turn."""
    pixels = np.asarray(region.convert("RGB"), dtype=np.float64) / 255.0
    mean = pixels.mean()
    pixels = (pixels - mean) * drawn.contrast + mean
    pixels = pixels * drawn.brightness
    pixels = np.clip(pixels, 0.0, 1.0) ** drawn.gamma
    pixels = pixels * np.asarray(drawn.gains)
    pixels = pixels * 255.0
    if drawn.noise_sigma > 0.0:
        noise = np.random.default_rng(noise_seed).normal(
            0.0, drawn.noise_sigma, size=pixels.shape
        )
        pixels = pixels + noise
    image = Image.fromarray(np.rint(np.clip(pixels, 0.0, 255.0)).astype(np.uint8))

    if drawn.blur_sigma > 0.0:
        image = image.filter(ImageFilter.GaussianBlur(radius=drawn.blur_sigma))
    elif drawn.sharpen_amount > 0.0:
        image = image.filter(
            ImageFilter.UnsharpMask(
                radius=1, percent=int(round(drawn.sharpen_amount * 100)), threshold=0
            )
        )

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=drawn.jpeg_quality)
    buffer.seek(0)
    with Image.open(buffer) as decoded:
        image = decoded.convert("RGB")

    return turn(image, centre, drawn.quarter_turns, drawn.mirror)


def variant(
    region: Image.Image, centre: tuple[float, float], *, seed: int, key: str, k: int
) -> tuple[Image.Image, tuple[float, float]]:
    """The ``k``-th phone variant of ``region``, with its disc's centre."""
    drawn = draw(seed, key, k)
    noise_seed = int(_generator(seed, key, k).integers(0, 2**31))
    return apply(region, centre, drawn, noise_seed=noise_seed)
