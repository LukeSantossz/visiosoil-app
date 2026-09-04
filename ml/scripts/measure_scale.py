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
    python scripts/measure_scale.py --from-record measurements/dish-scale-v1.json

Reading the rim of the archive takes about seven minutes and the manifest it
writes into is a build product (ADR 0019), so a rebuilt version would pay that
again for a measurement that has not changed. `--from-record` fills the manifest
from the committed record instead, reading no photograph, and refuses a record
whose manifest digest is not the one on disk.

Exit codes: 0 the record was written or the manifest was filled, 1 the version
could not be read or the record does not describe it.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.manifest import (  # noqa: E402
    ARCHIVE_CLASSES,
    SCALE_COLUMNS,
    dataset_root,
    read_manifest,
    unmeasured_digest,
    write_manifest,
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
    parser.add_argument(
        "--from-record",
        help="fill the manifest from this record instead of reading the images",
    )
    return parser.parse_args(argv)


def _producing_command(args: argparse.Namespace, version: str) -> str:
    """Return the invocation that reproduces this record, run from `ml/`.

    Normalised rather than `sys.argv`: the record has to reproduce byte for
    byte, and the interpreter path and flag order a person happened to type are
    not part of what produced the numbers. It names the version because that is
    what selects the data, and the root only when one was given.
    """
    parts = ["python", "scripts/measure_scale.py"]
    if args.root:
        parts += ["--root", str(args.root)]
    parts += ["--version", version]
    return " ".join(parts)


def _scale_of(reading) -> dict[str, float]:
    """The four numbers the patch grid needs, or nothing when there is no scale.

    Four and not the one `disc_diameter_px` SPEC 0037 names: cutting a grid
    needs the region's centre as well as its size, and neither record said so.
    """
    if reading.mm_per_px is None:
        return {}
    return {
        "mm_per_px": reading.mm_per_px,
        "disc_diameter_px": reading.disc_diameter_px,
        "disc_centre_x_px": reading.centre_x_px,
        "disc_centre_y_px": reading.centre_y_px,
        "frame_width_px": float(reading.frame_width_px),
        "frame_height_px": float(reading.frame_height_px),
    }


def _fill_from_record(root: Path, record_path: Path) -> int:
    """Write the recorded measurement into the manifest, reading no image."""
    try:
        record = json.loads(Path(record_path).read_text(encoding="utf-8"))
        manifest = read_manifest(root, ARCHIVE_CLASSES)
    except (ValueError, FileNotFoundError, json.JSONDecodeError) as error:
        print(f"cannot fill {root} from {record_path}: {error}", file=sys.stderr)
        return 1

    if not isinstance(record, dict):
        # A JSON array or scalar reaches `record.get` below and raises
        # `AttributeError`, which is a traceback rather than an exit code.
        print(
            f"{record_path} is not a measurement record: its root is a "
            f"{type(record).__name__}, not an object",
            file=sys.stderr,
        )
        return 1

    digest = unmeasured_digest(root)
    if record.get("manifest_digest") != digest:
        # The digest is the only thing that ties a recorded row to a photograph
        # rather than to a path that happens to match. A record of another
        # version would fill plausible numbers measured from other images.
        print(
            f"{record_path} was taken over manifest "
            f"{record.get('manifest_digest')} and {root} is {digest}",
            file=sys.stderr,
        )
        return 1

    recorded = {
        row["image"]: row
        for row in record.get("photographs", [])
        if isinstance(row, dict) and "image" in row
    }

    # Checked before anything is written, not row by row while writing. This
    # function replaces the manifest's scale columns wholesale, so a record that
    # covers only some photographs would blank the rest — leaving a version that
    # reads as ingested and never measured, which is a state nobody caused on
    # purpose and which no error would have announced.
    missing = [row.image for row in manifest.rows if row.image not in recorded]
    if missing:
        print(
            f"{record_path} describes {len(recorded)} photograph(s) and "
            f"{manifest.version} holds {len(manifest.rows)}; {len(missing)} are "
            f"not in the record, the first being {missing[0]}",
            file=sys.stderr,
        )
        return 1

    filled = []
    for row in manifest.rows:
        measurement = recorded[row.image]
        filled.append(
            replace(
                row,
                scale={
                    column: measurement[column]
                    for column in SCALE_COLUMNS
                    if measurement.get(column) is not None
                },
            )
        )

    write_manifest(root, filled)
    measured = sum(1 for row in filled if row.scale)
    print(f"{measured} of {len(filled)} rows filled from {record_path}")
    return 0


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

    if args.from_record:
        return _fill_from_record(root, Path(args.from_record))

    try:
        manifest = read_manifest(root, ARCHIVE_CLASSES)
    except (ValueError, FileNotFoundError) as error:
        # `ValueError` rather than `ManifestError`, which is one of its
        # subclasses: `validate_version_name` raises the base class, so a root
        # that is not named `vN` escaped this clause as a traceback.
        print(f"cannot read the manifest at {root}: {error}", file=sys.stderr)
        return 1

    rows = []
    measured = []
    for index, row in enumerate(manifest.rows, start=1):
        with Image.open(root / row.image) as image:
            reading = read_dish_scale(image)
        measured.append(replace(row, scale=_scale_of(reading)))
        rows.append(
            {
                "image": row.image,
                "sample_id": row.sample_id,
                "texture_class": row.texture_class,
                "population": row.source_group,
                "mm_per_px": reading.mm_per_px,
                "disc_diameter_px": reading.disc_diameter_px,
                "disc_centre_x_px": reading.centre_x_px,
                "disc_centre_y_px": reading.centre_y_px,
                "frame_width_px": reading.frame_width_px or None,
                "frame_height_px": reading.frame_height_px or None,
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
        "command": _producing_command(args, version),
        "dataset_version": version,
        "manifest_digest": unmeasured_digest(root),
        "dish_diameter_mm": DISH_DIAMETER_MM,
        "canonical_percentile": CANONICAL_PERCENTILE,
        "canonical_mm_per_px": canonical_mm_per_px(readings),
        "summary": summarise(rows).as_dict(),
        "photographs": rows,
    }

    # The manifest carries what the patch grid reads; the record carries the
    # evidence and the distribution. Writing both from one pass is what keeps
    # them describing the same measurement. `--out` chooses where the record
    # goes and says nothing about the manifest, which is why it no longer
    # suppresses this write: the recorded digest blanks the scale columns, so
    # writing them cannot change what the record claims to describe.
    write_manifest(root, measured)

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
