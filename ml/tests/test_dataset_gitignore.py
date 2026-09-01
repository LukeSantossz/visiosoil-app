"""The ignore rules must actually keep a dataset version out of the repository.

Nothing under a version directory is versioned, the manifest included: the
version is reproducible from the archive by a deterministic ingestion, so it is a
build product. Asserted against `git check-ignore` rather than by
re-implementing gitignore matching, because the pattern semantics are the thing
under test.

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

#: Bookkeeping files that used to be excepted from the ignore-all rule. They are
#: listed here so the reversal is asserted rather than merely performed: an
#: exception that creeps back would put a build product under version control
#: again, and nothing else would notice.
BOOKKEEPING_PATHS = [
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


@pytest.mark.parametrize("path", BOOKKEEPING_PATHS)
def test_dataset_bookkeeping_files_are_ignored_too(path):
    """A dataset version is reproducible, so none of it is a record."""
    assert check_ignore(path), f"{path} would be committed"


def test_no_dataset_version_file_is_tracked():
    """The reversal is asserted against the index, not only against the rules.

    An ignore rule says nothing about a file already in history: `git rm
    --cached` is what removes one, and forgetting it leaves the file tracked and
    the rule inert. This is the check that would have caught that.
    """
    completed = subprocess.run(
        ["git", "ls-files", "--", "ml/data/datasets"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        stdin=subprocess.DEVNULL,
    )

    assert completed.returncode == 0, completed.stderr
    assert completed.stdout.strip() == "", (
        "these dataset-version files are still tracked:\n" + completed.stdout
    )
