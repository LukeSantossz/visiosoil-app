"""Tests for the two dataset command-line tools (SPEC 0033).

`validate_dataset.py` is what a collector runs to find out whether a version is
usable, so it has to report every problem in one pass rather than the first one.
`admit_images.py` is what decides which candidates enter, and it rewrites the
collector's own manifest, so it does nothing destructive without being told to.
"""

import importlib.util
from pathlib import Path

import pytest

from src.manifest import REJECTED_FILENAME, read_manifest
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


def test_validator_prints_the_split_composition(tmp_path, validate_dataset, capsys):
    """Per-split counts by class, site, and device are what the report is for."""
    root = write_version(tmp_path)

    validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    out = capsys.readouterr().out
    for split_name in ("train", "val", "test"):
        assert split_name in out
    assert "class:" in out
    assert "site:" in out
    assert "device:" in out
    assert "Fazenda 0" in out


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
    manifest.write_text(
        manifest.read_text(encoding="utf-8").replace("dish", "in_situ", 1),
        encoding="utf-8",
    )

    validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert "not run" in capsys.readouterr().err


def test_validator_reports_a_version_that_cannot_be_split(
    tmp_path, validate_dataset, capsys
):
    """Too few groups per class is a dataset-size problem, named as one."""
    root = write_image_version(
        tmp_path, {"S1": [("dish", b"x"), ("paper", b"x")]}
    )

    code = validate_dataset.main(
        ["--root", str(root), "--splits-dir", str(tmp_path / "splits")]
    )

    assert code == 1
    assert "Arenosa" in capsys.readouterr().err


# --- admit_images.py ----------------------------------------------------------


def test_admit_defaults_to_a_dry_run(tmp_path, admit_images, capsys):
    """Admission never rewrites a collector's manifest unless asked."""
    root = write_image_version(
        tmp_path, {"S1": [("dish", noise_image()), ("paper", flat_image())]}
    )
    before = (root / "manifest.csv").read_bytes()

    code = admit_images.main(["--root", str(root)])

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

    code = admit_images.main(["--root", str(root), "--write"])

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

    code = admit_images.main(["--root", str(root), "--write"])

    assert code == 0
    assert len(read_manifest(root, CLASSES).rows) == 2


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

    code = admit_images.main(["--root", str(root), "--write"])

    assert code == 2
    assert "Barro" in capsys.readouterr().err
