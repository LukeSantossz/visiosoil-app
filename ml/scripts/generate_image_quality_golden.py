"""Generate the image quality fixtures and the cross-language golden (SPEC 0030).

Writes PNG fixtures and `golden.json` into `test/fixtures/image_quality/`. The
Dart suite and the Python suite each assert their implementation reproduces the
golden, so a silent drift on either side fails the other side's tests.

Fixtures are synthesized from fixed formulas with no randomness, so a run with
no source change must produce a byte-identical `golden.json`. A non-empty diff
means an implementation changed, and the diff is the evidence.

Run from the `ml/` directory:

    python scripts/generate_image_quality_golden.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Callable, Dict, List

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.image_quality import (  # noqa: E402
    DEFAULT_CRITERIA,
    Criterion,
    ImageQualityCriteria,
    ImageQualityMetrics,
    analyze,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = REPO_ROOT / "test" / "fixtures" / "image_quality"

SIDE = 640


# --- fixture formulas ------------------------------------------------------


def _rgb(plane: np.ndarray) -> np.ndarray:
    return np.dstack([plane, plane, plane]).astype(np.uint8)


def _checkerboard(side: int, low: int, high: int, cell: int) -> np.ndarray:
    ys, xs = np.mgrid[0:side, 0:side]
    mask = ((xs // cell) + (ys // cell)) % 2 == 0
    return _rgb(np.where(mask, high, low))


def _ok_checkerboard() -> np.ndarray:
    return _checkerboard(SIDE, 60, 200, 4)


def _blur_only() -> np.ndarray:
    """An integer ramp: high contrast, but a linear signal has no Laplacian."""
    xs = np.arange(SIDE)
    row = 40 + (xs * 180) // SIDE
    return _rgb(np.tile(row, (SIDE, 1)))


def _exposure_dark_only() -> np.ndarray:
    return _checkerboard(SIDE, 5, 65, 4)


def _exposure_bright_only() -> np.ndarray:
    return _checkerboard(SIDE, 190, 248, 4)


def _clipping_only() -> np.ndarray:
    """Clips at the dark bound: a bright-clipped pixel is always also specular."""
    pixels = _checkerboard(SIDE, 150, 190, 4)
    pixels[:, ::5] = 0
    return pixels


def _contrast_only() -> np.ndarray:
    return _checkerboard(SIDE, 113, 143, 4)


def _color_cast_only() -> np.ndarray:
    pixels = _checkerboard(SIDE, 60, 180, 4)
    pixels[:, :, 0] = np.clip(pixels[:, :, 0].astype(np.int32) + 60, 0, 255)
    return pixels


def _specular_only() -> np.ndarray:
    pixels = _checkerboard(SIDE, 100, 160, 4)
    pixels[: int(SIDE * 0.15), :, :] = 251
    return pixels


def _resolution_only() -> np.ndarray:
    """Below the ROI minimum, so no downscale runs before the Laplacian."""
    return _checkerboard(256, 60, 200, 4)


def _flat_fill() -> np.ndarray:
    """A known exact mean of 128.0: a mismatch here is a decoder difference."""
    return _rgb(np.full((SIDE, SIDE), 128))


def _multi_failure() -> np.ndarray:
    return _rgb(np.full((SIDE, SIDE), 12))


FIXTURES: Dict[str, Callable[[], np.ndarray]] = {
    "ok_checkerboard": _ok_checkerboard,
    "blur_only": _blur_only,
    "exposure_dark_only": _exposure_dark_only,
    "exposure_bright_only": _exposure_bright_only,
    "clipping_only": _clipping_only,
    "contrast_only": _contrast_only,
    "color_cast_only": _color_cast_only,
    "specular_only": _specular_only,
    "resolution_only": _resolution_only,
    "flat_fill": _flat_fill,
    "multi_failure": _multi_failure,
}


# --- golden ----------------------------------------------------------------


def _threshold_distance(
    metrics: ImageQualityMetrics, criteria: ImageQualityCriteria
) -> Dict[str, float]:
    """Absolute distance from each metric to the nearest bound governing it.

    A fixture sitting on a bound would make its verdict depend on floating-point
    noise, which is exactly what the conformance golden must not tolerate.
    """
    return {
        "blur_score": abs(metrics.blur_score - criteria.min_blur_score),
        "mean_luminance": min(
            abs(metrics.mean_luminance - criteria.min_mean_luminance),
            abs(metrics.mean_luminance - criteria.max_mean_luminance),
        ),
        "clipped_fraction": abs(
            metrics.clipped_fraction - criteria.max_clipped_fraction
        ),
        "contrast_score": abs(metrics.contrast_score - criteria.min_contrast_score),
        "color_cast_score": abs(
            metrics.color_cast_score - criteria.max_color_cast_score
        ),
        "specular_fraction": abs(
            metrics.specular_fraction - criteria.max_specular_fraction
        ),
        "roi_side_px": float(abs(metrics.roi_side_px - criteria.min_roi_side_px)),
    }


def main() -> int:
    FIXTURE_DIR.mkdir(parents=True, exist_ok=True)
    entries: List[dict] = []

    for name, build in FIXTURES.items():
        path = FIXTURE_DIR / f"{name}.png"
        Image.fromarray(build(), mode="RGB").save(path, format="PNG", optimize=True)

        report = analyze(Image.open(path))
        if report.metrics is None:
            raise SystemExit(f"fixture {name} did not analyse: {report.unvalidated_reason}")

        entries.append(
            {
                "file": path.name,
                "verdict": report.verdict.value,
                "metrics": {
                    "blur_score": report.metrics.blur_score,
                    "mean_luminance": report.metrics.mean_luminance,
                    "clipped_fraction": report.metrics.clipped_fraction,
                    "contrast_score": report.metrics.contrast_score,
                    "color_cast_score": report.metrics.color_cast_score,
                    "specular_fraction": report.metrics.specular_fraction,
                    "roi_side_px": report.metrics.roi_side_px,
                    "downscale_applied": report.metrics.downscale_applied,
                },
                "failures": [
                    {
                        "criterion": failure.criterion.value,
                        "severity": failure.severity.value,
                        "measured": failure.measured,
                        "threshold": failure.threshold,
                        "margin": failure.margin,
                    }
                    for failure in report.failures
                ],
                "threshold_distance": _threshold_distance(
                    report.metrics, DEFAULT_CRITERIA
                ),
            }
        )

    golden = {
        "spec": "0030",
        "criteria": {
            "min_blur_score": DEFAULT_CRITERIA.min_blur_score,
            "min_mean_luminance": DEFAULT_CRITERIA.min_mean_luminance,
            "max_mean_luminance": DEFAULT_CRITERIA.max_mean_luminance,
            "max_clipped_fraction": DEFAULT_CRITERIA.max_clipped_fraction,
            "min_contrast_score": DEFAULT_CRITERIA.min_contrast_score,
            "max_color_cast_score": DEFAULT_CRITERIA.max_color_cast_score,
            "max_specular_fraction": DEFAULT_CRITERIA.max_specular_fraction,
            "min_roi_side_px": DEFAULT_CRITERIA.min_roi_side_px,
        },
        "fixtures": entries,
    }
    (FIXTURE_DIR / "golden.json").write_text(
        json.dumps(golden, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    _report(entries)
    return 0


def _report(entries: List[dict]) -> None:
    sole = {
        entry["failures"][0]["criterion"]
        for entry in entries
        if len(entry["failures"]) == 1
    }
    for entry in entries:
        names = ", ".join(f["criterion"] for f in entry["failures"]) or "-"
        print(f"{entry['file']:<28} {entry['verdict']:<11} {names}")

    missing = {c.value for c in Criterion} - sole
    print()
    if missing:
        print(f"NOT ISOLATED BY ANY FIXTURE: {sorted(missing)}")
    else:
        print("every criterion is isolated by at least one fixture")


if __name__ == "__main__":
    raise SystemExit(main())
