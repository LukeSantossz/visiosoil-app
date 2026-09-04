"""Tests for the two dataset command-line tools (SPEC 0033).

`validate_dataset.py` is what a collector runs to find out whether a version is
usable, so it has to report every problem in one pass rather than the first one.
`admit_images.py` is what decides which candidates enter, and it rewrites the
collector's own manifest, so it does nothing destructive without being told to.
"""

import csv
import importlib.util
import json
import math
from collections.abc import Mapping
from pathlib import Path

import pytest
from PIL import Image

from src.config import load_config
from src.manifest import (
    QUARANTINE_DIRNAME,
    REJECTED_FILENAME,
    SCALE_COLUMNS,
    class_images,
    read_manifest,
    verify_directory,
)
from src.patches import PatchRefusal, resample_to_canonical
from src.scale import DISH_DIAMETER_MM
from tests.support import (
    CLASSES,
    flat_image,
    noise_image,
    write_image_version,
    write_version,
)

ML_ROOT = Path(__file__).resolve().parents[1]


def load_script(name):
    """Import a file under `scripts/` that is not part of a package."""
    path = ML_ROOT / "scripts" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def validate_dataset():
    return load_script("validate_dataset")


@pytest.fixture(scope="module")
def admit_images():
    return load_script("admit_images")


# --- the SPEC 0052 measurement a fixture version carries ----------------------
#
# Every test about folds needs one. Since SPEC 0053 the partition is a function
# of the measurement — a photograph the patch grid refuses is in no fold — so
# `create_folds_for_config` refuses to partition a version nobody has measured,
# and a fold test built on `write_version` alone would be exercising that
# refusal instead of what it means to exercise.

#: A scale the patch grid accepts: well below the canonical, so nothing is
#: refused for coarseness, and a 90 mm dish still clears the nine-patch floor
#: after the resample. The default for a fixture that is not about the scale.
FINE_MM_PER_PX = 0.05


def canonical_mm_per_px():
    """What training resamples to, read from `config.yaml` as production does."""
    return load_config()["preprocessing"]["canonical_mm_per_px"]


def scale_cells(mm_per_px):
    """The dish-rim columns a reading of ``mm_per_px`` would have produced.

    Nothing on this path decodes an image, so the numbers only have to be
    consistent with each other: the diameter follows from the dish being 90 mm,
    the centre is the middle of a notional 2000 px frame, and that frame is the
    one the reading is expressed in.
    """
    return {
        "mm_per_px": mm_per_px,
        "disc_diameter_px": DISH_DIAMETER_MM / mm_per_px,
        "disc_centre_x_px": 1000.0,
        "disc_centre_y_px": 1000.0,
        "frame_width_px": 2000.0,
        "frame_height_px": 2000.0,
    }


def write_scale_columns(root, readings):
    """Add the SPEC 0052 measurement to a fixture manifest, row by row.

    ``readings`` holds one entry per manifest row, in manifest order: a
    millimetres-per-pixel value, a mapping written into the scale columns
    verbatim, or ``None`` for a row the dish-rim reader gave no scale — which is
    every row of a version that has been ingested and not yet measured.
    """
    path = root / "manifest.csv"
    with path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    assert len(readings) == len(rows), "one reading per manifest row"

    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=list(rows[0]) + list(SCALE_COLUMNS),
            lineterminator="\n",
        )
        writer.writeheader()
        for row, reading in zip(rows, readings):
            if isinstance(reading, Mapping):
                row.update(reading)
            elif reading is not None:
                row.update(scale_cells(reading))
            writer.writerow(row)


def measured_version(tmp_path, readings_for=None, **kwargs):
    """A fixture dataset version carrying the dish-rim measurement.

    ``readings_for`` is called with the manifest row count and returns one entry
    per row; omitted, every photograph is measured at a scale the patch grid
    accepts. The count is passed rather than assumed because it is a property of
    the fixture, and a test that hardcoded it would break the day
    `write_version` changed. Any other keyword goes to `write_version`.
    """
    root = write_version(tmp_path, **kwargs)
    count = len(read_manifest(root, CLASSES).rows)
    write_scale_columns(
        root, readings_for(count) if readings_for else [FINE_MM_PER_PX] * count
    )
    return root, count


# --- validate_dataset.py ------------------------------------------------------


