"""Tests for the two dataset command-line tools (SPEC 0033).

`validate_dataset.py` is what a collector runs to find out whether a version is
usable, so it has to report every problem in one pass rather than the first one.
`admit_images.py` is what decides which candidates enter, and it rewrites the
collector's own manifest, so it does nothing destructive without being told to.
"""

import importlib.util
import json
from pathlib import Path

import pytest

from src.config import load_config
from src.manifest import (
    QUARANTINE_DIRNAME,
    REJECTED_FILENAME,
    read_manifest,
    verify_directory,
)
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


# --- validate_dataset.py ------------------------------------------------------


def test_validator_accepts_a_clean_version(tmp_path, validate_dataset, capsys):
    """A version that satisfies the protocol exits zero."""
    root = write_version(tmp_path)

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
    root = write_version(tmp_path)

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
    root = write_version(tmp_path)

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
    root = write_version(tmp_path)

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
    root = write_version(tmp_path, samples_per_class=2)

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    err = capsys.readouterr().err
    assert code == 1
    assert "splittable sample group" in err
    assert str(load_config()["evaluation"]["k"]) in err


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
    root = write_version(tmp_path)
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
    root = write_version(tmp_path)
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
