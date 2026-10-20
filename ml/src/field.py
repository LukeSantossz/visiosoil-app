"""Field photographs exported by the app, and featurisers that augment
(SPEC 0175).

The Python side has no A4-sheet reader, so the app measures each field
photograph and exports the region the classifier reads, already at the
canonical scale (SPEC 0174). This module reads that export into probe entries
and featurises them the way the archive is featurised: the patch grid cut from
the canonical region, then the descriptors. A variant entry is augmented by
`phone_augment` before the cut; the archive featuriser here does the same to an
archive photograph after its resample.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Mapping

import numpy as np
from PIL import Image, ImageOps

from . import phone_augment
from .descriptors import describe_patch
from .patches import cut_patches, patch_geometry, resample_to_canonical

#: The seed every variant is drawn under unless the study is given another.
DEFAULT_SEED = 20261019

MANIFEST_FILENAME = "manifest.json"


def load_field_export(directory: Path | str, cfg: Mapping) -> list[dict]:
    """The export's photographs as probe entries, in manifest order.

    Each entry's group is its soil sample, so a photograph is never split from
    its sample, and its label indexes the configured classes. A class the
    configuration does not hold, or a scale other than the configured
    canonical, is a different export from the one this run expects. A disc too
    small for the patch grid is left out, and named.
    """
    directory = Path(directory)
    rows = json.loads((directory / MANIFEST_FILENAME).read_text(encoding="utf-8"))
    canonical = cfg["preprocessing"]["canonical_mm_per_px"]
    entries = []
    for row in rows:
        if row["class"] not in cfg["classes"]:
            raise ValueError(
                f"{row['file']}: the class {row['class']!r} is not one of the "
                f"configured classes {cfg['classes']}"
            )
        if abs(float(row["canonical_mm_per_px"]) - canonical) > 1e-12:
            raise ValueError(
                f"{row['file']}: exported at {row['canonical_mm_per_px']} mm/px, "
                f"and the configured canonical is {canonical}"
            )
        try:
            patch_geometry(
                region_diameter_px=float(row["diameter"]),
                input_size=cfg["data"]["image_size"],
                canonical_mm_per_px=canonical,
                min_patches=cfg["preprocessing"]["min_patches"],
                stride_fraction=cfg["preprocessing"]["patch_stride_fraction"],
            )
        except ValueError as refusal:
            # The app measured the disc and its grid refused it, so the
            # classifier never read this photograph either.
            print(f"left out {row['file']}: {refusal}")
            continue
        path = str(directory / row["file"])
        entries.append(
            {
                "path": path,
                "image": path,
                "key": row["file"],
                "class": row["class"],
                "label": cfg["classes"].index(row["class"]),
                "group": row["sample"],
                "sample": row["sample"],
                "upsampled": bool(row["upsampled"]),
                "centre_y": float(row["centre_y"]),
                "centre_x": float(row["centre_x"]),
                "diameter": float(row["diameter"]),
            }
        )
    return entries


def _cut(region: Image.Image, centre, diameter: float, cfg: Mapping) -> np.ndarray:
    patches = cut_patches(
        region,
        centre_y=centre[0],
        centre_x=centre[1],
        region_diameter_px=diameter,
        input_size=cfg["data"]["image_size"],
        canonical_mm_per_px=cfg["preprocessing"]["canonical_mm_per_px"],
        min_patches=cfg["preprocessing"]["min_patches"],
        stride_fraction=cfg["preprocessing"]["patch_stride_fraction"],
    )
    return np.stack([describe_patch(patch) for patch in patches])


def variant_key(entry: Mapping, cfg: Mapping) -> str:
    """The name a variant is drawn under: the photograph's path inside the
    export, or inside the dataset root, so the draw does not depend on where
    either sits on this machine or how the command line spelled it."""
    if "key" in entry:
        return str(entry["key"])
    from .dataset import _stored_path
    from .manifest import dataset_root

    root = dataset_root(cfg["data"]["datasets_dir"], cfg["data"]["dataset_version"])
    return _stored_path(entry.get("image") or entry["path"], str(root))


def _augmented(region, centre, entry: Mapping, cfg: Mapping, seed: int):
    if entry.get("variant") is None:
        return region, centre
    return phone_augment.variant(
        region, centre, seed=seed, key=variant_key(entry, cfg), k=int(entry["variant"])
    )


def field_features(
    entry: Mapping, cfg: Mapping, seed: int = DEFAULT_SEED
) -> np.ndarray:
    """One exported region's patches as descriptor rows, augmented when the
    entry is a variant."""
    with Image.open(entry["image"]) as handle:
        region = handle.convert("RGB")
    centre = (entry["centre_y"], entry["centre_x"])
    region, centre = _augmented(region, centre, entry, cfg, seed)
    return _cut(region, centre, entry["diameter"], cfg)


def archive_features(
    entry: Mapping, cfg: Mapping, seed: int = DEFAULT_SEED
) -> np.ndarray:
    """An archive photograph's patches as descriptor rows: resampled to the
    canonical as `dataset._photograph_patches` does, augmented when the entry
    is a variant, then cut."""
    from .dataset import _canonical_region, _measurement_of, photograph_scale

    source = {**entry, "path": entry.get("image", entry["path"])}
    measurement = _measurement_of(source, photograph_scale(cfg))
    centre_y, centre_x, diameter = _canonical_region(source["path"], measurement, cfg)
    with Image.open(source["path"]) as handle:
        photograph = ImageOps.exif_transpose(handle).convert("RGB")
    region, _ = resample_to_canonical(
        photograph,
        measurement["mm_per_px"],
        cfg["preprocessing"]["canonical_mm_per_px"],
    )
    region, centre = _augmented(region, (centre_y, centre_x), source, cfg, seed)
    return _cut(region, centre, diameter, cfg)
