"""Phone-camera augmentation of a canonical region (SPEC 0175).

A variant is a seeded draw of photometric changes, a recompression, a blur or a
sharpening, and a quarter turn and mirror that carry the disc's centre with
them. It never changes the scale: the region keeps its size, turned.
"""

from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from src import phone_augment
from src.phone_augment import RANGES, draw, variant


def _region(height=60, width=80, seed=3):
    generator = np.random.default_rng(seed)
    pixels = generator.integers(40, 200, size=(height, width, 3), dtype=np.uint8)
    return Image.fromarray(pixels, mode="RGB")


def test_a_variant_is_deterministic():
    region = _region()
    first, first_centre = variant(region, (20.0, 30.0), seed=7, key="a.png", k=1)
    again, again_centre = variant(region, (20.0, 30.0), seed=7, key="a.png", k=1)
    other, _ = variant(region, (20.0, 30.0), seed=7, key="a.png", k=2)

    assert np.array_equal(np.asarray(first), np.asarray(again))
    assert first_centre == again_centre
    assert not np.array_equal(np.asarray(first), np.asarray(other))


def test_a_variant_keeps_the_scale():
    region = _region(60, 80)
    for k in range(40):
        drawn = draw(seed=11, key="b.png", k=k)
        image, _ = variant(region, (30.0, 40.0), seed=11, key="b.png", k=k)
        expected = (80, 60) if drawn.quarter_turns % 2 == 0 else (60, 80)
        assert image.size == expected, k
        assert image.mode == "RGB"

        for name in ("brightness", "contrast", "gamma"):
            low, high = RANGES[name]
            assert low <= getattr(drawn, name) <= high, (k, name)
        low, high = RANGES["white_balance"]
        assert all(low <= gain <= high for gain in drawn.gains), k
        low, high = RANGES["noise_sigma"]
        assert low <= drawn.noise_sigma <= high, k
        low, high = RANGES["jpeg_quality"]
        assert low <= drawn.jpeg_quality <= high, k
        assert drawn.blur_sigma == 0.0 or drawn.sharpen_amount == 0.0, k
        assert 0.0 <= drawn.blur_sigma <= RANGES["blur_sigma"][1], k
        assert 0.0 <= drawn.sharpen_amount <= RANGES["sharpen_amount"][1], k
        assert drawn.quarter_turns in (0, 1, 2, 3), k


@pytest.mark.parametrize(
    ("turns", "mirror", "expected"),
    [
        (0, False, (10.0, 25.0)),
        # Clockwise quarter turn of an H x W region: (y, x) -> (x, H - 1 - y).
        (1, False, (25.0, 60 - 1 - 10.0)),
        # Mirror: (y, x) -> (y, W - 1 - x).
        (0, True, (10.0, 80 - 1 - 25.0)),
        # A turn, then a mirror of the turned region (its width is H).
        (1, True, (25.0, 60 - 1 - (60 - 1 - 10.0))),
    ],
)
def test_the_centre_turns_with_the_region(turns, mirror, expected):
    height, width = 60, 80
    pixels = np.zeros((height, width, 3), dtype=np.uint8)
    y, x = 10, 25
    pixels[y, x] = 255
    region = Image.fromarray(pixels, mode="RGB")

    turned, centre = phone_augment.turn(region, (float(y), float(x)), turns, mirror)

    assert centre == pytest.approx(expected)
    lit = np.argwhere(np.asarray(turned)[..., 0] == 255)
    assert lit.tolist() == [[int(round(centre[0])), int(round(centre[1]))]]
