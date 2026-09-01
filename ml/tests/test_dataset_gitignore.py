"""The ignore rules must actually keep dataset images out of the repository.

`manifest.csv` is the record and is versioned; the images it lists are large and
are not. Asserted against `git check-ignore` rather than by re-implementing
gitignore matching, because the pattern semantics are the thing under test.

Casing matters here and not only in theory: the scanner matches suffixes
case-insensitively, cameras commonly produce `.JPG`, and the CI runner is
Linux — so a lowercase-only pattern would let camera files into history on
exactly the machine that builds the release.
"""

import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

IGNORED_PATHS = [
    "ml/data/datasets/v1/images/sample_dish.jpg",
    "ml/data/datasets/v1/images/sample_dish.JPG",
    "ml/data/datasets/v1/images/sample_paper.jpeg",
    "ml/data/datasets/v1/images/sample_paper.PNG",
    "ml/data/datasets/v1/images/sample.BMP",
    "ml/data/datasets/v1/images/sample.WebP",
    "ml/data/datasets/v1/rejected/images/refused.JPG",
    "ml/data/datasets/v2/images/other.png",
]

TRACKED_PATHS = [
    "ml/data/datasets/v1/manifest.csv",
    "ml/data/datasets/v1/admission-rejected.csv",
]


def check_ignore(path: str) -> bool:
    """Whether git would ignore ``path``, asked of git itself."""
    completed = subprocess.run(
        ["git", "check-ignore", "-q", path],
        cwd=REPO_ROOT,
        capture_output=True,
        # pytest hands the test an stdin handle subprocess cannot duplicate on
        # Windows, which surfaces as `OSError: [WinError 6] invalid handle`
        # before git ever runs. DEVNULL is the fix; without it this test fails
        # for a reason that has nothing to do with ignore rules.
        stdin=subprocess.DEVNULL,
    )
    if completed.returncode not in (0, 1):
        pytest.fail(f"git check-ignore failed: {completed.stderr.decode(errors='replace')}")
    return completed.returncode == 0


@pytest.mark.parametrize("path", IGNORED_PATHS)
def test_dataset_images_are_ignored(path):
    """No dataset image reaches history, whatever its extension's casing."""
    assert check_ignore(path), f"{path} would be committed"


@pytest.mark.parametrize("path", TRACKED_PATHS)
def test_dataset_bookkeeping_files_are_not_ignored(path):
    """The manifest is the record, so it has to be committable."""
    assert not check_ignore(path), f"{path} is ignored but must be versioned"


def test_the_manifest_is_pinned_to_lf_so_its_digest_survives_a_checkout():
    """A split proves it belongs to a manifest by that manifest's byte digest.

    `core.autocrlf` is on by default on Windows, so without an explicit
    attribute the same committed manifest hashes differently on a Windows
    checkout than on the Linux runner, and every split generated on one platform
    reports itself foreign on the other.

    Asserted through `git check-attr` rather than by reading `.gitattributes`,
    because what matters is the attribute git actually resolves for the path.
    """
    completed = subprocess.run(
        [
            "git",
            "check-attr",
            "text",
            "eol",
            "--",
            "ml/data/datasets/v1/manifest.csv",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr
    assert "text: set" in completed.stdout
    assert "eol: lf" in completed.stdout