def test_validator_accepts_a_clean_version(tmp_path, validate_dataset, capsys):
    """A version that satisfies the protocol exits zero."""
    root, _ = measured_version(tmp_path)

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 0
    assert "rejected" not in capsys.readouterr().err


def test_fold_composition_is_reported(tmp_path, validate_dataset, capsys):
    """Per repeat and fold, the training and test counts by class and group.

    The composition is what lets a reader see the rules hold — every class in
    every fold, the transported population only ever on the training side —
    without running a test.
    """
    root, _ = measured_version(tmp_path)

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 0
    out = capsys.readouterr().out
    cfg = load_config()
    for repeat in range(cfg["evaluation"]["repeats"]):
        for fold in range(cfg["evaluation"]["k"]):
            assert f"repeat {repeat} fold {fold}" in out
    assert "train:" in out
    assert "test:" in out
    assert "class:" in out
    assert "source_group:" in out
    # The configured classes and not the archive's five: a composition reports
    # the pool, and Siltosa is in the manifest but in no fold (SPEC 0046).
    for texture_class in cfg["classes"]:
        assert texture_class in out
    assert "Siltosa" not in out


def _admit_args(root, tmp_path, *extra):
    """Admission arguments that isolate the immutability check to `tmp_path`.

    `--splits-dir` defaults to `data.splits_dir`, which is the repository's own
    `ml/data/splits/`. A test that omits it builds its dataset in `tmp_path` and
    then asks whether a split *somewhere else entirely* claims that version, so
    the whole admission suite turns red the moment a developer generates a fold
    manifest for v1 — which SPEC 0046's own Reproducibility tells them to do.

    The production default is right; it is the test that was reaching outside
    its fixture.
    """
    return ["--root", str(root), "--splits-dir", str(tmp_path / "splits"), *extra]


def parse_class_counts(section):
    """Read a composition section's `class:` line into name to count.

    Parsed rather than searched for substrings. `"Argilosa" in section` is true
    of a section that holds only `Muito Argilosa=4`, so a substring check
    reported every class present whenever the longer name was, which is exactly
    the case this test exists to catch.
    """
    for line in section.splitlines():
        line = line.strip()
        if not line.startswith("class:"):
            continue
        counts = {}
        for item in line[len("class:"):].split(","):
            item = item.strip()
            if not item:
                continue
            name, _, count = item.rpartition("=")
            counts[name.strip()] = int(count)
        return counts
    raise AssertionError(f"no class line in section: {section!r}")


def test_parse_class_counts_does_not_confuse_two_classes_sharing_a_word():
    """Guards the parser this test's assertion rests on."""
    counts = parse_class_counts("  class: Muito Argilosa=4, Media=2\n")

    assert counts == {"Muito Argilosa": 4, "Media": 2}
    assert "Argilosa" not in counts


def test_fold_composition_holds_every_class_in_every_fold(
    tmp_path, validate_dataset, capsys
):
    """A fold missing a class would be visible here before a run wasted a day."""
    root, _ = measured_version(tmp_path)

    validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    out = capsys.readouterr().out
    cfg = load_config()
    expected_blocks = cfg["evaluation"]["k"] * cfg["evaluation"]["repeats"]
    blocks = out.split("repeat ")[1:]
    assert len(blocks) == expected_blocks, (
        f"{len(blocks)} fold block(s) printed, expected {expected_blocks}"
    )

    for block in blocks:
        # One `test:` per block, so the section cannot run into the next fold.
        assert block.count("test:") == 1, block
        held = parse_class_counts(block.split("test:")[1])
        for texture_class in cfg["classes"]:
            assert held.get(texture_class, 0) >= 1, (
                f"{texture_class} is absent from a fold's test side: {held}"
            )
        assert "Siltosa" not in held, (
            f"a class the model does not emit reached a test side: {held}"
        )


def test_validator_reports_a_schema_problem_and_exits_nonzero(
    tmp_path, validate_dataset, capsys
):
    """An unknown class is named, and the exit code says the run failed."""
    root = write_version(tmp_path)
    manifest = root / "manifest.csv"
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("Arenosa,", "Barro,", 1),
        encoding="utf-8",
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    assert "Barro" in capsys.readouterr().err


def test_validator_reports_an_orphan_image(tmp_path, validate_dataset, capsys):
    """A file nobody declared is reported by name."""
    root = write_version(tmp_path)
    (root / "images" / "orphan.jpg").write_bytes(b"x")

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    assert "orphan.jpg" in capsys.readouterr().err


