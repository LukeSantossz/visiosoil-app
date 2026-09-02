"""Write the delivered sample archive into an immutable dataset version.

The archive is source material: English class folders, original filenames, and
three capture populations in two containers. This script is the only thing in
the pipeline that reads it. What every experiment names afterwards is the
version written here.

HEIC is converted to PNG, JPEG is copied byte for byte, the class comes from the
folder by name, and a column the archive cannot supply is written `unknown`
rather than guessed. The reasoning is in
`docs/specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md`.

Run from the `ml/` directory:

    python scripts/ingest_archive.py                          # data/archive -> v1
    python scripts/ingest_archive.py --version v2
    python scripts/ingest_archive.py --source path/to/archive --root path/to/v1

Exit codes: 0 the version was written, 1 the archive was refused, 2 the target
version already holds a manifest and was not overwritten.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.ingest import ArchiveError, ingest_archive, version_root  # noqa: E402
from src.manifest import (  # noqa: E402
    ARCHIVE_CLASSES,
    MANIFEST_FILENAME,
    manifest_path,
)

#: Where the delivery sits by default, relative to the resolved data root. It is
#: git-ignored: the archive is 214 MB of image data and the version is what the
#: repository records.
DEFAULT_ARCHIVE_DIRNAME = "archive"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--source",
        help="The archive directory. Defaults to the sibling 'archive' directory "
        "of the configured datasets root.",
    )
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
        "--force",
        action="store_true",
        help="Write even though the version already holds a manifest. A dataset "
        "version is immutable, so this is for re-running an ingestion that was "
        "never used, never for changing one an experiment has read.",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Do not rewrite a target file that is already this photograph, "
        "verified by comparison. For resuming an interrupted ingestion.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    data = cfg["data"]

    try:
        root = (
            Path(args.root)
            if args.root
            else version_root(data["datasets_dir"], args.version or data["dataset_version"])
        )
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 1

    source = (
        Path(args.source)
        if args.source
        else Path(data["datasets_dir"]).parent / DEFAULT_ARCHIVE_DIRNAME
    )

    if manifest_path(root).exists() and not args.force:
        print(
            f"{root} already holds a {MANIFEST_FILENAME}. A dataset version is "
            f"immutable once written, so ingest into the next version instead, or "
            f"pass --force if this one was never read by an experiment",
            file=sys.stderr,
        )
        return 2

    try:
        report = ingest_archive(
            # Ingestion writes every archive class into the version, so it
            # takes the archive's vocabulary and not the model's four.
            source,
            root,
            classes=ARCHIVE_CLASSES,
            skip_existing=args.skip_existing,
        )
    except ArchiveError as error:
        print(str(error), file=sys.stderr)
        return 1

    print(report.render())
    print(f"manifest written to {manifest_path(root)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
