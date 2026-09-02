"""The dataset manifest: its schema, its loader, and its validator.

The manifest is the dataset. A CSV at the root of each dataset version, authored
by the collector, is the authoritative record of what the dataset contains; the
directory walk is a check that the files on disk agree with it, not the source of
truth. An image with no row is an error and a row with no image is an error;
neither is skipped, because a dataset that silently differs from its record
cannot support a reproducible experiment.

This module imports no TensorFlow. Validating a manifest has to be possible in
any environment that can read a CSV, including one where the training stack is
not installed.

Specified by ``docs/specs/0033-dataset-protocol-manifest-and-splits.md``.
"""

import csv
import hashlib
import io
import os
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path, PurePosixPath, PureWindowsPath
from typing import Mapping, Sequence

#: The manifest lives at the root of a dataset version directory.
MANIFEST_FILENAME = "manifest.csv"

#: Written by admission for the candidates it refused, next to the manifest.
REJECTED_FILENAME = "admission-rejected.csv"

#: Every column a collector must supply. Order is the order they are written.
REQUIRED_COLUMNS = (
    "sample_id",
    "texture_class",
    "image",
    "setting",
    "site",
    "device",
    "captured_at",
)

#: Columns that must not appear. No granulometric value and no laboratory
#: reference enters this process, so a manifest carrying one is rejected rather
#: than having the column ignored: an ignored column arrives quietly and is then
#: read by something later, which is how a withdrawn decision comes back.
FORBIDDEN_COLUMNS = frozenset({"sand_pct", "silt_pct", "clay_pct", "lab_report"})

#: The two presentation conditions the protocol pairs on one physical sample.
#: ``in_situ`` is deliberately absent: the mode is deferred, and a silently
#: accepted value is how an uncovered condition enters a dataset that reports
#: itself as covering it.
VALID_SETTINGS = ("dish", "paper")

#: The seven SPEC 0030 metrics, recorded per admitted image so a threshold
#: recalibration can be recomputed without re-reading a single file.
METRIC_COLUMNS = (
    "blur_score",
    "mean_luminance",
    "clipped_fraction",
    "contrast_score",
    "color_cast_score",
    "specular_fraction",
    "roi_side_px",
)

QUALITY_VERDICT_COLUMN = "quality_verdict"
QUALITY_FLAGS_COLUMN = "quality_flags"

#: Flags are joined with a pipe rather than a comma or a semicolon: both of
#: those are CSV delimiters here or in a pt-BR spreadsheet export.
FLAG_SEPARATOR = "|"

#: Suffixes treated as dataset images when the directory is compared with the
#: manifest. Shared with :mod:`src.dataset` so the two cannot drift.
IMAGE_SUFFIXES = frozenset({".jpg", ".jpeg", ".png", ".bmp", ".webp"})

#: Suffixes that are images the pipeline cannot read, listed so a file offered
#: in one is refused by name with the remedy rather than skipped as a non-image.
#: See docs/specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md.
UNREADABLE_IMAGE_SUFFIXES = frozenset({".heic", ".heif"})

#: The literal a column carries when the archive cannot supply it. Written
#: rather than left blank, and rather than filled with a plausible value: an
#: invented date is indistinguishable from a measured one once it is in the
#: column. Accepted by `device` and `captured_at`, and by nothing else.
UNKNOWN = "unknown"

#: Recorded per row so a capture population that correlates with the label stays
#: visible to evaluation, and so a derived sample identity is never read as a
#: declared one. Optional in a manifest a collector authored by hand; written by
#: ingestion, which knows all of them.
PROVENANCE_COLUMNS = (
    "source_format",
    "source_group",
    "source_width",
    "source_height",
    "sample_id_source",
)

#: How a row's `sample_id` was arrived at. `filename` means the collector's own
#: identifier was in the name; `capture-burst` means it was derived from the
#: photograph's capture time because the name declared nothing. A derived
#: identity is weaker evidence than a declared one and every figure that rests
#: on grouping has to be readable as such, so it is recorded rather than assumed.
VALID_SAMPLE_ID_SOURCES = ("filename", "capture-burst")

#: The capture populations of the delivered archive, told apart by evidence
#: rather than by filename spelling: `C` is the native HEIC session, `A` is the
#: exported JPEG that kept its EXIF, `B` is the transported JPEG that lost it.
VALID_SOURCE_GROUPS = ("A", "B", "C")

