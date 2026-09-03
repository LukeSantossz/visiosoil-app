"""Measure the dish rim of every photograph in a dataset version (SPEC 0052).

Writes the measurement record the canonical millimetres per pixel is derived
from: one row per photograph with its capture population, the distribution
overall and per population, and every photograph that received no scale, named.
The record carries the dataset version and the manifest digest, so a record
taken over other data is recognisable as such rather than silently reused.

The canonical value is a contract value — a model trained at one canonical scale
cannot be served at another (ADR 0017) — so the record is committed while the
dataset version it describes is a build product (ADR 0019).

Needs no TensorFlow. Run from the `ml/` directory:

    python scripts/measure_scale.py                    # the configured version
    python scripts/measure_scale.py --version v2
    python scripts/measure_scale.py --out somewhere.json

Exit codes: 0 the record was written, 1 the version could not be read.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.manifest import (  # noqa: E402
    ARCHIVE_CLASSES,
    dataset_root,
    manifest_digest,
    read_manifest,
)
from src.scale import (  # noqa: E402
    CANONICAL_PERCENTILE,
    DISH_DIAMETER_MM,
    canonical_mm_per_px,
    read_dish_scale,
    summarise,
)

DEFAULT_OUT = Path(__file__).resolve().parents[1] / "measurements"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="dataset version; defaults to the config")
    parser.add_argument("--root", help="the version directory, bypassing the config")
    parser.add_argument("--config", help="path to config.yaml")
    parser.add_argument("--out", help="where to write the record")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    config = resolve_paths(load_config(args.config))
    if args.root:
        # The version labels the record and names the file it is written to, so
        # taking it from the config while the data comes from `--root` would
        # write a measurement of one version over another version's record,
        # under that version's name. The directory measured is the version.
        root = Path(args.root)
        version = args.version or root.name
    else:
        version = args.version or config["data"]["dataset_version"]
        root = Path(dataset_root(config["data"]["datasets_dir"], version))

    try:
        manifest = read_manifest(root, ARCHIVE_CLASSES)
    except (ValueError, FileNotFoundError) as error:
        # `ValueError` rather than `ManifestError`, which is one of its
        # subclasses: `validate_version_name` raises the base class, so a root
        # that is not named `vN` escaped this clause as a traceback.
        print(f"cannot read the manifest at {root}: {error}", file=sys.stderr)
        return 1

    rows = []
    for index, row in enumerate(manifest.rows, start=1):
        with Image.open(root / row.image) as image:
            reading = read_dish_scale(image)
        rows.append(
            {
                "image": row.image,
                "sample_id": row.sample_id,
                "texture_class": row.texture_class,
                "population": row.source_group,
                "mm_per_px": reading.mm_per_px,
                "disc_diameter_px": reading.disc_diameter_px,
                "rim_dispersion": reading.rim_dispersion,
                "ray_coverage": reading.ray_coverage,
                "refusal": None if reading.refusal is None else reading.refusal.value,
            }
        )
        print(f"  {index}/{len(manifest.rows)} {row.image}", file=sys.stderr)

    readings = [row["mm_per_px"] for row in rows if row["mm_per_px"] is not None]
    if not readings:
        print(f"no photograph of {version} yielded a scale", file=sys.stderr)
        return 1

    record = {
        "spec": "0052",
        "dataset_version": version,
        "manifest_digest": manifest_digest(root),
        "dish_diameter_mm": DISH_DIAMETER_MM,
        "canonical_percentile": CANONICAL_PERCENTILE,
        "canonical_mm_per_px": canonical_mm_per_px(readings),
        "summary": summarise(rows).as_dict(),
        "photographs": rows,
    }

    destination = Path(args.out) if args.out else DEFAULT_OUT / f"dish-scale-{version}.json"
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(
        json.dumps(record, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )
    print(
        f"{len(readings)} of {len(rows)} photographs read; "
        f"canonical {record['canonical_mm_per_px']:.4f} mm/px -> {destination}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
