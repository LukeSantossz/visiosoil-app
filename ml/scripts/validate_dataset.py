"""Validate a dataset version and report how its evaluation folds are composed.

Reports every problem it can find in one pass, because the reader is a collector
fixing a spreadsheet: one list of faults is the difference between one correction
cycle and eight. Needs no TensorFlow, so a dataset can be checked on the machine
that holds it rather than on the machine that trains.

It also reports what the dish-rim reader measured (SPEC 0052): how far apart the
version's apparent scales are, and how many photographs are too coarse to reach
the canonical and therefore leave training (SPEC 0053).

Run from the `ml/` directory:

    python scripts/validate_dataset.py                 # the configured version
    python scripts/validate_dataset.py --version v2
    python scripts/validate_dataset.py --root path/to/v1 --splits-dir /tmp/splits

Exit codes: 0 the version is usable, 1 it is not. A version nobody has measured
yet still exits 0 — measuring is the next step of the pipeline, not a fault in
the version — but it has **no fold composition**, because since SPEC 0053 the
partition depends on the measurement. Asking for one anyway, with
`--splits-dir`, fails: nothing honest can be written.
"""

from __future__ import annotations

import argparse
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.config import load_config, resolve_paths  # noqa: E402
from src.dataset import create_folds_for_config, format_fold_composition  # noqa: E402
from src.manifest import (  # noqa: E402
    Manifest,
    ManifestError,
    check_class_coverage,
    check_scale_columns,
    check_setting_pairing,
    dataset_root,
    ARCHIVE_CLASSES,
    read_manifest,
    scale_spread,
    verify_directory,
)
from src.patches import PatchRefusal  # noqa: E402

#: How many photographs a partly measured version names before the rest are
#: counted. A gap the dish-rim reader left is usually a handful, and a cap only
#: keeps a pathological one from pushing the fold composition off the screen.
_UNMEASURED_NAMED = 10


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

    # Before the partition rather than after it, so a version that turns out to
    # have no composition has still said what it holds and what was measured of
    # it. Those facts are properties of the manifest and do not depend on any
    # fold being drawn.
    print(f"{len(manifest.rows)} photograph(s) in {manifest.version}")
    print(f"manifest digest {manifest.digest}")
    unmeasured = check_scale_columns(manifest)
    _report_scale(manifest, cfg["preprocessing"]["canonical_mm_per_px"], unmeasured)

    # Since SPEC 0053 the partition is a function of the measurement: a
    # photograph the patch grid refuses is in no fold, so `create_folds_for_config`
    # refuses a version nobody has measured. This guard decides *whether* to
    # partition and never how — `create_folds_for_config` stays the only thing
    # that draws one — and it reads `check_scale_columns`, the same function
    # `dataset.photograph_scale_of` raises on, so the validator never skips a
    # partition that would have succeeded and never attempts one that cannot.
    if unmeasured:
        return _report_no_composition(manifest, unmeasured, args.splits_dir)

    evaluation = cfg["evaluation"]
    with _splits_destination(args.splits_dir) as splits_dir:
        try:
            # Through `create_folds_for_config` and not `create_folds`, even
            # though `--root` reads a version the config does not name. The
            # partition this tool writes to disk is the one a run trains on, and
            # the filtering, the training restriction and the refusal record all
            # live in that function: assembling the call here again produced a
            # `splits.json` holding the eleven photographs the patch grid
            # refuses, from the same version the training path partitioned
            # without them.
            folds = create_folds_for_config(cfg, splits_dir, manifest=manifest)
        except ValueError as error:
            _report([str(error)])
            return 1

        print(
            f"{folds['counts']['splittable_groups']} splittable sample group(s), "
            f"{folds['counts']['train_only_groups']} restricted to training, "
            f"over {evaluation['k']} fold(s) and {evaluation['repeats']} repeat(s)"
        )
        print(format_fold_composition(folds, manifest))
        if args.splits_dir:
            print(f"splits.json written to {splits_dir}")
    return 0