VALID_SOURCE_FORMATS = ("heic", "jpeg", "png")

#: A sample photographed only in one of these groups may enter the training
#: split and never validation or test. Group B is a second generation at reduced
#: resolution whose population is confounded with the label, and the application
#: captures directly from the camera, so its degradation is not representative
#: of deployment. Letting it score would flatter the one measurement that has to
#: be honest. ADR 0016 and SPEC 0040 D6.
TRAIN_ONLY_SOURCE_GROUPS = frozenset({"B"})

#: Where admission moves a refused image. It stays inside the version as
#: evidence, so the directory is excluded from the manifest-to-disk comparison
#: and no row may declare a path inside it.
QUARANTINE_DIRNAME = "rejected"

#: A dataset version directory: vN, numbered from 1. `latest` would point at
#: different data on different days, and `v0` is a typo rather than a dataset.
_VERSION_PATTERN = re.compile(r"^v[1-9][0-9]*$")

#: `captured_at` is an ISO 8601 calendar date and nothing else. `fromisoformat`
#: alone also accepts `20260812` and `2026-W33-3`, which the protocol and the
#: error message both rule out — and which no two readers group the same way.
_ISO_DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")

_HEADER_ROW_COUNT = 1


class ManifestError(ValueError):
    """Every problem found in one manifest, reported together.

    Aggregated rather than raised on the first fault because the reader is a
    collector fixing a spreadsheet: one pass over a list of problems is the
    difference between one correction cycle and eight.
    """

    def __init__(self, problems: Sequence[str]) -> None:
        self.problems = tuple(problems)
        count = len(self.problems)
        noun = "problem" if count == 1 else "problems"
        detail = "".join(f"\n  - {problem}" for problem in self.problems)
        super().__init__(f"{MANIFEST_FILENAME} rejected ({count} {noun}):{detail}")


@dataclass(frozen=True)
class ManifestRow:
    """One photograph of one physical sample."""

    sample_id: str
    texture_class: str
    image: str
    setting: str
    site: str
    device: str
    captured_at: str
    quality_verdict: str = ""
    quality_flags: tuple[str, ...] = ()
    metrics: Mapping[str, float] = field(default_factory=dict)
    source_format: str = ""
    source_group: str = ""
    source_width: int = 0
    source_height: int = 0
    sample_id_source: str = ""


@dataclass(frozen=True)
class Manifest:
    """A parsed manifest, with the version it belongs to and its digest."""

    version: str
    root: Path
    digest: str
    rows: tuple[ManifestRow, ...]


def validate_version_name(version: str) -> str:
    """Return ``version`` if it names an immutable version directory.

    A version is a directory name, never a path. `config.yaml` validates its own
    value, but a version also arrives from a ``--version`` flag, and joined
    straight onto the datasets root a value like ``../elsewhere`` would let a
    writing command operate outside ``data/datasets`` entirely. One definition,
    used by both entry points.

    Raises:
        ValueError: If the name is not ``vN``, numbered from 1.
    """
    if not _VERSION_PATTERN.match(str(version)):
        raise ValueError(
            f"dataset version must name an immutable version directory as vN, "
            f"numbered from 1, got {version!r}"
        )
    return version


def dataset_root(datasets_dir: str | Path, version: str) -> Path:
    """Return the directory of one dataset version.

    One function builds this path, so a version is never assembled by string
    concatenation at a call site and never escapes the datasets root.
    """
    return Path(datasets_dir) / validate_version_name(version)


def manifest_path(root: str | Path) -> Path:
    """Return the manifest path inside a dataset version root."""
    return Path(root) / MANIFEST_FILENAME


def manifest_digest(root: str | Path) -> str:
    """Return the SHA-256 of the manifest bytes.

    Over the bytes rather than the parsed content, so a split can be shown to
    belong to the exact file it was generated from. It is stable across
    platforms provided the file is committed with consistent line endings.
    """
    return hashlib.sha256(manifest_path(root).read_bytes()).hexdigest()


#: The order a manifest is written in. One writer owns it, so a manifest that
#: has been through admission is never reshaped by whoever wrote it last.
WRITE_COLUMNS = (
    *REQUIRED_COLUMNS,
    QUALITY_VERDICT_COLUMN,
    QUALITY_FLAGS_COLUMN,
    *METRIC_COLUMNS,
    *PROVENANCE_COLUMNS,
)


#: A manifest is staged here and then renamed over the real one, so a reader
#: never sees a half-written record.
STAGED_SUFFIX = ".staged"


