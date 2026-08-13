"""Run the SPEC 0030 quality criteria over a dataset version's candidates.

An image the criteria call `blocking` does not enter the dataset. An `advisory`
image does, with its failing criteria recorded, because a marginal photograph is
representative of real conditions and excluding it would curate the dataset into
the narrow subpopulation ADR 0009 warns about. Every admitted image carries its
seven measured metrics, so a threshold recalibration can be recomputed from the
manifest without re-reading a single file.

Writing is opt-in. The manifest belongs to the collector who authored it, and
admission rewrites it to hold only the admitted rows, so the default is a report.

Run from the `ml/` directory:

    python scripts/admit_images.py                     # report only
    python scripts/admit_images.py --write             # rewrite the manifest
    python scripts/admit_images.py --root path/to/v1 --write

Exit codes: 0 every candidate was admitted, 1 something was refused, 2 the
manifest itself is not valid.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.admission import admit, write_refusal_report  # noqa: E402
from src.config import load_config, resolve_paths  # noqa: E402
from src.manifest import (  # noqa: E402
    REJECTED_FILENAME,
    ManifestError,
    dataset_root,
    read_manifest,
    write_manifest,
)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--version",
        help="Dataset version directory name. Defaults to data.dataset_version.",
    )
    parser.add_argument(
        "--root",
        help="Path to the version directory, overriding --version entirely.",
    )
    parser.add_argument("--config", help="Path to config.yaml.")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Rewrite the manifest with the admitted rows and write the refusal "
        "report. Without it, nothing on disk changes.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    data = cfg["data"]

    version = args.version or data["dataset_version"]
    root = Path(args.root) if args.root else dataset_root(data["datasets_dir"], version)

    try:
        manifest = read_manifest(root, cfg["classes"], check_files=True)
    except (FileNotFoundError, ManifestError) as error:
        print(str(error), file=sys.stderr)
        return 2

    result = admit(manifest)

    print(f"{len(manifest.rows)} candidate(s) in {manifest.version}")
    print(f"admitted {len(result.admitted)}, refused {len(result.refused)}")
    for refusal in result.refused:
        print(f"  refused {refusal.image}: {refusal.verdict} — {refusal.reason}")

    if args.write:
        write_manifest(root, result.admitted)
        report = write_refusal_report(root, result.refused)
        print(f"manifest rewritten with the admitted rows; refusals in {report.name}")
    else:
        print(
            "dry run: nothing written. Re-run with --write to rewrite the manifest "
            f"and produce {REJECTED_FILENAME}"
        )

    return 1 if result.refused else 0


if __name__ == "__main__":
    raise SystemExit(main())