def test_validator_reports_a_pairing_gap(tmp_path, validate_dataset, capsys):
    """A sample photographed in one condition only is reported."""
    root = write_version(tmp_path)
    manifest = root / "manifest.csv"
    kept = [
        line
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if not line.startswith("Arenosa-0,Arenosa,images/Arenosa-0_paper.jpg")
    ]
    manifest.write_text("\n".join(kept) + "\n", encoding="utf-8")
    (root / "images" / "Arenosa-0_paper.jpg").unlink()

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    err = capsys.readouterr().err
    assert "Arenosa-0" in err
    assert "paper" in err


def test_validator_says_when_it_stopped_before_the_disk_checks(
    tmp_path, validate_dataset, capsys
):
    """Silence about a check that never ran reads as a check that passed."""
    root = write_version(tmp_path)
    manifest = root / "manifest.csv"
    # Replace the `setting` cell, not the first occurrence of the word: the
    # filenames contain it too, and hitting one of those would raise a
    # not-found-on-disk error instead of the invalid-setting error under test.
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace(",dish,", ",in_situ,", 1),
        encoding="utf-8",
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    err = capsys.readouterr().err
    assert code == 1
    assert "in_situ" in err
    assert "not run" in err


def test_validator_reports_a_class_with_no_photographs(
    tmp_path, validate_dataset, capsys
):
    """A four-class version cannot support the five-way product contract.

    Left unreported it is worse than thin data: the class list is the model's
    output order, so a class at zero reindexes every label in `splits.json`.

    The class removed is a **configured** one. Removing Siltosa proves nothing
    since SPEC 0046 — the model does not emit it, so a version holding none of
    it is valid, and this test passed for that reason rather than for the one
    it was written for.
    """
    absent_class = "Arenosa"
    root = write_version(tmp_path)
    manifest = root / "manifest.csv"
    kept = [
        line
        for line in manifest.read_text(encoding="utf-8").splitlines()
        if f",{absent_class}," not in line
    ]
    manifest.write_text("\n".join(kept) + "\n", encoding="utf-8")
    for orphan in (root / "images").glob(f"{absent_class}-*"):
        orphan.unlink()

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    assert absent_class in capsys.readouterr().err


def test_validator_does_not_publish_splits_by_default(tmp_path, validate_dataset):
    """Reporting a composition must not overwrite the pipeline's own splits.

    `src.train` reuses any existing `splits.json` and the file is gitignored, so
    a validator that wrote there by default would silently replace an artefact
    the next training run consumes.

    Asserted as *unchanged* rather than *absent*. Absent was the weaker claim and
    the wrong one twice over: it held only on a machine where no fold manifest
    had ever been generated — which SPEC 0046's own workflow tells a developer to
    do — and it could never fail on the overwrite this docstring names, because a
    file that is replaced still exists.
    """
    from src.config import load_config, resolve_paths

    configured = Path(resolve_paths(load_config())["data"]["splits_dir"])
    published = configured / "splits.json"
    before = published.read_bytes() if published.exists() else None
    root, _ = measured_version(tmp_path)

    code = validate_dataset.main(["--root", str(root)])

    assert code == 0
    after = published.read_bytes() if published.exists() else None
    assert after == before, (
        f"the validator wrote to the configured splits directory {configured}"
    )


def test_validator_reports_a_version_that_cannot_be_folded(
    tmp_path, validate_dataset, capsys
):
    """Too few groups per class is a dataset-size problem, named as one.

    Every class is present, so the coverage check passes and the fold generator
    is what has to speak. The floor is k, which is what the protocol needs to
    put a group of every class in every fold's test side.
    """
    root, _ = measured_version(tmp_path, samples_per_class=2)

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    err = capsys.readouterr().err
    assert code == 1
    assert "splittable sample group" in err
    assert str(load_config()["evaluation"]["k"]) in err


# --- validate_dataset.py: the measured scale (SPEC 0053) ----------------------