def write_manifest(root: str | Path, rows: Sequence[ManifestRow]) -> Path:
    """Write ``rows`` as the manifest of the dataset version at ``root``."""
    return commit_staged_manifest(stage_manifest(root, rows), root)


def stage_manifest(root: str | Path, rows: Sequence[ManifestRow]) -> Path:
    """Write the manifest content beside the real file without replacing it.

    Split from the commit so a caller that also has filesystem work to do can
    have every way of failing happen before anything is replaced. Line endings
    are forced to LF rather than left to the platform, because the digest is over
    the file bytes and a split has to be shown to belong to the same manifest on
    any machine.
    """
    path = manifest_path(root).with_name(MANIFEST_FILENAME + STAGED_SUFFIX)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(WRITE_COLUMNS)
        for row in rows:
            writer.writerow(
                [
                    row.sample_id,
                    row.texture_class,
                    row.image,
                    row.setting,
                    row.site,
                    row.device,
                    row.captured_at,
                    row.quality_verdict,
                    FLAG_SEPARATOR.join(row.quality_flags),
                    *(_format_metric(row.metrics.get(column)) for column in METRIC_COLUMNS),
                    row.source_format,
                    row.source_group,
                    row.source_width or "",
                    row.source_height or "",
                    row.sample_id_source,
                ]
            )
    return path


def commit_staged_manifest(staged: Path, root: str | Path) -> Path:
    """Rename a staged manifest over the real one.

    A single rename on one filesystem, so there is no window in which the
    manifest is neither the old record nor the new one.
    """
    path = manifest_path(root)
    os.replace(staged, path)
    return path


def discard_staged_manifest(staged: Path) -> None:
    """Remove a staged manifest that will not be committed.

    Left behind, it reads as a record of something rather than as the debris of a
    run that failed.
    """
    staged.unlink(missing_ok=True)


#: Every texture class the delivered archive contains.
#:
#: Not the same list as ``cfg["classes"]``, and the distinction is the point.
#: This is what a manifest row *may* say, fixed by what was delivered; the
#: configured list is what the model *emits*, and ADR 0016 keeps Siltosa out of
#: the first model while SPEC 0040 ingests every archive photograph including
#: its three Siltosa sample groups. The two lists were identical by coincidence
#: until the class list dropped to four, at which point reading a manifest
#: against the model's classes rejected rows the archive was supposed to hold.
#:
#: Declared here rather than derived from ``ingest.ARCHIVE_CLASS_BY_FOLDER``,
#: whose keys are delivered directory names: this module owns the manifest
#: contract and must not import the ingester. They cannot drift — a test asserts
#: the folder map's values are exactly these.
ARCHIVE_CLASSES = (
    "Arenosa",
    "Media",
    "Siltosa",
    "Muito Argilosa",
    "Argilosa",
)


def read_manifest(
    root: str | Path, classes: Sequence[str], *, check_files: bool = False
) -> Manifest:
    """Parse and validate the manifest at ``root``.

    Args:
        root: The dataset version directory.
        classes: The accepted texture classes, from ``config.yaml``.
        check_files: Also report a row whose image is not on disk. Orphan files
            are reported by :func:`verify_directory`, which walks the directory.

    Returns:
        The parsed manifest.

    Raises:
        FileNotFoundError: If the manifest itself is not there.
        ValueError: If ``root`` is not named for a dataset version. Plain rather
            than a `ManifestError`, because the fault is the path the caller
            passed and not the file's contents; both entry points catch
            `ValueError` so it reaches an exit code rather than a traceback.
        ManifestError: With every problem found, never only the first.
    """
    root = Path(root)
    # The version is the directory name and is published as a split's
    # `dataset_version`, so a `--root` pointing at a directory called `latest`
    # would record provenance the immutability contract does not allow.
    validate_version_name(root.name)
    path = manifest_path(root)
    if not path.exists():
        raise FileNotFoundError(
            f"Dataset manifest not found: {path}. Every dataset version holds a "
            f"{MANIFEST_FILENAME} at its root"
        )

    text = _decode(path)
    lines = text.splitlines()
    _reject_a_semicolon_export(lines[0] if lines else "")

    reader = csv.DictReader(io.StringIO(text))
    columns = list(reader.fieldnames or [])
    _reject_a_broken_header(columns)

    rows, problems = _parse_rows(reader, root, classes, columns, check_files=check_files)
    problems.extend(_cross_row_problems(rows))

    if problems:
        raise ManifestError(problems)

    return Manifest(
        version=root.name,
        root=root,
        digest=manifest_digest(root),
        rows=tuple(rows),
    )


