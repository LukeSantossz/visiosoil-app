"""Validate a dataset version and report how its evaluation folds are composed.

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
from src.dataset import create_folds, format_fold_composition  # noqa: E402
from src.manifest import (  # noqa: E402
    ManifestError,
    check_class_coverage,
    check_setting_pairing,
    class_images,
    dataset_root,
    ARCHIVE_CLASSES,
    read_manifest,
    sample_ids_by_image,
    train_only_sample_ids,
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
    # Two lists, two questions. `classes` is what the model emits and is what
    # the coverage check and the pool are built from; `ARCHIVE_CLASSES` is what
    # a manifest row may say, and is what the manifest is parsed against.
    archive_classes = ARCHIVE_CLASSES

    version = args.version or data["dataset_version"]

    # Resolving the version is inside the guard for the same reason as in
    # admit_images.py: a name that is not a version raises a plain `ValueError`,
    # which `ManifestError` does not cover.
    try:
        root = (
            Path(args.root)
            if args.root
            else dataset_root(data["datasets_dir"], version)
        )
    except ValueError as error:
        _report([str(error)])
        return 1

    print(f"Validating dataset version at {root}")

    # Most specific clause first: `ManifestError` subclasses `ValueError`, and
    # Python takes the first match rather than trying the rest.
    try:
        manifest = read_manifest(root, archive_classes, check_files=True)
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
    except (FileNotFoundError, ValueError) as error:
        _report([str(error)])
        return 1

    problems = (
        verify_directory(manifest)
        + check_class_coverage(manifest, classes)
        + check_setting_pairing(manifest)
    )
    if problems:
        _report(problems)
        return 1

    evaluation = cfg["evaluation"]
    with _splits_destination(args.splits_dir) as splits_dir:
        try:
            folds = create_folds(
                class_images(manifest, classes),
                k=evaluation["k"],
                repeats=evaluation["repeats"],
                seed=data["seed"],
                splits_dir=splits_dir,
                sample_ids=sample_ids_by_image(manifest),
                dataset_version=manifest.version,
                manifest_digest=manifest.digest,
                train_only_samples=train_only_sample_ids(manifest),
            )
        except ValueError as error:
            _report([str(error)])
            return 1

        print(f"{len(manifest.rows)} photograph(s) in {manifest.version}")
        print(f"manifest digest {manifest.digest}")
        print(
            f"{folds['counts']['splittable_groups']} splittable sample group(s), "
            f"{folds['counts']['train_only_groups']} restricted to training, "
            f"over {evaluation['k']} fold(s) and {evaluation['repeats']} repeat(s)"
        )
        print(format_fold_composition(folds, manifest))
        if args.splits_dir:
            print(f"splits.json written to {splits_dir}")
    return 0


@contextmanager
def _splits_destination(requested: str | None):
    """Yield where splits.json goes, discarding it unless one was requested.

    `create_folds` always persists. Defaulting to the configured `splits_dir`
    would make a command that reads like a report overwrite the artefact
    `src.crossval` reuses — and it is gitignored, so unrecoverably.
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
