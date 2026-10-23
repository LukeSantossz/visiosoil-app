"""Generate the real-photograph descriptor-pipeline golden (SPEC 0177).

The fixture records Python's result for one committed, location-free JPEG from
the decode and EXIF-orientation boundary through canonical resampling, patch
cutting, 26 descriptors per patch, and their feature-wise mean. It also emits
the Pillow-decoded, EXIF-oriented RGB frame itself — before any resample — as
a lossless PNG, so Dart can start its own comparison from that stage instead
of decoding the JPEG a second time, where a JPEG decoder difference between
Pillow and `package:image` would contaminate the comparison (SPEC 0177 Risks).
Dart reads that PNG and the same measurement in
`descriptor_pipeline_golden_test.dart`.

Run from `ml/`:

    python scripts/generate_descriptor_pipeline_golden.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.descriptors import describe_patch  # noqa: E402
from src.patches import cut_patches, resample_to_canonical  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "descriptors" / "pipeline_golden.json"
#: The decoded-frame stage emitted below. Named so the golden JSON documents
#: which stage the PNG freezes, in case a future photograph's decoded frame
#: no longer fits under `_MAX_DECODED_FRAME_BYTES` and a later, smaller stage
#: (e.g. the canonical-size frame) has to be emitted instead.
_DECODED_FRAME_STAGE = "decoded_rgb_pre_resample"
DECODED_FRAME_PATH = (
    REPO_ROOT / "test" / "fixtures" / "descriptors" / "pipeline_golden_decoded_frame.png"
)
#: Keeps the committed fixture small. If the decoded frame ever exceeds this,
#: `main` raises rather than silently committing a multi-megabyte PNG; the fix
#: is to freeze a later, smaller lossless stage instead (see `_DECODED_FRAME_STAGE`).
_MAX_DECODED_FRAME_BYTES = 2 * 1024 * 1024
PHOTOGRAPH = "test/fixtures/sheet_photos/photo_160609.jpg"

# This is an explicit test measurement in the decoded photograph's displayed
# frame, not a duplicate Python A4-sheet reader. The reduction exercises the
# canonical resample and the 680 px diameter carries the contract's nine-patch
# floor after that reduction.
MEASUREMENT = {
    "mm_per_px": 0.09,
    "centre_y_px": 230.5,
    "centre_x_px": 512.0,
    "diameter_px": 680.0,
}
GEOMETRY = {
    "canonical_mm_per_px": 0.12920342774728033,
    "patch_px": 160,
    "patch_stride_fraction": 0.5,
    "min_patches": 9,
}


def decoded_frame() -> Image.Image:
    """Return the Pillow-decoded, EXIF-oriented RGB frame, before any resample.

    This is the stage named by `_DECODED_FRAME_STAGE` and written to
    `DECODED_FRAME_PATH` by `main`, so Dart can start its comparison here
    instead of decoding the JPEG itself.
    """
    path = REPO_ROOT / PHOTOGRAPH
    with Image.open(path) as handle:
        return ImageOps.exif_transpose(handle).convert("RGB")


def describe_pipeline() -> dict:
    """Describe the fixture photograph through the shared Python path."""
    photograph = decoded_frame()
    decoded_rgb = np.asarray(photograph, dtype=np.float64)
    canonical, _ = resample_to_canonical(
        photograph,
        MEASUREMENT["mm_per_px"],
        GEOMETRY["canonical_mm_per_px"],
    )
    ratio = MEASUREMENT["mm_per_px"] / GEOMETRY["canonical_mm_per_px"]
    patches = cut_patches(
        canonical,
        centre_y=MEASUREMENT["centre_y_px"] * ratio,
        centre_x=MEASUREMENT["centre_x_px"] * ratio,
        region_diameter_px=MEASUREMENT["diameter_px"] * ratio,
        input_size=GEOMETRY["patch_px"],
        canonical_mm_per_px=GEOMETRY["canonical_mm_per_px"],
        min_patches=GEOMETRY["min_patches"],
        stride_fraction=GEOMETRY["patch_stride_fraction"],
    )
    features = np.stack([describe_patch(patch) for patch in patches])
    return {
        "photograph": PHOTOGRAPH,
        "measurement": MEASUREMENT,
        "geometry": GEOMETRY,
        "decoded_size": list(photograph.size),
        "decoded_rgb_statistics": {
            "pixel_count": int(decoded_rgb.shape[0] * decoded_rgb.shape[1]),
            "mean": [float(value) for value in decoded_rgb.mean(axis=(0, 1))],
            "std": [float(value) for value in decoded_rgb.std(axis=(0, 1))],
        },
        "decoded_frame_fixture": {
            "path": str(DECODED_FRAME_PATH.relative_to(REPO_ROOT)),
            "stage": _DECODED_FRAME_STAGE,
        },
        "canonical_size": list(canonical.size),
        "patches": [[float(value) for value in row] for row in features],
        "mean_features": [float(value) for value in features.mean(axis=0)],
    }


def render(golden: dict) -> str:
    return json.dumps(golden, indent=2) + "\n"


def main() -> None:
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    GOLDEN_PATH.write_text(render(describe_pipeline()), encoding="utf-8")
    print(f"wrote {GOLDEN_PATH}")

    frame = decoded_frame()
    frame.save(DECODED_FRAME_PATH, format="PNG")
    written_bytes = DECODED_FRAME_PATH.stat().st_size
    if written_bytes > _MAX_DECODED_FRAME_BYTES:
        raise RuntimeError(
            f"{DECODED_FRAME_PATH} is {written_bytes} bytes, over the "
            f"{_MAX_DECODED_FRAME_BYTES}-byte budget for a committed fixture; "
            "freeze a later, smaller lossless stage (e.g. the canonical-size "
            "frame) instead of the decoded frame, and update "
            "_DECODED_FRAME_STAGE to document which stage was committed"
        )
    print(f"wrote {DECODED_FRAME_PATH} ({written_bytes} bytes)")


if __name__ == "__main__":
    main()