def read_manifest_or_none(
    root: str | Path, classes: Sequence[str], *, check_files: bool = False
) -> Manifest | None:
    """Return the manifest at ``root``, or ``None`` when there is none.

    Only a missing file yields ``None``. A manifest that exists and is wrong
    still raises, because "absent" and "broken" have different remedies and a
    caller that treats them alike falls back to a legacy path on a typo.
    """
    try:
        return read_manifest(root, classes, check_files=check_files)
    except FileNotFoundError:
        return None


def derived_sample_ids(manifest: Manifest) -> set[str]:
    """Return the samples whose identity was inferred rather than declared.

    Every figure that rests on grouping — a leakage guarantee above all — is
    only as strong as the grouping, so which rows are held together by an
    inference is a number a reader is entitled to see.
    """
    return {
        row.sample_id
        for row in manifest.rows
        if row.sample_id_source == "capture-burst"
    }


def train_only_sample_ids(manifest: Manifest) -> set[str]:
    """Return the samples that may enter training and never validation or test.

    A sample qualifies only when *every* photograph of it comes from a
    train-only source group. One photograph from another group is evidence
    representative of deployment, and holding that sample out would discard a
    measurement rather than protect one.
    """
    groups_by_sample: dict[str, set[str]] = defaultdict(set)
    for row in manifest.rows:
        groups_by_sample[row.sample_id].add(row.source_group)

    return {
        sample_id
        for sample_id, groups in groups_by_sample.items()
        if groups and groups <= TRAIN_ONLY_SOURCE_GROUPS
    }


def check_unreadable_images(root: str | Path) -> list[str]:
    """Report every file in a container the pipeline cannot decode.

    Refused by name with the remedy, never skipped. `.heic` is not in
    `IMAGE_SUFFIXES`, so without this check a HEIC file dropped into a version
    is neither a manifest row nor an orphan: it is simply not seen, which is how
    58 % of the delivered archive stayed invisible to both pipelines until it was
    measured. See docs/specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md.
    """
    root = Path(root)
    quarantine = (root / QUARANTINE_DIRNAME).resolve()
    return [
        f"{path.resolve().relative_to(root.resolve()).as_posix()} is in a container "
        f"the pipeline cannot decode. Convert the archive once with "
        f"`python scripts/ingest_archive.py`, which writes PNG into the version; "
        f"a file left in this format is invisible to both the training decoder "
        f"and the application"
        for path in sorted(root.rglob("*"))
        if path.is_file()
        and path.suffix.lower() in UNREADABLE_IMAGE_SUFFIXES
        and not path.resolve().is_relative_to(quarantine)
    ]


def verify_directory(manifest: Manifest) -> list[str]:
    """Report every disagreement between the manifest and the files on disk."""
    quarantine = (manifest.root / QUARANTINE_DIRNAME).resolve()
    declared = {(manifest.root / row.image).resolve(): row.image for row in manifest.rows}
    present = {
        path.resolve()
        for path in manifest.root.rglob("*")
        if path.is_file()
        and path.suffix.lower() in IMAGE_SUFFIXES
        and not path.resolve().is_relative_to(quarantine)
    }

    problems = [
        f"row image not found on disk: {declared[path]}"
        for path in sorted(declared.keys() - present)
    ]
    problems.extend(
        f"image on disk has no manifest row: "
        f"{orphan.relative_to(manifest.root.resolve()).as_posix()}"
        for orphan in sorted(present - declared.keys())
    )
    problems.extend(check_unreadable_images(manifest.root))
    return problems


def covered_settings(manifest: Manifest) -> tuple[str, ...]:
    """The settings this version covers, in the order ``VALID_SETTINGS`` declares."""
    present = {row.setting for row in manifest.rows}
    return tuple(setting for setting in VALID_SETTINGS if setting in present)


