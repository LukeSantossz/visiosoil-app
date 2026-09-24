"""Generate the cross-language descriptor golden (SPEC 0077).

Writes `test/fixtures/descriptors/golden.json`: the feature names, the band
edges of every fixture shape, and for each fixture its pixels and the features
`src.descriptors.describe_patch` returns for it. The Dart port in
`lib/core/services/descriptors/` must reproduce them, and
`tests/test_descriptor_golden.py` asserts that Python still does, so a silent
drift on either side fails the other side's suite.

The pixels are stored as base64 of the raw ``uint8`` plane. No image codec
stands between the two languages.

Fixtures come from fixed seeds and integer arithmetic only, so a run with no
source change writes a byte-identical file. A non-empty diff means an
implementation changed, and the diff is the evidence.

Run from the `ml/` directory:

    python scripts/generate_descriptor_golden.py
"""

from __future__ import annotations

import base64
import json
import sys
from pathlib import Path
from typing import Callable, Dict, List

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.descriptors import (  # noqa: E402
    MIN_CYCLES_PER_PATCH,
    SPECTRAL_BANDS,
    _band_map,
    describe_patch,
    feature_names,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "descriptors" / "golden.json"

SIDE = 160

#: A radius this close to an edge is on it, and goes to the upper band. Exact
#: ties are structural: a square patch's middle edge is the square root of its
#: side, which is a grid radius whenever the side is a sum of two squares (160
#: is), and numpy computes that edge a few units in the last place off.
TIE = 1e-9
#: Between `TIE` and this, a radius is neither clearly on an edge nor clearly
#: off it, and the two languages could disagree for no reason worth testing.
#: The generator refuses a shape with a radius there.
AMBIGUOUS = 1e-6


# --- fixture formulas ---------------------------------------------------------


def _pink_noise() -> np.ndarray:
    """Octaves of blocky noise, each half the amplitude of the one above.

    Power falls with frequency as a natural image's does, so every band carries
    energy. Built from integers and block repeats rather than an inverse FFT,
    so no transform's last bit reaches the pixels.
    """
    rng = np.random.default_rng(77)
    total = np.zeros((SIDE, SIDE), dtype=np.int64)
    for octave in range(6):
        block = 1 << octave
        cells = rng.integers(-32, 33, size=(SIDE // block, SIDE // block))
        total += np.kron(cells, np.ones((block, block), dtype=np.int64)) * (octave + 1)
    return np.clip(128 + total // 4, 0, 255).astype(np.uint8)


def _white_noise() -> np.ndarray:
    return np.random.default_rng(78).integers(0, 256, size=(SIDE, SIDE)).astype(np.uint8)


def _coarse_grains() -> np.ndarray:
    rng = np.random.default_rng(79)
    grains = np.kron(rng.integers(40, 221, size=(SIDE // 8, SIDE // 8)), np.ones((8, 8), dtype=np.int64))
    jitter = rng.integers(-6, 7, size=(SIDE, SIDE))
    return np.clip(grains + jitter, 0, 255).astype(np.uint8)


def _ramp() -> np.ndarray:
    ys, xs = np.mgrid[0:SIDE, 0:SIDE]
    return (40 + ((xs + ys) * 180) // (2 * SIDE - 2)).astype(np.uint8)


def _checkerboard() -> np.ndarray:
    ys, xs = np.mgrid[0:SIDE, 0:SIDE]
    return np.where(((xs // 4) + (ys // 4)) % 2 == 0, 200, 60).astype(np.uint8)


def _flat() -> np.ndarray:
    return np.full((SIDE, SIDE), 128, dtype=np.uint8)


def _ties() -> np.ndarray:
    """Two grey levels in large runs, so `>=` decides most LBP codes."""
    rng = np.random.default_rng(80)
    return np.kron(
        rng.choice(np.array([90, 150]), size=(SIDE // 16, SIDE // 16)),
        np.ones((16, 16), dtype=np.int64),
    ).astype(np.uint8)


def _rectangle() -> np.ndarray:
    return np.random.default_rng(81).integers(0, 256, size=(37, 53)).astype(np.uint8)


def _smallest_banded() -> np.ndarray:
    return np.random.default_rng(82).integers(0, 256, size=(5, 5)).astype(np.uint8)


FIXTURES: Dict[str, Callable[[], np.ndarray]] = {
    "pink_noise_160": _pink_noise,
    "white_noise_160": _white_noise,
    "coarse_grains_160": _coarse_grains,
    "ramp_160": _ramp,
    "checkerboard_160": _checkerboard,
    "flat_160": _flat,
    "ties_160": _ties,
    "rectangle_37x53": _rectangle,
    "smallest_banded_5x5": _smallest_banded,
}


# --- the spectral geometry ----------------------------------------------------


def band_edges(height: int, width: int) -> np.ndarray:
    """The band edges `src.descriptors._band_map` uses for one shape."""
    return np.geomspace(MIN_CYCLES_PER_PATCH, min(height, width) / 2.0, SPECTRAL_BANDS + 1)


def _radius(height: int, width: int) -> np.ndarray:
    """Every frequency bin's radius in cycles per patch, in `fftfreq` order."""
    frequency_y = np.fft.fftfreq(height) * height
    frequency_x = np.fft.fftfreq(width) * width
    return np.hypot(frequency_y[:, None], frequency_x[None, :]).ravel()


def _edge_distance(height: int, width: int) -> np.ndarray:
    """Each bin's distance to its nearest band edge, first and last included."""
    edges = band_edges(height, width)
    return np.abs(_radius(height, width)[:, None] - edges[None, :]).min(axis=1)


def python_band_map(height: int, width: int) -> np.ndarray:
    """The band of every bin as `src.descriptors` assigns it, -1 for none."""
    positions, bands = _band_map(height, width)
    result = np.full(height * width, -1, dtype=np.int8)
    result[positions] = bands
    return result


def tie_rule_band_map(height: int, width: int) -> np.ndarray:
    """The band of every bin under SPEC 0077's rule, -1 for none.

    A radius in ``[edge_i, edge_{i+1})`` is in band ``i``, one within `TIE` of
    an edge is on it, and the Nyquist radius closes the top band.
    """
    radius = _radius(height, width)
    edges = band_edges(height, width)
    result = np.full(radius.shape, -1, dtype=np.int8)
    for band in range(SPECTRAL_BANDS):
        result[radius >= edges[band] - TIE] = band
    result[radius > edges[-1] + TIE] = -1
    return result


def bins_on_an_interior_edge(height: int, width: int) -> int:
    """How many bins sit within `TIE` of an interior edge."""
    interior = band_edges(height, width)[1:-1]
    radius = _radius(height, width)
    return int((np.abs(radius[:, None] - interior[None, :]) <= TIE).any(axis=1).sum())


def ambiguous_radii(height: int, width: int) -> int:
    """How many bins sit between `TIE` and `AMBIGUOUS` of an edge."""
    distance = _edge_distance(height, width)
    return int(((distance > TIE) & (distance < AMBIGUOUS)).sum())


# --- the golden -----------------------------------------------------------------


def build_golden() -> dict:
    """The golden as a JSON-ready mapping.

    Raises:
        ValueError: If a fixture shape puts a radius on an interior band edge.
    """
    fixtures: List[dict] = []
    shapes = []
    for name, make in FIXTURES.items():
        plane = make()
        height, width = plane.shape
        if ambiguous_radii(height, width):
            raise ValueError(
                f"{name}: a {height}x{width} radius sits between {TIE:g} and "
                f"{AMBIGUOUS:g} of a band edge"
            )
        if not np.array_equal(
            python_band_map(height, width), tie_rule_band_map(height, width)
        ):
            raise ValueError(
                f"{name}: the reference's {height}x{width} band map is not the "
                "tie rule's, so the Dart port has no rule to reproduce"
            )
        if (height, width) not in shapes:
            shapes.append((height, width))
        fixtures.append(
            {
                "name": name,
                "height": height,
                "width": width,
                "pixels": base64.b64encode(plane.tobytes()).decode("ascii"),
                "features": [float(value) for value in describe_patch(plane)],
            }
        )
    return {
        "spec": "0077",
        "generator": "ml/scripts/generate_descriptor_golden.py",
        "tolerance": {"relative": 1e-9, "absolute": 1e-12},
        "feature_names": list(feature_names()),
        "band_edges": [
            {
                "height": height,
                "width": width,
                "edges": [float(edge) for edge in band_edges(height, width)],
                "bands": base64.b64encode(
                    python_band_map(height, width).tobytes()
                ).decode("ascii"),
            }
            for height, width in shapes
        ],
        "fixtures": fixtures,
    }


def render(golden: dict) -> str:
    """The golden as the text written to disk."""
    return json.dumps(golden, indent=2) + "\n"


def main() -> None:
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(GOLDEN_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(render(build_golden()))
    print(f"wrote {GOLDEN_PATH}")


if __name__ == "__main__":
    main()
