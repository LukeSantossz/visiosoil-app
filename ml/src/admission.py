"""Dataset admission: the SPEC 0030 criteria deciding what enters a version.

An image whose verdict is ``blocking`` does not enter the dataset. An
``advisory`` image does, with its failing criteria recorded, because a marginal
photograph is representative of real conditions and excluding it would curate the
dataset into the narrow subpopulation ADR 0009 warns about.

The thresholds are provisional, so admission records the measured metrics for
every admitted image rather than only the verdict. When the thresholds are
recalibrated the decision can be recomputed from the manifest without re-reading
a single file.

Specified by ``docs/specs/0033-dataset-protocol-manifest-and-splits.md``.
"""

import csv
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Sequence

from PIL import Image

from .image_quality import (
    DEFAULT_CRITERIA,
    CriterionFailure,
    ImageQualityCriteria,
    ImageQualityMetrics,
    ImageQualityReport,
    Verdict,
    analyze,
)
from .manifest import (
    METRIC_COLUMNS,
    QUARANTINE_DIRNAME,
    REJECTED_FILENAME,
    Manifest,
    ManifestRow,
)

#: The refusal report a collector reads to know what to retake.
REFUSAL_COLUMNS = ("image", "verdict", "reason")


@dataclass(frozen=True)
class RefusedImage:
    """One candidate that did not enter the dataset, and why."""

    image: str
    verdict: str
    reason: str


@dataclass(frozen=True)
class AdmissionResult:
    """The manifest rows that were admitted, and the candidates that were not."""

    admitted: tuple[ManifestRow, ...]
    refused: tuple[RefusedImage, ...]


def admit(
    manifest: Manifest, criteria: ImageQualityCriteria = DEFAULT_CRITERIA
) -> AdmissionResult:
    """Run the quality criteria over every row and decide what enters."""
    admitted: list[ManifestRow] = []
    refused: list[RefusedImage] = []

    for row in manifest.rows:
        report = _analyze_file(manifest.root / row.image, criteria)

        if report.verdict is Verdict.UNVALIDATED:
            # SPEC 0030 requires an analyzer failure never to block a capture.
            # Admission is the other context: a row with no recorded metrics
            # breaks the guarantee that a threshold change can be recomputed
            # from the manifest, so the image is refused with its cause rather
            # than admitted blind.
            refused.append(
                RefusedImage(
                    image=row.image,
                    verdict=Verdict.UNVALIDATED.value,
                    reason=report.unvalidated_reason
                    or "the analyzer could not measure this image",
                )
            )
            continue

        if report.verdict is Verdict.BLOCKING:
            refused.append(
                RefusedImage(
                    image=row.image,
                    verdict=Verdict.BLOCKING.value,
                    reason=_blocking_reason(report.failures),
                )
            )
            continue

        admitted.append(
            replace(
                row,
                quality_verdict=report.verdict.value,
                quality_flags=tuple(
                    failure.criterion.value for failure in report.failures
                ),
                metrics=_metrics_of(report.metrics),
            )
        )

    return AdmissionResult(admitted=tuple(admitted), refused=tuple(refused))


def write_refusal_report(
    root: str | Path, refused: Sequence[RefusedImage]
) -> Path:
    """Write the refusal report, header included even when nothing was refused.

    Always written, so its absence means admission never ran rather than that
    every candidate passed.
    """
    path = Path(root) / REJECTED_FILENAME
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(REFUSAL_COLUMNS)
        for refusal in refused:
            writer.writerow([refusal.image, refusal.verdict, refusal.reason])
    return path


def quarantine_refused(
    root: str | Path, refused: Sequence[RefusedImage]
) -> list[Path]:
    """Move every refused image out of the dataset and into quarantine.

    A refused row leaves the manifest, so leaving its file where it was would
    make the next validation report it as an orphan and refuse the very version
    admission had just produced — the documented workflow would contradict
    itself. Moved rather than deleted, because the image is the evidence for the
    refusal and a retake is judged against it.

    The path under quarantine mirrors the path the row declared, so two
    subdirectories holding one filename cannot overwrite each other.

    Every move is checked before any move happens. The caller rewrites the
    manifest around this call, so failing halfway would drop rows whose files had
    not moved — the orphan state quarantine exists to avoid.

    Raises:
        FileNotFoundError: If any refused image is not where the manifest said.
        FileExistsError: If quarantine already holds that path.
    """
    root = Path(root)
    planned = [(root / r.image, root / QUARANTINE_DIRNAME / r.image, r) for r in refused]

    for source, target, refusal in planned:
        if not source.is_file():
            raise FileNotFoundError(
                f"refused image {refusal.image} is no longer at {source}: nothing "
                "was quarantined, and the manifest is untouched"
            )
        if target.exists():
            raise FileExistsError(
                f"quarantine already holds {refusal.image}: it is the record of an "
                "earlier refusal, not scratch space. Move or remove it first; "
                "nothing was quarantined"
            )

    moved: list[Path] = []
    for source, target, _ in planned:
        target.parent.mkdir(parents=True, exist_ok=True)
        source.replace(target)
        moved.append(target)
    return moved


def _analyze_file(path: Path, criteria: ImageQualityCriteria) -> ImageQualityReport:
    """Analyze one file, converting an unreadable image into a verdict.

    Broad by intent: a corrupt file, an unsupported format and a truncated
    download all mean the same thing here, and every one of them must become an
    ``UNVALIDATED`` verdict with its cause attached rather than an exception that
    abandons the rest of the batch.
    """
    try:
        with Image.open(path) as image:
            image.load()
            return analyze(image, criteria)
    except Exception as error:  # noqa: BLE001 - converted to a verdict, not swallowed
        return ImageQualityReport(
            verdict=Verdict.UNVALIDATED,
            metrics=None,
            failures=(),
            unvalidated_reason=f"{type(error).__name__}: {error}",
        )


def _blocking_reason(failures: Sequence[CriterionFailure]) -> str:
    """Name every blocking failure, with what it measured against.

    Advisory failures are left out: they are recorded as flags on an admitted
    row, so repeating them in a refusal would mix the reason with the record.
    """
    return "; ".join(
        f"{failure.criterion.value} measured {failure.measured:.4g} against "
        f"threshold {failure.threshold:.4g}"
        for failure in failures
        if failure.severity is Verdict.BLOCKING
    )


def _metrics_of(metrics: ImageQualityMetrics | None) -> dict[str, float]:
    """Extract the seven recorded metrics in schema order."""
    if metrics is None:
        return {}
    return {column: float(getattr(metrics, column)) for column in METRIC_COLUMNS}