def _report_no_composition(
    manifest: Manifest, unmeasured: list[str], splits_dir: str | None
) -> int:
    """Say why no composition follows, and answer for what the caller asked.

    The exit code follows what was asked for rather than what the version is,
    which is what keeps this consistent with the decision `_report_scale`
    records. Asked for a report, the report is complete: the version validates,
    its scale state is printed, and the composition is named as unavailable with
    the reason — so 0.

    Asked with `--splits-dir` to **publish** a partition, nothing publishable
    exists. Exiting 0 having written no `splits.json` is indistinguishable, to
    the shell script that chains a training run onto this command, from having
    written one; and `splits.json` is the artefact `src.crossval` reuses and
    `admit_images.py` treats as freezing the version against further admission,
    so the silent no-op there is the expensive kind. That is 1.
    """
    reason = (
        f"no fold composition: {len(unmeasured)} of {len(manifest.rows)} "
        f"photograph(s) in {manifest.version} carry no measured scale, and which "
        "photographs the patch grid refuses is what decides which groups a fold "
        "can hold"
    )
    if splits_dir is None:
        print(f"{reason}; measure the version and validate it again")
        return 0
    _report([f"{reason}, so no splits.json was written to {splits_dir}"])
    return 1


def _report_scale(
    manifest: Manifest, canonical_mm_per_px: float, unmeasured: list[str]
) -> None:
    """Report what the dish-rim reader measured over this version.

    Three facts, because a reader who has not read SPEC 0053 needs all three to
    know what the version will train on: how far apart its apparent scales are,
    which is the whole reason the patch pipeline resamples at all (ADR 0017);
    how many photographs are coarser than the canonical and therefore leave
    training; and how many rows carry no measurement yet.

    An unmeasured version is a step of the pipeline rather than a fault in it,
    so the version itself still validates. Ingestion writes the manifest and
    `scripts/measure_scale.py` reads it, so a validator that failed an unmeasured
    version would refuse exactly the state the measuring step exists to consume
    — the same reason `manifest.py` keeps the columns optional at parse time. It
    is reported rather than passed over, because silence about a measurement
    never taken reads as one that is fine. What such a version does not get is a
    fold composition; :func:`_report_no_composition` says so and decides the
    exit code from what the caller asked for.

    ``unmeasured`` is passed in rather than recomputed, so the report and that
    guard can never disagree about which rows lack a measurement.
    """
    total = len(manifest.rows)
    spread = scale_spread(manifest)
    if spread:
        measured = int(spread["count"])
        print(
            f"scale measured on {measured} of {total} photograph(s): "
            f"{spread['minimum']:.4f} to {spread['maximum']:.4f} mm/px, "
            f"a spread of {spread['spread']:.2f}x"
        )
        # Strictly coarser, which is what `patches.resample_to_canonical`
        # refuses: a photograph at the canonical needs no resampling, and one
        # above it could only reach the canonical by inventing grain that was
        # never photographed. An unmeasured row reads as 0.0 and is counted by
        # the clause below instead, never here.
        coarse = sum(
            1
            for row in manifest.rows
            if row.scale.get("mm_per_px", 0.0) > canonical_mm_per_px
        )
        print(
            f"{coarse} of {measured} measured photograph(s) are coarser than the "
            f"canonical {canonical_mm_per_px:.4f} mm/px and leave training "
            f"({PatchRefusal.TOO_COARSE.value})"
        )

    if unmeasured:
        print(
            f"{len(unmeasured)} of {total} photograph(s) carry no measured scale, "
            "so no patch grid can be cut on this version yet"
        )
        # Two states, two reports. A version nobody has measured gets one
        # exemplar, because every row names the same version-wide remedy and
        # printing it 221 times buries the count above it. A version that *was*
        # measured and has gaps gets the gaps by name: those are the photographs
        # the dish-rim reader refused, and which ones they are is the whole
        # information a collector needs to act.
        if len(unmeasured) == total:
            print(f"  e.g. {unmeasured[0]}")
        else:
            for problem in unmeasured[:_UNMEASURED_NAMED]:
                print(f"  - {problem}")
            if len(unmeasured) > _UNMEASURED_NAMED:
                print(f"  - ... and {len(unmeasured) - _UNMEASURED_NAMED} more")


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