def test_validator_reports_the_measured_scale_spread(
    tmp_path, validate_dataset, capsys
):
    """The spread is the evidence SPEC 0053 rests on, so the tool states it.

    A reader has to be able to see that the archive photographs the same soil at
    apparent sizes differing by nearly five to one without opening a notebook:
    that ratio is the entire reason the patch pipeline resamples (ADR 0017).
    """
    root, count = measured_version(
        tmp_path, lambda rows: [0.04] * (rows - 1) + [0.16]
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 0
    out = capsys.readouterr().out
    assert f"scale measured on {count} of {count}" in out
    assert "0.0400" in out
    assert "0.1600" in out
    assert "4.00x" in out


def test_validator_reports_an_unmeasured_version_without_failing_it(
    tmp_path, validate_dataset, capsys
):
    """Ingested but not yet measured is a step of the pipeline, not corruption.

    `measure_scale.py` reads a manifest that already validates, so a validator
    that failed an unmeasured version would refuse exactly the state the
    measuring step exists to consume. It is still reported, and with the command
    that fixes it: silence about a measurement never taken reads as one that is
    fine.
    """
    root = write_version(tmp_path)
    count = len(read_manifest(root, CLASSES).rows)

    code = validate_dataset.main(["--root", str(root)])

    assert code == 0
    out = capsys.readouterr().out
    assert f"{count} of {count} photograph(s) carry no measured scale" in out
    assert "scripts/measure_scale.py --version v1" in out
    # One remedy line, not one per row: the command is version-wide, and eighty
    # copies of it would bury the count above them.
    assert out.count("scripts/measure_scale.py") == 1


def test_an_unmeasured_version_gets_no_fold_composition(
    tmp_path, validate_dataset, capsys
):
    """A composition printed now would not be the one training draws.

    Since SPEC 0053 the partition is a function of the measurement — a
    photograph the patch grid refuses is in no fold — so the composition is not
    merely unavailable, it is unknowable until the version is measured. Named as
    absent, because a validator that printed a plausible one would be reporting
    a partition nothing will use.
    """
    root = write_version(tmp_path)

    code = validate_dataset.main(["--root", str(root)])

    assert code == 0
    out = capsys.readouterr().out
    assert "no fold composition" in out
    assert "repeat 0 fold 0" not in out


def test_asking_an_unmeasured_version_to_publish_splits_fails(
    tmp_path, validate_dataset, capsys
):
    """The exit code follows what was asked for, not what the version is.

    Without `--splits-dir` this command is a report, and the report is complete.
    With it the command was asked to produce `splits.json` — the artefact
    `src.crossval` reuses and `admit_images.py` treats as freezing the version —
    and it cannot produce an honest one. Exiting 0 having written nothing is
    indistinguishable, to a shell script chaining a training run onto this, from
    having written it.
    """
    root = write_version(tmp_path)
    splits_dir = tmp_path / "splits"

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(splits_dir)]
    )

    assert code == 1
    assert not (splits_dir / "splits.json").exists()
    err = capsys.readouterr().err
    assert "no measured scale" in err
    assert "splits.json" in err


def test_validator_names_the_photographs_a_measured_version_missed(
    tmp_path, validate_dataset, capsys
):
    """A gap in a measured version is the dish-rim reader refusing a photograph.

    Which ones is the whole information a collector can act on, so they are
    named rather than counted. The spread is still reported beside them, because
    a run that measured most of a version must not read as one that measured
    none.
    """
    gap = 3
    root, count = measured_version(
        tmp_path, lambda rows: [None] * gap + [0.04] * (rows - gap - 1) + [0.16]
    )
    missed = [row.image for row in read_manifest(root, CLASSES).rows[:gap]]

    # No `--splits-dir`: a gap is still an unmeasured version as far as the
    # partition is concerned, and this test is about what the report says.
    code = validate_dataset.main(["--root", str(root)])

    assert code == 0
    out = capsys.readouterr().out
    assert f"scale measured on {count - gap} of {count}" in out
    assert f"{gap} of {count} photograph(s) carry no measured scale" in out
    for image in missed:
        assert image in out


def test_a_gap_larger_than_the_cap_is_counted_rather_than_listed(
    tmp_path, validate_dataset, capsys
):
    """Naming a gap must not push the fold composition off the screen."""
    named = validate_dataset._UNMEASURED_NAMED
    gap = named + 2
    root, _ = measured_version(
        tmp_path, lambda rows: [None] * gap + [FINE_MM_PER_PX] * (rows - gap)
    )

    code = validate_dataset.main(["--root", str(root)])

    assert code == 0
    out = capsys.readouterr().out
    assert out.count("scripts/measure_scale.py") == named
    assert f"and {gap - named} more" in out