def check_setting_pairing(manifest: Manifest) -> list[str]:
    """Report every sample not covering the same settings as the version does.

    The original rule required both settings of every sample, because pairing is
    what lets the background effect be measured within one physical sample
    rather than across two populations. ADR 0018 dissolved that need — a patch
    cut from inside the soil region is soil and nothing else, so what the model
    sees carries no background — and the delivered archive is single-condition,
    so the rule as written would report all 171 of its samples as broken.

    What is kept is the fault the rule actually exists to catch: a version that
    is *half* paired, where a background effect and a sample effect cannot be
    told apart. Coverage must be uniform across samples; how many photographs
    each setting holds is not constrained, because the archive holds one to four
    per sample and no criterion depends on the count. A single-condition version
    is legitimate and is reported by :func:`format_composition` on every run, so
    it is declared rather than silent.
    """
    settings_by_sample: dict[str, set[str]] = defaultdict(set)
    for row in manifest.rows:
        settings_by_sample[row.sample_id].add(row.setting)

    expected = covered_settings(manifest)
    if not expected:
        return []

    problems = []
    for sample_id in sorted(settings_by_sample):
        held = settings_by_sample[sample_id]
        if held == set(expected):
            continue
        problems.append(
            f"sample '{sample_id}' covers {', '.join(sorted(held))} while version "
            f"{manifest.version} covers {', '.join(expected)}; coverage must be "
            f"uniform across samples or a setting effect cannot be told from a "
            f"sample effect"
        )
    return problems


def check_class_coverage(manifest: Manifest, classes: Sequence[str]) -> list[str]:
    """Report every declared class the manifest holds no photograph of.

    Not a thin-data warning. The class list is the model's output order, so a
    class at zero is dropped from :func:`class_images` and every label after it
    is reindexed: a four-class split silently disagrees with the five-class
    contract the product ships, and both sides look internally consistent.
    """
    present = {row.texture_class for row in manifest.rows}
    return [
        f"class {texture_class!r} has no photograph in {manifest.version}. The "
        f"class list is the model's output order, so a class at zero reindexes "
        f"the labels rather than only thinning the data"
        for texture_class in classes
        if texture_class not in present
    ]


def class_images(
    manifest: Manifest, classes: Sequence[str]
) -> dict[str, list[str]]:
    """Group resolved image paths by class, in the order ``classes`` declares.

    Class order is the model's output order, so it comes from the config and
    never from the manifest's row order or from ``sorted()``. Only classes the
    manifest actually holds appear, so callers that need the full contract check
    :func:`check_class_coverage` first.
    """
    paths_by_class: dict[str, list[str]] = defaultdict(list)
    for row in manifest.rows:
        paths_by_class[row.texture_class].append(str(manifest.root / row.image))

    return {
        texture_class: sorted(paths_by_class[texture_class])
        for texture_class in classes
        if texture_class in paths_by_class
    }


def sample_ids_by_image(manifest: Manifest) -> dict[str, str]:
    """Map each resolved image path to the physical sample it photographs.

    Splits group on this rather than on a filename pattern: the identifier is a
    column the collector wrote, so a naming convention cannot silently regroup
    the dataset.
    """
    return {str(manifest.root / row.image): row.sample_id for row in manifest.rows}


def split_composition(
    splits: Mapping[str, Sequence[Mapping[str, object]]], manifest: Manifest
) -> dict[str, dict[str, Counter]]:
    """Count each split by class, site, device, setting, and source group.

    Every axis here is recorded and reported rather than held out, so the policy
    for any of them can be set from a count instead of a guess. Source group is
    the one axis that also carries a rule — see :data:`TRAIN_ONLY_SOURCE_GROUPS`
    — and reporting it is how that rule is checked by eye as well as by test.
    """
    rows_by_path = {
        str((manifest.root / row.image).resolve()): row for row in manifest.rows
    }

    composition: dict[str, dict[str, Counter]] = {}
    for split_name, entries in splits.items():
        axes: dict[str, Counter] = {
            "class": Counter(),
            "site": Counter(),
            "device": Counter(),
            "setting": Counter(),
            "source_group": Counter(),
        }
        for entry in entries:
            path = str(Path(str(entry["path"])).resolve())
            row = rows_by_path.get(path)
            if row is None:
                raise ValueError(
                    f"split '{split_name}' references {entry['path']!r}, which is "
                    f"not in manifest {manifest.version}"
                )
            axes["class"][row.texture_class] += 1
            axes["site"][row.site] += 1
            axes["device"][row.device] += 1
            axes["setting"][row.setting] += 1
            axes["source_group"][row.source_group or "(unrecorded)"] += 1
        composition[split_name] = axes

    return composition


