"""Is the capture population recoverable from the patches? (SPEC 0055)

The archive is three capture populations out of one device, and one of them —
the transported population `B` — lost its EXIF and was re-encoded with a
luminance quantization table three to four times coarser in the band soil
texture lives in. It is also 69 % Argilosa and 0 % Muito Argilosa, so its
encoding signature is **correlated with the label**. If a model can recover the
population from the same patches it classifies texture from, the E0 verdict may
be reading a compression artefact rather than soil, and nothing in the gate
would say so.

This module asks that question with the cheapest arm and the least new code:
the descriptor featuriser and `arms.probe.probe_fold`, unchanged, with the
**label** swapped from texture class to capture population.

Two things about it are deliberate and are not the protocol's defaults.

**It draws its own partition.** All twenty of population `B`'s sample groups are
train-only under SPEC 0040 D6, so `B` is in no E0 fold's test side and a probe
scored on those folds could never be scored on the population it exists to ask
about. It would answer "can `A` be told from `C`", which is not the question.
This is legitimate because the probe is a diagnostic about the data and not an
arm: it is reported outside `evaluation.contrasts` and shares no correction
family with anything.

**Its reading rule is fixed before it runs**, in :func:`probe_verdict`. A
diagnostic whose threshold is chosen after the number is not a diagnostic.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Collection, Mapping, Sequence

from .arms.descriptors import descriptor_features
from .dataset import (
    create_folds,
    drop_refused_photographs,
    photograph_scale_of,
    sample_ids_by_image,
)
from .manifest import Manifest
from .stats import wilson_interval

#: The arm name the probe's artifacts are filed under. Not in
#: `evaluation.contrasts` and never contrasted with an arm: it answers a
#: question about the data, and putting it in that family would spend the
#: correction budget of the family that answers the gate's question.
POPULATION_PROBE_ARM = "population_probe"

#: The same features the descriptor arm computes, over the same patches. Bound
#: here by name so a test can assert the identity rather than the resemblance —
#: a probe over *different* features would answer a question about those
#: features instead of about what the arms actually see.
probe_featuriser = descriptor_features

#: The confidence the interval is reported at, matching `evaluate.py`'s.
INTERVAL_CONFIDENCE = 0.95


def population_images(
    manifest: Manifest, refused: Collection[str], *, classes: Collection[str]
) -> dict[str, list[str]]:
    """Resolved image paths grouped by capture population.

    The shape `create_folds` takes, so the probe's partition is drawn by the
    same function the protocol's is — stratified on whatever the keys are, which
    here is the population rather than the texture class.

    Args:
        manifest: The dataset version's manifest.
        refused: Paths the patch grid cannot cut. Excluded, because the probe
            reads the patches the arms see and the arms never see these.
        classes: The classes the model emits, which is `cfg["classes"]` and not
            :data:`manifest.ARCHIVE_CLASSES`. Required rather than defaulted:
            the archive holds five groups and the model emits four (ADR 0016),
            `create_folds_for_config` partitions the four, and a probe over the
            five would score sample groups no arm ever sees — answering a
            question about a larger set than the one it exists to describe. The
            two lists are the standing confusion in this codebase, so the caller
            names which one it means.

    Raises:
        ValueError: If any row carries no ``source_group``. Inferring one from
            the pixel dimensions is how a diagnostic becomes a guess about the
            very thing it is diagnosing, so it is refused instead. Checked over
            the whole manifest and not only over ``classes``: ingest writes the
            column for every row and `train_only_sample_ids` reads it for the
            arms too, so a blank one is a broken ingest rather than a row this
            probe happens not to want.
        ValueError: If one ``sample_id`` carries two ``source_group`` values.
            `create_folds` groups on the key it is given, so a spanning sample
            would become two fold groups for one physical sample and its
            photographs could land on opposite sides of a split — the leak the
            protocol exists to prevent.
        ValueError: If the patch grid's refusals empty a population entirely.
            A population that never reaches a fold is not reported as ``null``
            by :func:`population_recall`; it is absent from ``populations`` and
            the report reads as a complete answer over whichever populations
            survived. The verdict is about which populations are separable, so
            losing one silently is losing the question.
    """
    unrecorded = [row.image for row in manifest.rows if not row.source_group]
    if unrecorded:
        raise ValueError(
            f"{len(unrecorded)} row(s) of {manifest.version} carry no "
            f"source_group, so their capture population is unknown; the first "
            f"is {unrecorded[0]}. The probe reads that column and never infers "
            f"it"
        )

    emitted = set(classes)
    probed = [row for row in manifest.rows if row.texture_class in emitted]

    # Before any filtering, because both of the guards below are about what the
    # filtering must not be allowed to hide.
    spanning: dict[str, set[str]] = {}
    for row in probed:
        spanning.setdefault(row.sample_id, set()).add(row.source_group)
    conflicted = sorted(
        sample for sample, groups in spanning.items() if len(groups) > 1
    )
    if conflicted:
        raise ValueError(
            f"{len(conflicted)} sample group(s) of {manifest.version} span two "
            f"capture populations, so grouping on sample_id would put one "
            f"physical sample on both sides of a split; the first is "
            f"{conflicted[0]} in "
            f"{', '.join(sorted(spanning[conflicted[0]]))}"
        )
    expected = {row.source_group for row in probed}

    excluded = set(refused)
    grouped: dict[str, list[str]] = {}
    for row in probed:
        path = str(manifest.root / row.image)
        if path in excluded:
            continue
        grouped.setdefault(row.source_group, []).append(path)

    emptied = sorted(expected - set(grouped))
    if emptied:
        raise ValueError(
            f"the patch grid refuses every photograph of capture population(s) "
            f"{', '.join(emptied)}, so they would be absent from the report "
            f"rather than reported as unscored. A probe that quietly drops a "
            f"population is not answering the question it was asked"
        )

    return {population: sorted(paths) for population, paths in sorted(grouped.items())}


def probe_refusals(
    cfg: Mapping, manifest: Manifest, classes: Collection[str]
) -> dict[str, str]:
    """The photographs the patch grid refuses, over the set the arms train on.

    The same call `create_folds_for_config` makes, including the scale: read
    from the manifest in hand rather than through the configured version, so a
    probe of a version the config does not name is measured against its own
    dish-rim readings instead of another version's.
    """
    images = population_images(manifest, refused=(), classes=classes)
    _, refused = drop_refused_photographs(
        [{"path": path} for paths in images.values() for path in paths],
        cfg,
        scale=photograph_scale_of(manifest),
    )
    return refused


def probe_partition(
    cfg: Mapping,
    manifest: Manifest,
    splits_dir: str,
    refused: Mapping[str, str],
    *,
    classes: Collection[str],
) -> dict:
    """Draw the probe's own partition, with every population splittable.

    Grouped on ``sample_id`` exactly as the protocol requires — no sample group
    spans two capture populations, asserted by a test over the manifest, so the
    grouping leaks nothing. ``train_only_samples`` is deliberately **not**
    passed: SPEC 0040 D6's restriction is what puts `B` beyond the reach of the
    E0 folds, and honouring it here would make the probe unable to ask its own
    question. D6 is untouched — this partition is the probe's and is written to
    its own directory.

    Args:
        refused: The patch grid's refusals, path to the reason, as
            :func:`probe_refusals` returns them. Passed to `create_folds` as
            well as filtered out, so the probe's fold manifest records which
            photographs left and why instead of being eleven short of the
            version it names.
    """
    evaluation = cfg["evaluation"]
    return create_folds(
        population_images(manifest, refused, classes=classes),
        k=evaluation["k"],
        repeats=evaluation["repeats"],
        seed=cfg["data"]["seed"],
        splits_dir=splits_dir,
        sample_ids=sample_ids_by_image(manifest),
        dataset_version=manifest.version,
        manifest_digest=manifest.digest,
        refused=refused,
    )


def probe_verdict(*, correct: int, total: int, prior: float) -> dict:
    """Apply the reading rule, which was fixed before the probe ran.

    The comparison is on the **Wilson lower bound** and not on the point
    estimate, because the question is whether predictability was *demonstrated*:
    at 97 groups a point estimate several points above the prior is routinely
    consistent with no effect. And against the **prior** rather than against
    chance, because the populations are 14 / 20 / 63 groups and always answering
    the majority scores 0.649 having learned nothing.

    Returns:
        The accuracy, its interval, the prior, whether predictability was
        demonstrated, and the reading that follows — in the words the spec fixed.
    """
    if total <= 0:
        raise ValueError("the probe scored no group, so there is nothing to read")

    accuracy = correct / total
    low, high = wilson_interval(correct, total, INTERVAL_CONFIDENCE)
    predictable = low > prior

    if predictable:
        reading = (
            "the capture population is recoverable from the patches the arms "
            "see, so SPEC 0040 D6's train-only rule is a mitigation whose "
            "sufficiency has not been shown. D6 is re-opened: either population "
            "B leaves training entirely, or it is restricted to arms that "
            "provably cannot exploit an encoding signature. Recovering the "
            "population is not the same as the texture arms exploiting it, and "
            "this reading does not say the E0 result is wrong"
        )
    else:
        reading = (
            "predictability of the capture population was not demonstrated at "
            "this resolution, so SPEC 0040 D6's train-only rule stands as "
            "written and the E0 verdict is read as it stands. Failing to "
            "demonstrate an effect is not evidence that there is none"
        )

    return {
        "correct": int(correct),
        "total": int(total),
        "accuracy": accuracy,
        "lower_bound": low,
        "upper_bound": high,
        "prior": prior,
        "confidence": INTERVAL_CONFIDENCE,
        "predictable": predictable,
        "reading": reading,
    }


def majority_prior(fold_manifest: Mapping) -> float:
    """The share the largest population would score by always being answered.

    Counted over **sample groups** and not over photographs, because the group
    is the unit of the accuracy this prior is compared against (ADR 0020). The
    two differ whenever the populations photograph their samples at different
    rates, which this archive does: a photograph-level prior read against a
    group-level accuracy compares two quantities, and can even name a different
    population the majority.

    Read from the fold manifest rather than from the images, so the prior and
    the accuracy are counted over one partition by construction.
    """
    sizes: dict[str, int] = {}
    for group in fold_manifest["groups"].values():
        sizes[group["class"]] = sizes.get(group["class"], 0) + 1
    if not sizes:
        raise ValueError("no population holds a sample group")
    return max(sizes.values()) / sum(sizes.values())


def population_recall(
    pairs: Sequence[tuple[int, int]], ordered: Sequence[str]
) -> dict[str, float | None]:
    """The share of each population's groups the probe recovered.

    Reported beside the pooled figure because a pooled accuracy at the prior is
    consistent with a probe that recovers `B` perfectly and confuses `A` with
    `C` — and `B` is the population the whole question is about. The pooled
    number alone would hide the finding.

    A population no fold scored is ``None`` and not ``0.0``: zero reads as
    "recovered none of them", which is a different fact from "never asked".
    """
    recall: dict[str, float | None] = {}
    for index, population in enumerate(ordered):
        held = [pair for pair in pairs if pair[0] == index]
        if not held:
            recall[population] = None
            continue
        recall[population] = sum(1 for _, predicted in held if predicted == index) / len(
            held
        )
    return recall


#: The predicate, in the words SPEC 0055 fixed, carried in the report so a later
#: reader cannot substitute a different one for the number in front of them.
READING_RULE = (
    "The Wilson 95 % lower bound on pooled group-level accuracy is compared "
    "against the majority-population prior. At or below it, predictability was "
    "not demonstrated at this resolution and SPEC 0040 D6 stands as written. "
    "Above it, the capture population is recoverable from the patches the arms "
    "see and D6 is re-opened by name. The lower bound rather than the point "
    "estimate, because the question is whether predictability was demonstrated; "
    "against the prior rather than against chance, because always answering the "
    "majority population scores the prior having learned nothing."
)

PROBE_REPORT_FILENAME = "probe.json"


def write_probe_report(
    directory: Path | str,
    *,
    version: str,
    manifest_digest: str,
    populations: Sequence[str],
    pairs: Sequence[tuple[int, int]],
    prior: float,
    seeds: Mapping,
    library_versions: Mapping,
) -> dict:
    """Write the probe's verdict, whichever way it reads.

    Committed either way, with everything needed to reproduce it: a probe that
    reported only when it found something would be a probe nobody could read a
    null from.
    """
    correct = sum(1 for truth, predicted in pairs if truth == predicted)
    report = {
        "spec": "0055",
        "dataset_version": version,
        "manifest_digest": manifest_digest,
        "populations": list(populations),
        "reading_rule": READING_RULE,
        "verdict": probe_verdict(correct=correct, total=len(pairs), prior=prior),
        "recall": population_recall(pairs, populations),
        "confusion": _confusion(pairs, populations),
        "seeds": dict(seeds),
        "library_versions": dict(library_versions),
    }

    destination = Path(directory)
    destination.mkdir(parents=True, exist_ok=True)
    (destination / PROBE_REPORT_FILENAME).write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    return report


def _confusion(
    pairs: Sequence[tuple[int, int]], ordered: Sequence[str]
) -> dict[str, dict[str, int]]:
    """Which population each was mistaken for, which the recall alone hides."""
    table = {
        truth: {predicted: 0 for predicted in ordered} for truth in ordered
    }
    for truth, predicted in pairs:
        table[ordered[truth]][ordered[predicted]] += 1
    return table


def probe_directory(output_dir: Path | str) -> Path:
    """Where the probe's folds and report live, beside the arms and not among."""
    return Path(output_dir) / POPULATION_PROBE_ARM
