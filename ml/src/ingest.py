"""Turn the delivered sample archive into an immutable dataset version.

The archive is what the laboratory handed over: English class folders, original
filenames, and three capture populations in two containers, one of which neither
pipeline decodes. It is source material and nothing in the pipeline reads it
except this module. What experiments name is the version this module writes.

The decisions here are recorded in
``docs/specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md``. Three
are load-bearing and are asserted by tests rather than left to the reader:

* the class comes from the folder **by name**, never by the folder's number,
  because the folders run in granulometric order and ``config.yaml`` does not;
* HEIC becomes PNG and JPEG is copied byte for byte, so no file gains a second
  generation of compression on the band that carries the signal;
* a column the archive cannot supply is written ``unknown``, never guessed.
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass, replace
from datetime import datetime
from pathlib import Path
from typing import Iterator, Sequence

from PIL import Image, ExifTags
from pillow_heif import register_heif_opener

from .dataset import sample_id_from_filename
from .manifest import (
    UNKNOWN,
    ManifestRow,
    dataset_root,
    validate_version_name,
    write_manifest,
)

register_heif_opener()

#: The archive's folder names, mapped to the classes ``ml/config.yaml`` declares.
#:
#: By name and never by index. The folders are numbered in granulometric order —
#: sandy through very clayey — while the configured class list runs Arenosa,
#: Media, Siltosa, Muito Argilosa, Argilosa. Pairing folder number to class index
#: mislabels four of the five and raises no error while doing it.
ARCHIVE_CLASS_BY_FOLDER = {
    "1 Sandy": "Arenosa",
    "2 Silty": "Siltosa",
    "3 Medium": "Media",
    "4 Clayey": "Argilosa",
    "5 Very Clayey": "Muito Argilosa",
}

#: Every archive photograph is soil in a Petri dish on a pale background.
ARCHIVE_SETTING = "dish"

#: Filenames a camera writes on its own. They identify the photograph and
#: declare nothing about what was photographed, so a sample identity taken from
#: one would be a different sample per shot — which is the shape that puts two
#: photographs of one dish into two different splits.
CAMERA_DEFAULT_NAME = re.compile(r"^(?:IMG|DSC|DSCN|PXL|PHOTO)[_-]?\d+$", re.IGNORECASE)

#: Photographs of one sample are taken in a burst; the dish is swapped between
#: bursts and swapping takes time. Measured over the delivered archive's 129
#: HEIC files: gaps inside a burst run 2 to 23 seconds, gaps between bursts
#: never fall below 100, and nothing at all lies in between. A cut anywhere from
#: 30 to 60 seconds yields the same 63 groups, which is what a well-separated
#: threshold looks like; 60 sits in the empty band rather than on its edge.
#:
#: Two independent checks corroborate the grouping and are enforced below: no
#: burst may span two texture classes, and a photograph with no capture time
#: cannot be grouped at all and is refused rather than guessed at.
BURST_GAP_SECONDS = 60

#: The prefix of a derived sample identity, so a reader can see at a glance that
#: the group came from a clock and not from a collector.
BURST_ID_PREFIX = "burst"

#: Where converted and copied images land inside the version.
IMAGES_DIRNAME = "images"

#: EXIF tag numbers, resolved once rather than looked up by name per file.
_TAG_MODEL = 0x0110
_TAG_DATETIME = 0x0132
_TAG_DATETIME_ORIGINAL = 0x9003

_EXIF_DATETIME_FORMAT = "%Y:%m:%d %H:%M:%S"


class ArchiveError(ValueError):
    """Every problem found in one archive, reported together.

    Aggregated for the same reason :class:`~src.manifest.ManifestError` is: the
    reader is fixing a delivery, and one pass over a list of faults is the
    difference between one correction cycle and many.
    """

    def __init__(self, problems: Sequence[str]) -> None:
        self.problems = tuple(problems)
        count = len(self.problems)
        noun = "problem" if count == 1 else "problems"
        detail = "".join(f"\n  - {problem}" for problem in self.problems)
        super().__init__(f"archive rejected ({count} {noun}):{detail}")


@dataclass(frozen=True)
class SourceImage:
    """One archive photograph, with everything the manifest needs about it."""

    path: Path
    texture_class: str
    sample_id: str
    source_format: str
    source_group: str
    width: int
    height: int
    device: str
    captured_at: str
    sample_id_source: str
    captured_at_exact: datetime | None

    @property
    def target_name(self) -> str:
        """The filename this image takes inside the version.

        HEIC changes suffix because its bytes change; JPEG keeps its own name
        because its bytes do not, which makes a copy verifiable by comparison.
        """
        if self.source_format == "heic":
            return self.path.stem + ".png"
        return self.path.name


@dataclass(frozen=True)
class IngestReport:
    """What one ingestion run did, in numbers a caller can assert on."""

    version: str
    root: Path
    converted: int
    copied: int
    reused: int
    rows: int
    samples: int
    derived_samples: int
    group_mix: dict[str, dict[str, int]]

    def render(self) -> str:
        lines = [
            f"{self.version}: {self.rows} photograph(s) of {self.samples} sample(s)",
            f"  converted to PNG: {self.converted}",
            f"  copied unchanged: {self.copied}",
            f"  already present, reused: {self.reused}",
            f"  sample identity derived from the capture burst: "
            f"{self.derived_samples} of {self.samples}",
            "  source group by class:",
        ]
        for texture_class in sorted(self.group_mix):
            counts = self.group_mix[texture_class]
            rendered = ", ".join(f"{group}={counts[group]}" for group in sorted(counts))
            lines.append(f"    {texture_class}: {rendered}")
        return "\n".join(lines)


def _class_dirname(texture_class: str) -> str:
    """The per-class directory inside ``images/``.

    Images are filed by class so two classes cannot collide on a filename, and
    the spelling matches the folder convention ``scan_dataset`` already uses.
    """
    return texture_class.replace(" ", "_")


def _device_slug(model: str) -> str:
    return "-".join(model.strip().lower().split())


def _exif_of(image: Image.Image) -> dict[int, object]:
    try:
        return dict(image.getexif())
    except Exception:  # pragma: no cover - a container without EXIF support
        return {}


def _captured_at_exact(exif: dict[int, object]) -> datetime | None:
    """The full capture instant, which is what bursts are computed from."""
    for tag in (_TAG_DATETIME_ORIGINAL, _TAG_DATETIME):
        raw = exif.get(tag)
        if not raw:
            continue
        try:
            return datetime.strptime(str(raw), _EXIF_DATETIME_FORMAT)
        except ValueError:
            continue
    return None


def _captured_at(exif: dict[int, object]) -> str:
    """The calendar date the photograph was taken, or the unknown literal.

    Group B carries no EXIF at all and shares no laboratory batch number with
    the dated groups, so it cannot inherit a date from them; its filesystem
    timestamps are a single bulk-copy instant. There is nothing to read, so
    nothing is written.
    """
    for tag in (_TAG_DATETIME_ORIGINAL, _TAG_DATETIME):
        raw = exif.get(tag)
        if not raw:
            continue
        try:
            return datetime.strptime(str(raw), _EXIF_DATETIME_FORMAT).date().isoformat()
        except ValueError:
            continue
    return UNKNOWN


def _source_group(container_format: str, exif: dict[int, object]) -> str:
    """Which capture population this photograph belongs to.

    Read from evidence, not from the filename. The delivered archive happens to
    spell one JPEG population ``.JPEG`` and the other ``.jpeg``, but case is not
    a property a filesystem is obliged to preserve, and what actually separates
    them is that one kept its EXIF and the other was stripped in transport.
    """
    if container_format == "heic":
        return "C"
    return "A" if exif.get(_TAG_MODEL) else "B"


def _read(path: Path, texture_class: str) -> SourceImage:
    with Image.open(path) as image:
        image.load()
        container = (image.format or "").lower()
        width, height = image.size
        exif = _exif_of(image)

    if container in ("heif", "heic"):
        source_format = "heic"
    elif container in ("jpeg", "jpg"):
        source_format = "jpeg"
    elif container == "png":
        source_format = "png"
    else:
        raise ValueError(f"unsupported container {container!r}")

    model = str(exif.get(_TAG_MODEL) or "").strip()
    declared = sample_id_from_filename(str(path))
    names_a_sample = not CAMERA_DEFAULT_NAME.match(declared)
    return SourceImage(
        path=path,
        texture_class=texture_class,
        sample_id=declared if names_a_sample else "",
        source_format=source_format,
        source_group=_source_group(source_format, exif),
        width=width,
        height=height,
        device=_device_slug(model) if model else UNKNOWN,
        captured_at=_captured_at(exif),
        sample_id_source="filename" if names_a_sample else "",
        captured_at_exact=_captured_at_exact(exif),
    )


def _assign_burst_sample_ids(
    images: Sequence[SourceImage],
) -> tuple[list[SourceImage], list[str]]:
    """Give every camera-named photograph the identity of its capture burst.

    A photograph whose filename declares a sample keeps it untouched. The rest
    are ordered by capture time and cut wherever the gap exceeds
    :data:`BURST_GAP_SECONDS`. Two faults are refusals rather than warnings: a
    photograph with no capture time cannot be placed in a burst, and a burst
    spanning two texture classes means the gap threshold does not separate what
    it is assumed to separate. Both would produce a grouping that looks fine and
    leaks.
    """
    declared = [image for image in images if image.sample_id]
    undeclared = [image for image in images if not image.sample_id]
    if not undeclared:
        return list(images), []

    problems = [
        f"{image.path.name}: the filename declares no sample and the photograph "
        f"carries no capture time, so it cannot be grouped. Every photograph of "
        f"one physical sample has to stay in one split, and nothing here says "
        f"which sample this is"
        for image in undeclared
        if image.captured_at_exact is None
    ]
    if problems:
        return list(images), problems

    ordered = sorted(undeclared, key=lambda image: (image.captured_at_exact, image.path.name))
    bursts: list[list[SourceImage]] = [[ordered[0]]]
    for previous, current in zip(ordered, ordered[1:]):
        gap = (current.captured_at_exact - previous.captured_at_exact).total_seconds()
        if gap > BURST_GAP_SECONDS:
            bursts.append([])
        bursts[-1].append(current)

    grouped: list[SourceImage] = []
    for burst in bursts:
        classes = {image.texture_class for image in burst}
        if len(classes) > 1:
            problems.append(
                f"a capture burst starting at {burst[0].captured_at_exact:%Y-%m-%d %H:%M:%S} "
                f"spans {', '.join(sorted(classes))}. A burst is assumed to be one "
                f"physical sample, and one sample has one class, so the "
                f"{BURST_GAP_SECONDS}s threshold does not separate what it is "
                f"assumed to separate here"
            )
            continue
        sample_id = f"{BURST_ID_PREFIX}-{burst[0].captured_at_exact:%Y%m%d-%H%M%S}"
        grouped.extend(
            replace(image, sample_id=sample_id, sample_id_source="capture-burst")
            for image in burst
        )

    if problems:
        return list(images), problems

    return sorted(declared + grouped, key=lambda image: str(image.path)), []


def _candidate_files(source: Path) -> Iterator[tuple[str, Path]]:
    for folder in sorted(child.name for child in source.iterdir() if child.is_dir()):
        for path in sorted((source / folder).iterdir(), key=lambda p: p.name):
            if path.is_file():
                yield folder, path


def scan_archive(source: str | Path) -> list[SourceImage]:
    """Read every photograph in ``source``, or refuse the archive.

    Refuses rather than skips, in both directions: a folder the map does not
    name and a file that will not decode are both faults in the delivery, and
    both are silent if ingestion simply passes them by. Silently ingesting the
    readable part is the failure this whole module exists to close.
    """
    source = Path(source)
    if not source.is_dir():
        raise ArchiveError([f"archive directory not found: {source}"])

    problems: list[str] = []
    images: list[SourceImage] = []

    folders = sorted(child.name for child in source.iterdir() if child.is_dir())
    unmapped = [folder for folder in folders if folder not in ARCHIVE_CLASS_BY_FOLDER]
    for folder in unmapped:
        problems.append(
            f"folder {folder!r} is not one of the archive's class folders "
            f"({', '.join(ARCHIVE_CLASS_BY_FOLDER)}). A folder is a class, so an "
            f"unnamed one is either a new class or a mistake, and both need a "
            f"decision rather than a skip"
        )

    for folder, path in _candidate_files(source):
        if folder in unmapped:
            continue
        try:
            images.append(_read(path, ARCHIVE_CLASS_BY_FOLDER[folder]))
        except Exception as error:
            problems.append(f"{folder}/{path.name}: cannot be read ({error})")

    if problems:
        raise ArchiveError(problems)

    images, problems = _assign_burst_sample_ids(images)
    if problems:
        raise ArchiveError(problems)
    return images


def _already_written(target: Path, image: SourceImage) -> bool:
    """Whether ``target`` is already this photograph, verified rather than assumed.

    A resumed run must not trust a filename. A copied JPEG is compared byte for
    byte against its source; a converted PNG is checked for the dimensions the
    source declares, which is what a truncated write fails.
    """
    if not target.is_file():
        return False
    if image.source_format != "heic":
        return target.read_bytes() == image.path.read_bytes()
    try:
        with Image.open(target) as written:
            written.load()
            return written.size == (image.width, image.height)
    except Exception:
        return False


def ingest_archive(
    source: str | Path,
    root: str | Path,
    *,
    classes: Sequence[str],
    skip_existing: bool = False,
) -> IngestReport:
    """Write ``source`` into the dataset version at ``root``.

    Deterministic: the file order is sorted and nothing is sampled, so two runs
    over one archive produce byte-identical manifests.

    Args:
        skip_existing: Do not rewrite a target file that is already this
            photograph, verified by comparison rather than by name. Converting
            this archive writes 1.3 GB, so an interrupted run has to be
            resumable; the verification is what keeps that from becoming a cache
            that can drift.
    """
    source = Path(source)
    root = Path(root)
    validate_version_name(root.name)

    images = scan_archive(source)
    unknown_classes = sorted(
        {image.texture_class for image in images} - set(classes)
    )
    if unknown_classes:
        raise ArchiveError(
            [
                f"class {name!r} is not declared in the configured class list "
                f"({', '.join(classes)})"
                for name in unknown_classes
            ]
        )

    rows: list[ManifestRow] = []
    written: dict[str, Path] = {}
    problems: list[str] = []
    converted = copied = reused = 0

    for image in images:
        relative = f"{IMAGES_DIRNAME}/{_class_dirname(image.texture_class)}/{image.target_name}"
        if relative in written:
            problems.append(
                f"{image.path.name} and {written[relative].name} both claim "
                f"{relative}; two photographs of one class cannot share a name"
            )
            continue
        written[relative] = image.path

        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if skip_existing and _already_written(target, image):
            reused += 1
        elif image.source_format == "heic":
            with Image.open(image.path) as decoded:
                decoded.convert("RGB").save(target, format="PNG")
            converted += 1
        else:
            shutil.copyfile(image.path, target)
            copied += 1

        rows.append(
            ManifestRow(
                sample_id=image.sample_id,
                texture_class=image.texture_class,
                image=relative,
                setting=ARCHIVE_SETTING,
                # The archive's GPS is one fifty-metre circle: the bench the
                # photographs were taken on, not where any soil was sampled.
                # Writing it here would assert an origin the rows do not share.
                site=UNKNOWN,
                device=image.device,
                captured_at=image.captured_at,
                source_format=image.source_format,
                source_group=image.source_group,
                source_width=image.width,
                source_height=image.height,
                sample_id_source=image.sample_id_source,
            )
        )

    if problems:
        raise ArchiveError(problems)

    write_manifest(root, rows)

    group_mix: dict[str, dict[str, int]] = {}
    for row in rows:
        group_mix.setdefault(row.texture_class, {}).setdefault(row.source_group, 0)
        group_mix[row.texture_class][row.source_group] += 1

    return IngestReport(
        version=root.name,
        root=root,
        converted=converted,
        copied=copied,
        reused=reused,
        rows=len(rows),
        samples=len({row.sample_id for row in rows}),
        derived_samples=len(
            {row.sample_id for row in rows if row.sample_id_source == "capture-burst"}
        ),
        group_mix=group_mix,
    )


def version_root(datasets_dir: str | Path, version: str) -> Path:
    """The version directory ingestion writes to, validated."""
    return dataset_root(datasets_dir, version)