def test_validator_counts_the_photographs_too_coarse_to_normalise(
    tmp_path, validate_dataset, capsys
):
    """The photographs that leave training are counted where a reader will see it.

    Counted against `config.yaml`'s canonical, which is the value training
    reads, so the number describes the population a run will actually see rather
    than one a spec quoted.
    """
    canonical = canonical_mm_per_px()
    coarse = 3
    root, count = measured_version(
        tmp_path,
        lambda rows: [canonical * 2.0] * coarse + [canonical / 2.0] * (rows - coarse),
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 0
    out = capsys.readouterr().out
    assert f"{coarse} of {count} measured photograph(s) are coarser" in out
    assert PatchRefusal.TOO_COARSE.value in out


def test_the_coarse_count_is_the_one_the_patch_pipeline_refuses(
    tmp_path, validate_dataset, capsys
):
    """A photograph exactly at the canonical trains; a hair coarser does not.

    The validator compares the scales itself, so the boundary is pinned here to
    `patches.resample_to_canonical`, which is what actually refuses the
    photograph. An inclusive comparison in either place would report a count no
    training run produces.
    """
    canonical = canonical_mm_per_px()
    just_coarser = math.nextafter(canonical, math.inf)
    root, count = measured_version(
        tmp_path,
        lambda rows: [canonical, just_coarser] + [canonical / 2.0] * (rows - 2),
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 0
    assert f"1 of {count} measured photograph(s) are coarser" in capsys.readouterr().out

    frame = Image.new("RGB", (8, 8))
    resample_to_canonical(frame, canonical, canonical)
    with pytest.raises(ValueError, match=PatchRefusal.TOO_COARSE.value):
        resample_to_canonical(frame, just_coarser, canonical)


def test_validator_refuses_a_non_positive_disc_diameter_by_name(
    tmp_path, validate_dataset, capsys
):
    """A diameter of zero would divide by zero in the patch geometry.

    Refused at the manifest, which is where a measurement that cannot be one has
    to stop, and reported through the tool a collector actually runs rather than
    only through the parser.
    """
    root, _ = measured_version(
        tmp_path,
        lambda rows: [{**scale_cells(0.05), "disc_diameter_px": 0.0}]
        + [0.05] * (rows - 1),
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    assert "disc_diameter_px" in capsys.readouterr().err


# --- admit_images.py ----------------------------------------------------------


def test_admit_defaults_to_a_dry_run(tmp_path, admit_images, capsys):
    """Admission never rewrites a collector's manifest unless asked."""
    root = write_image_version(
        tmp_path, {"S1": [("dish", noise_image()), ("paper", flat_image())]}
    )
    before = (root / "manifest.csv").read_bytes()

    code = admit_images.main(_admit_args(root, tmp_path))

    assert (root / "manifest.csv").read_bytes() == before
    assert not (root / REJECTED_FILENAME).exists()
    assert code == 1
    out = capsys.readouterr().out
    assert "dry run" in out.lower()


def test_admit_writes_the_manifest_and_the_refusal_report(
    tmp_path, admit_images
):
    """With --write, the manifest holds the admitted rows and their metrics."""
    root = write_image_version(
        tmp_path, {"S1": [("dish", noise_image()), ("paper", flat_image())]}
    )

    code = admit_images.main(_admit_args(root, tmp_path, "--write"))

    reloaded = read_manifest(root, CLASSES)
    assert [row.image for row in reloaded.rows] == ["images/S1_dish.png"]
    assert reloaded.rows[0].metrics
    report = (root / REJECTED_FILENAME).read_text(encoding="utf-8")
    assert "images/S1_paper.png" in report
    assert "blur" in report
    assert code == 1


def test_admit_exits_zero_when_every_candidate_is_admitted(
    tmp_path, admit_images
):
    """Nothing to fix means nothing to report."""
    root = write_image_version(
        tmp_path,
        {"S1": [("dish", noise_image()), ("paper", noise_image(seed=11))]},
    )

    code = admit_images.main(_admit_args(root, tmp_path, "--write"))

    assert code == 0
    assert len(read_manifest(root, CLASSES).rows) == 2


def test_admit_quarantines_a_refused_image(tmp_path, admit_images, validate_dataset):
    """A refused file leaves the dataset, so the version still validates.

    Dropping the row while leaving the file on disk made the documented workflow
    self-contradicting: the next validator run reported every refused image as an
    orphan and refused the version admission had just produced.
    """
    root = write_image_version(
        tmp_path,
        {
            "S1": [("dish", noise_image()), ("paper", flat_image())],
        },
    )

    admit_images.main(_admit_args(root, tmp_path, "--write"))

    assert not (root / "images" / "S1_paper.png").exists()
    # The path under quarantine mirrors the path the row declared, rather than
    # flattening to the basename: two subdirectories may hold the same filename,
    # and where a refused image came from is part of what makes it evidence.
    assert (root / QUARANTINE_DIRNAME / "images" / "S1_paper.png").is_file()
    # The pairing check still reports the gap; the orphan must not be reported.
    assert "orphan" not in "".join(
        verify_directory(read_manifest(root, CLASSES))
    )


def test_admit_refuses_to_rewrite_a_version_an_existing_split_claims(
    tmp_path, admit_images, validate_dataset, capsys
):
    """Rewriting a manifest a split was generated from destroys its provenance."""
    # Measured, because the validator only publishes a split for a version whose
    # scale is known: the guard under test is admission's, and it needs a split
    # to exist before it can refuse.
    root, _ = measured_version(tmp_path)
    splits_dir = tmp_path / "splits"
    validate_dataset.main(["--root", str(root), "--splits-dir", str(splits_dir)])
    before = (root / "manifest.csv").read_bytes()

    code = admit_images.main(
        ["--root", str(root), "--write", "--splits-dir", str(splits_dir)]
    )

    assert code == 3
    assert (root / "manifest.csv").read_bytes() == before
    err = capsys.readouterr().err
    assert "immutable" in err.lower()


def test_admit_refuses_when_a_split_claims_the_version_with_a_stale_digest(
    tmp_path, admit_images, validate_dataset, capsys
):
    """Any split naming this version freezes it, matching digest or not.

    Guarding on an exact digest match was backwards: a split recording an older
    digest of the same version is the one already unverifiable, and rewriting
    again makes that permanent instead of telling the operator to move to vN+1.
    """
    root, _ = measured_version(tmp_path)
    splits_dir = tmp_path / "splits"
    validate_dataset.main(["--root", str(root), "--splits-dir", str(splits_dir)])
    splits = splits_dir / "splits.json"
    recorded = json.loads(splits.read_text(encoding="utf-8"))
    recorded["manifest_digest"] = "0" * 64
    splits.write_text(json.dumps(recorded), encoding="utf-8")
    before = (root / "manifest.csv").read_bytes()

    code = admit_images.main(
        ["--root", str(root), "--write", "--splits-dir", str(splits_dir)]
    )

    assert code == 3
    assert (root / "manifest.csv").read_bytes() == before
    assert "immutable" in capsys.readouterr().err.lower()


def test_admit_treats_a_non_mapping_split_as_unusable(tmp_path, admit_images):
    """`[]` is valid JSON, so the guard must not crash on it.

    The surrounding code promises an unreadable split is treated as claiming
    nothing; `recorded.get` on a list raised `AttributeError` instead.
    """
    root = write_image_version(tmp_path, {"S1": [("dish", noise_image())]})
    splits_dir = tmp_path / "splits"
    splits_dir.mkdir()
    (splits_dir / "splits.json").write_text("[]", encoding="utf-8")

    code = admit_images.main(
        ["--root", str(root), "--write", "--splits-dir", str(splits_dir)]
    )

    assert code == 0


def test_admit_keeps_the_dataset_consistent_when_quarantine_fails(
    tmp_path, admit_images, monkeypatch
):
    """A half-applied --write must not exist.

    The manifest is staged before any file moves, so a failure while moving
    leaves the committed manifest and the images exactly as they were, and the
    staged file is not left behind to be mistaken for one.
    """
    root = write_image_version(
        tmp_path, {"S1": [("dish", noise_image()), ("paper", flat_image())]}
    )
    before = (root / "manifest.csv").read_bytes()
    monkeypatch.setattr(
        admit_images,
        "quarantine_refused",
        lambda *args, **kwargs: (_ for _ in ()).throw(OSError("disk went away")),
    )

    with pytest.raises(OSError):
        admit_images.main(
            ["--root", str(root), "--write", "--splits-dir", str(tmp_path / "none")]
        )

    assert (root / "manifest.csv").read_bytes() == before
    assert (root / "images" / "S1_paper.png").is_file()
    assert list(root.glob("manifest.csv.*")) == []


def test_admit_rejects_a_version_name_that_escapes_the_datasets_root(
    tmp_path, admit_images, capsys
):
    """`--version` is a directory name, not a path, and it reaches a writer.

    Reported through the documented exit code rather than as a traceback. An
    earlier version of this test asserted `pytest.raises(ValueError)`, which
    encoded the defect as the expectation: `validate_version_name` raises a plain
    `ValueError`, the CLI caught only `ManifestError`, and the bad flag escaped
    as a stack trace past every documented exit code.
    """
    code = admit_images.main(["--version", "../elsewhere", "--write"])

    assert code == 2
    assert "dataset version" in capsys.readouterr().err


def test_validator_rejects_a_version_name_that_is_not_a_version(
    tmp_path, validate_dataset, capsys
):
    """The same rule, reported the same way, on the read-only tool."""
    code = validate_dataset.main(["--version", "latest"])

    assert code == 1
    assert "dataset version" in capsys.readouterr().err


def test_admit_writes_when_no_split_claims_the_version(
    tmp_path, admit_images, capsys
):
    """The guard is about provenance, so an unclaimed version still admits."""
    root = write_image_version(tmp_path, {"S1": [("dish", noise_image())]})

    code = admit_images.main(
        ["--root", str(root), "--write", "--splits-dir", str(tmp_path / "empty")]
    )

    assert code == 0
    assert read_manifest(root, CLASSES).rows[0].metrics


def test_admit_output_survives_a_narrow_console_encoding(
    tmp_path, admit_images, capsys
):
    """A collector's Windows console may be cp437, which has no em dash.

    `print` encodes with the console's code page, so a non-ASCII character in a
    refusal line crashes the tool on the machine it exists to serve — and only
    there, which is the worst place to find out.
    """
    root = write_image_version(
        tmp_path, {"S1": [("dish", noise_image()), ("paper", flat_image())]}
    )

    admit_images.main(["--root", str(root), "--splits-dir", str(tmp_path / "none")])

    captured = capsys.readouterr()
    (captured.out + captured.err).encode("cp437")


def test_admit_reports_an_invalid_manifest_without_analyzing(
    tmp_path, admit_images, capsys
):
    """A manifest that does not parse is a different failure, and says so."""
    root = write_image_version(tmp_path, {"S1": [("dish", noise_image())]})
    manifest = root / "manifest.csv"
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("Arenosa,", "Barro,", 1),
        encoding="utf-8",
    )

    code = admit_images.main(_admit_args(root, tmp_path, "--write"))

    assert code == 2
    assert "Barro" in capsys.readouterr().err


def test_the_validator_keeps_a_refused_photograph_out_of_the_folds(
    tmp_path, validate_dataset
):
    """The tool that writes the partition applies the filter that shapes it.

    The validator is what a collector runs to produce `splits.json`, so a filter
    that only ran on the training entry point would leave the two producing
    different partitions from the same version — and the one actually written to
    disk would be the unfiltered one.
    """
    root = write_version(tmp_path)
    manifest = read_manifest(root, CLASSES)
    # The pool, not the manifest. `class_images` keeps only the classes the model
    # emits, so the archive's fifth class is in the version and in no fold
    # (SPEC 0046): a coarse Siltosa row would be filtered out before the patch
    # grid ever saw it, and the refusal under test would never happen.
    pooled = {
        path
        for paths in class_images(manifest, load_config()["classes"]).values()
        for path in paths
    }
    coarse = next(
        row.image for row in manifest.rows if str(manifest.root / row.image) in pooled
    )
    write_scale_columns(
        root,
        [
            canonical_mm_per_px() * 2.0 if row.image == coarse else FINE_MM_PER_PX
            for row in manifest.rows
        ],
    )
    splits_dir = tmp_path / "splits"

    assert (
        validate_dataset.main(["--root", str(root), "--splits-dir", str(splits_dir)])
        == 0
    )

    fold_manifest = json.loads(
        (splits_dir / "splits.json").read_text(encoding="utf-8")
    )
    listed = {
        image
        for record in fold_manifest["groups"].values()
        for image in record["images"]
    }
    assert fold_manifest["counts"]["refused_photographs"] == 1
    assert len(fold_manifest["refused"]) == 1
    refused = next(iter(fold_manifest["refused"]))
    assert Path(refused).name == Path(coarse).name
    assert refused not in listed
    # Derived from the pool rather than from the manifest row count: the pool is
    # already four classes of the archive's five, so the answer is one short of
    # the pool and not one short of the version.
    assert len(listed) == len(pooled) - 1
