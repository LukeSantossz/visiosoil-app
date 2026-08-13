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
manifest itself is not valid, 3 the version is frozen by an existing split.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.admission import admit, quarantine_refused, write_refusal_report  # noqa: E402
from src.config import load_config, resolve_paths  # noqa: E402
from src.manifest import (  # noqa: E402
    QUARANTINE_DIRNAME,
    REJECTED_FILENAME,
    Manifest,
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
        help="Rewrite the manifest with the admitted rows, quarantine the refused "
        "images, and write the refusal report. Without it, nothing on disk changes.",
    )
    parser.add_argument(
        "--splits-dir",
        help="Where to look for a splits.json that already claims this version. "
        "Defaults to data.splits_dir.",
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

    if args.write:
        claimed_by = _split_claiming(args.splits_dir or data["splits_dir"], manifest)
        if claimed_by is not None:
            print(
                f"refusing to rewrite {manifest.version}: a dataset version is "
                f"immutable once a split has been generated from it, and "
                f"{claimed_by} records this manifest's digest. Collect into the "
                f"next version instead, or regenerate that split afterwards",
                file=sys.stderr,
            )
            return 3

    result = admit(manifest)

    print(f"{len(manifest.rows)} candidate(s) in {manifest.version}")
    print(f"admitted {len(result.admitted)}, refused {len(result.refused)}")
    for refusal in result.refused:
        print(f"  refused {refusal.image}: {refusal.verdict}: {refusal.reason}")

    if args.write:
        # Quarantine first. It validates the whole batch before moving anything,
        # so a refused file that has gone missing stops the run with the manifest
        # still intact — rewriting first and failing here is what would leave rows
        # dropped while their files stayed put.
        quarantined = quarantine_refused(root, result.refused)
        write_manifest(root, result.admitted)
        report = write_refusal_report(root, result.refused)
        print(f"manifest rewritten with the admitted rows; refusals in {report.name}")
        if quarantined:
            print(
                f"{len(quarantined)} refused image(s) moved into "
                f"{QUARANTINE_DIRNAME}/, so the version still validates"
            )
    else:
        print(
            "dry run: nothing written. Re-run with --write to rewrite the manifest, "
            f"quarantine the refused images, and produce {REJECTED_FILENAME}"
        )

    return 1 if result.refused else 0


def _split_claiming(splits_dir: str, manifest: Manifest) -> Path | None:
    """Return a splits.json claiming this dataset version, if one exists.

    Keyed on the **version**, not on the digest. Admission rewrites the manifest,
    which moves its digest: a split recording the current digest is valid now and
    would be broken by the rewrite, and a split recording an older digest of the
    same version is already unverifiable — rewriting again makes that permanent
    instead of telling the operator to collect into the next version. Either way
    the version is frozen, which is what the immutability rule says.
    """
    path = Path(splits_dir) / "splits.json"
    if not path.is_file():
        return None
    try:
        recorded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        # An unreadable split cannot be shown to claim this version, and failing
        # here would block admission on an unrelated corrupt file.
        return None
    return path if recorded.get("dataset_version") == manifest.version else None


if __name__ == "__main__":
    raise SystemExit(main())