#: Every axis :func:`split_composition` counts, in the order the report prints
#: them. A fold report narrows to two of them: at k folds over R repeats the
#: full set is fifty blocks of five lines, and the two axes that carry a rule
#: are the two worth reading that many times.
COMPOSITION_AXES = ("class", "site", "device", "setting", "source_group")
FOLD_COMPOSITION_AXES = ("class", "source_group")


def format_composition(
    composition: Mapping[str, Mapping[str, Counter]],
    axes: Sequence[str] = COMPOSITION_AXES,
    indent: str = "",
) -> str:
    """Render :func:`split_composition` as the text the validator prints."""
    lines = []
    for split_name, counters in composition.items():
        total = sum(counters["class"].values())
        lines.append(f"{indent}{split_name}: {total} photograph(s)")
        for axis in axes:
            counts = ", ".join(
                f"{value}={count}" for value, count in sorted(counters[axis].items())
            )
            lines.append(f"{indent}  {axis}: {counts or '(none)'}")
    return "\n".join(lines)


def verify_split_digest(split_manifest: Mapping[str, object], digest: str) -> None:
    """Fail unless a split manifest belongs to the manifest it is used with.

    Without this, "the model got worse" and "the dataset changed" are
    indistinguishable, which is the whole reason a dataset version is immutable.
    """
    recorded = split_manifest.get("manifest_digest")
    if not recorded:
        raise ValueError(
            "splits.json carries no manifest_digest, so it cannot be shown to "
            "belong to the current dataset. Delete it and regenerate the splits"
        )
    if recorded != digest:
        raise ValueError(
            f"splits.json manifest_digest {recorded!r} does not match the current "
            f"manifest digest {digest!r}. The dataset changed after the splits "
            "were generated; regenerate them or check out the matching version"
        )


def _decode(path: Path) -> str:
    """Decode the manifest, diagnosing the encoding a spreadsheet produces."""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise ManifestError(
            [
                f"{MANIFEST_FILENAME} is not UTF-8 encoded (byte 0x{raw[error.start]:02x} "
                f"at offset {error.start} is not valid UTF-8). A pt-BR spreadsheet "
                "commonly exports Latin-1; re-export it as UTF-8"
            ]
        ) from error
    # A spreadsheet export commonly leads with a byte-order mark, which would
    # otherwise become part of the first column's name.
    return text.lstrip("\ufeff")


def _reject_a_semicolon_export(header_line: str) -> None:
    """Diagnose a semicolon-delimited export before any column is examined.

    Reported as a delimiter fault rather than as absent columns, because the
    second message sends a collector looking for a column that is right there.
    """
    if ";" not in header_line:
        return
    fields = next(csv.reader([header_line]), [])
    if len(fields) >= len(REQUIRED_COLUMNS):
        return
    raise ManifestError(
        [
            f"{MANIFEST_FILENAME} looks semicolon-delimited: its header parses as "
            f"{len(fields)} column(s) with a comma delimiter. Re-export it with a "
            "comma delimiter"
        ]
    )


def _reject_a_broken_header(columns: Sequence[str]) -> None:
    """Fail on a header that makes row-level validation meaningless."""
    problems = []

    # `DictReader` keeps one value of a repeated column and discards the other,
    # so a header naming `texture_class` twice would silently pick a winner and
    # change the authoritative label with no error anywhere.
    repeated = sorted({c for c in columns if columns.count(c) > 1})
    if repeated:
        problems.append(
            f"column(s) named more than once: {', '.join(repeated)}. A repeated "
            "column silently discards one of its values"
        )

    forbidden = [column for column in columns if column in FORBIDDEN_COLUMNS]
    if forbidden:
        problems.append(
            f"column(s) not accepted by this schema: {', '.join(sorted(forbidden))}. "
            "No granulometric value and no laboratory reference enters this process"
        )

    absent = [column for column in REQUIRED_COLUMNS if column not in columns]
    if absent:
        problems.append(f"required column(s) not present: {', '.join(absent)}")

    if problems:
        raise ManifestError(problems)


