"""Validate a dataset version and report how its splits are composed.

Reports every problem it can find in one pass, because the reader is a collector
fixing a spreadsheet: one list of faults is the difference between one correction
cycle and eight. Needs no TensorFlow, so a dataset can be checked on the machine
that holds it rather than on the machine that trains.

Run from the `ml/` directory:

    python scripts/validate_dataset.py                 # the configured version
    python scripts/validate_dataset.py --version v2
    python scripts/validate_dataset.py --root path/to/v1 --splits-dir /tmp/splits

Exit codes: 0 the version is usable, 1 it is not.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.dataset import create_splits  # noqa: E402
from src.manifest import (  # noqa: E402
    ManifestError,
    check_class_coverage,
    check_setting_pairing,
    class_images,
    dataset_root,
    format_composition,
    read_manifest,
    sample_ids_by_image,
    split_composition,
    verify_directory,
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
        "--splits-dir",
        help="Publish splits.json here. Omitted, the splits are generated in a "
        "temporary directory and discarded: reporting a composition must not "
        "replace the splits.json the training pipeline reuses.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    cfg = resolve_paths(load_config(args.config))
    data = cfg["data"]
    classes = cfg["classes"]

    version = args.version or data["dataset_version"]
    root = Path(args.root) if args.root else dataset_root(data["datasets_dir"], version)

    print(f"Validating dataset version at {root}")

    try:
        manifest = read_manifest(root, classes, check_files=True)
    except FileNotFoundError as error:
        _report([str(error)])
        return 1
    except ManifestError as error:
        _report(
            list(error.problems)
            + [
                "the directory comparison, the class-coverage check and the "
                "setting-pairing check were not run: they need a manifest that "
                "parses"
            ]
        )
        return 1

    problems = (
        verify_directory(manifest)
        + check_class_coverage(manifest, classes)
        + check_setting_pairing(manifest)
    )
    if problems:
        _report(problems)
        return 1

    with _splits_destination(args.splits_dir) as splits_dir:
        try:
            splits = create_splits(
                class_images(manifest, classes),
                val_split=data["val_split"],
                test_split=data["test_split"],
                seed=data["seed"],
                splits_dir=splits_dir,
                sample_ids=sample_ids_by_image(manifest),
                dataset_version=manifest.version,
                manifest_digest=manifest.digest,
            )
        except ValueError as error:
            _report([str(error)])
            return 1

        print(f"{len(manifest.rows)} photograph(s) in {manifest.version}")
        print(f"manifest digest {manifest.digest}")
        print(format_composition(split_composition(splits, manifest)))
        if args.splits_dir:
            print(f"splits.json written to {splits_dir}")
    return 0


@contextmanager
def _splits_destination(requested: str | None):
    """Yield where splits.json goes, discarding it unless one was requested.

    `create_splits` always persists. Defaulting to the configured `splits_dir`
    would make a command that reads like a report overwrite the artefact
    `src.train` reuses — and it is gitignored, so unrecoverably.
    """
    if requested:
        yield requested
        return
    with tempfile.TemporaryDirectory(prefix="visiosoil-splits-") as temporary:
        yield temporary


def _report(problems: list[str]) -> None:
    """Write every problem to stderr, so a redirected stdout still shows them."""
    count = len(problems)
    noun = "problem" if count == 1 else "problems"
    print(f"{count} {noun} found:", file=sys.stderr)
    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