def _parse_rows(
    reader: csv.DictReader,
    root: Path,
    classes: Sequence[str],
    columns: Sequence[str],
    *,
    check_files: bool,
) -> tuple[list[ManifestRow], list[str]]:
    """Validate every row and build it, collecting problems as it goes."""
    accepted_classes = ", ".join(classes)
    accepted_settings = ", ".join(VALID_SETTINGS)
    metric_columns = [column for column in METRIC_COLUMNS if column in columns]

    rows: list[ManifestRow] = []
    problems: list[str] = []
    images_seen: dict[str, int] = {}

    for index, raw in enumerate(reader):
        number = index + 1 + _HEADER_ROW_COUNT
        values = {
            column: (raw.get(column) or "").strip() for column in REQUIRED_COLUMNS
        }

        blank = [column for column in REQUIRED_COLUMNS if not values[column]]
        if blank:
            problems.append(f"row {number}: blank required value(s): {', '.join(blank)}")
            continue

        if values["texture_class"] not in classes:
            problems.append(
                f"row {number}: texture_class {values['texture_class']!r} is not a "
                f"declared class. Accepted: {accepted_classes}"
            )
        if values["setting"] not in VALID_SETTINGS:
            problems.append(
                f"row {number}: setting {values['setting']!r} is not accepted. "
                f"Accepted: {accepted_settings}"
            )
        if not _is_iso_date(values["captured_at"]) and values["captured_at"] != UNKNOWN:
            problems.append(
                f"row {number}: captured_at {values['captured_at']!r} is neither an "
                f"ISO 8601 date (YYYY-MM-DD) nor {UNKNOWN!r}"
            )

        image = _normalized_image(values["image"])
        image_problem = _image_path_problem(image, values["image"], root, number)
        if image_problem:
            problems.append(image_problem)
        else:
            # Keyed on the resolved, case-normalized path rather than on the
            # spelling: `./images/x.jpg` and `images/x.jpg` are one file, and on
            # Windows so are `x.jpg` and `X.JPG`. Comparing the raw strings let
            # both rows through, after which one photograph was silently counted
            # under another sample's group — or, with the two casings, the same
            # file joined two groups and could reach train and test at once.
            key = _identity(root, image)
            if key in images_seen:
                problems.append(
                    f"row {number}: image {image!r} is already claimed by row "
                    f"{images_seen[key]}"
                )
            else:
                images_seen[key] = number
                if check_files and not (root / image).is_file():
                    problems.append(f"row {number}: image not found on disk: {image}")

        metrics, metric_problems = _parse_metrics(raw, metric_columns, number)
        problems.extend(metric_problems)

        provenance, provenance_problems = _parse_provenance(raw, number)
        problems.extend(provenance_problems)

        rows.append(
            ManifestRow(
                sample_id=values["sample_id"],
                texture_class=values["texture_class"],
                image=image,
                setting=values["setting"],
                site=values["site"],
                device=values["device"],
                captured_at=values["captured_at"],
                quality_verdict=(raw.get(QUALITY_VERDICT_COLUMN) or "").strip(),
                quality_flags=_parse_flags(raw.get(QUALITY_FLAGS_COLUMN)),
                metrics=metrics,
                **provenance,
            )
        )

    if not rows and not problems:
        problems.append(f"{MANIFEST_FILENAME} declares no rows")

    return rows, problems


def _cross_row_problems(rows: Sequence[ManifestRow]) -> list[str]:
    """Report faults only visible across rows."""
    classes_by_sample: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        classes_by_sample[row.sample_id].add(row.texture_class)

    return [
        f"sample_id {sample_id!r} appears under {len(found)} classes "
        f"({', '.join(sorted(found))}). One physical sample carries one class, so "
        "this is a labelling error rather than a naming collision"
        for sample_id, found in sorted(classes_by_sample.items())
        if len(found) > 1
    ]


def _normalized_image(value: str) -> str:
    """Accept the separator a collector's operating system produced."""
    return value.replace("\\", "/")


def _identity(root: Path, image: str) -> str:
    """The key two rows share when they name one file.

    ``normcase`` is what makes this correct on both platforms: on Windows it
    folds case and separators, and on POSIX it is the identity function, so a
    case-sensitive filesystem keeps two spellings distinct.

    Windows case folding of a path that does not exist is the one gap:
    ``resolve()`` cannot canonicalise a missing file's casing, so ``x.jpg`` and
    ``X.JPG`` stay distinct until the files are there. Both command-line tools
    read with ``check_files=True``, where the files exist by the time this runs.
    """
    return os.path.normcase(str((root / image).resolve()))


def _image_path_problem(
    image: str, declared: str, root: Path, number: int
) -> str | None:
    """Return why an image path is unusable, or ``None`` when it is fine."""
    if PurePosixPath(declared).is_absolute() or PureWindowsPath(declared).is_absolute():
        return (
            f"row {number}: image {declared!r} must be relative to the dataset "
            "version root, so the dataset stays movable"
        )
    # `C:images/a.jpg` is neither absolute nor relative-to-root by pathlib's
    # reckoning — it is relative to the drive's current directory. It names one
    # file on Windows and a directory called `C:images` on POSIX, so the same
    # manifest would describe two different datasets.
    if PureWindowsPath(declared).drive:
        return (
            f"row {number}: image {declared!r} carries a drive letter, which names "
            "a different file on Windows than on POSIX"
        )
    if not (root / image).resolve().is_relative_to(root.resolve()):
        return (
            f"row {number}: image {declared!r} resolves outside the dataset version "
            "root"
        )
    if (root / image).resolve().is_relative_to(
        (root / QUARANTINE_DIRNAME).resolve()
    ):
        return (
            f"row {number}: image {declared!r} is inside {QUARANTINE_DIRNAME}/, which "
            "holds what admission refused. A refused image cannot be declared"
        )
    return None


def _parse_metrics(
    raw: Mapping[str, str], metric_columns: Sequence[str], number: int
) -> tuple[dict[str, float], list[str]]:
    """Read the recorded quality metrics, reporting a value that is not a number."""
    metrics: dict[str, float] = {}
    problems: list[str] = []
    for column in metric_columns:
        value = (raw.get(column) or "").strip()
        if not value:
            continue
        try:
            metrics[column] = float(value)
        except ValueError:
            problems.append(f"row {number}: {column} {value!r} is not a number")
    return metrics, problems


def _parse_provenance(
    raw: Mapping[str, str], number: int
) -> tuple[dict[str, object], list[str]]:
    """Read the provenance columns, which a hand-authored manifest omits.

    Absent, they are empty and nothing downstream restricts the row. Present,
    they are checked: a `source_group` outside the declared set would silently
    exempt a population from the train-only rule, which is the one thing these
    columns exist to enforce.
    """
    values = {column: (raw.get(column) or "").strip() for column in PROVENANCE_COLUMNS}
    if not any(values.values()):
        return {}, []

    problems: list[str] = []
    if values["source_format"] and values["source_format"] not in VALID_SOURCE_FORMATS:
        problems.append(
            f"row {number}: source_format {values['source_format']!r} is not "
            f"accepted. Accepted: {', '.join(VALID_SOURCE_FORMATS)}"
        )
    if values["source_group"] and values["source_group"] not in VALID_SOURCE_GROUPS:
        problems.append(
            f"row {number}: source_group {values['source_group']!r} is not "
            f"accepted. Accepted: {', '.join(VALID_SOURCE_GROUPS)}"
        )
    if (
        values["sample_id_source"]
        and values["sample_id_source"] not in VALID_SAMPLE_ID_SOURCES
    ):
        problems.append(
            f"row {number}: sample_id_source {values['sample_id_source']!r} is not "
            f"accepted. Accepted: {', '.join(VALID_SAMPLE_ID_SOURCES)}"
        )

    sizes: dict[str, object] = {}
    for column in ("source_width", "source_height"):
        text = values[column]
        if not text:
            sizes[column] = 0
            continue
        try:
            size = int(text)
        except ValueError:
            problems.append(f"row {number}: {column} {text!r} is not a whole number")
            sizes[column] = 0
            continue
        if size <= 0:
            problems.append(f"row {number}: {column} must be positive, got {size}")
        sizes[column] = size

    return (
        {
            "source_format": values["source_format"],
            "source_group": values["source_group"],
            "sample_id_source": values["sample_id_source"],
            **sizes,
        },
        problems,
    )


def _parse_flags(value: str | None) -> tuple[str, ...]:
    """Split the recorded advisory flags."""
    if not value:
        return ()
    return tuple(flag.strip() for flag in value.split(FLAG_SEPARATOR) if flag.strip())


def _format_metric(value: float | None) -> str:
    """Render a metric for a file a person also reads.

    An integral value is written without a decimal part so ``roi_side_px`` reads
    as ``600`` rather than ``600.0``; both round-trip through :func:`float`.
    """
    if value is None:
        return ""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


def _is_iso_date(value: str) -> bool:
    """Whether ``value`` is an ISO 8601 calendar date in the documented form."""
    if not _ISO_DATE_PATTERN.match(value):
        return False
    try:
        date.fromisoformat(value)
    except ValueError:
        return False
    return True
