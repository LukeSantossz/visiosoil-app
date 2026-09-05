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


#: The fold manifest. Tracked on 2026-09-05 and untracked the same day: it
#: stores absolute image paths, so a copy on another machine is a manifest whose
#: every path is wrong, and tracking it bought nothing the move it was tracked
#: for could use. Listed here so the reversal is asserted rather than merely
#: performed — the same reason `BOOKKEEPING_PATHS` exists. See #233.
WITHDRAWN_PATHS = [
    "ml/data/splits/splits.json",
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


@pytest.mark.parametrize("path", WITHDRAWN_PATHS)
def test_the_fold_manifest_is_not_tracked_while_its_paths_are_absolute(path):
    """Tracking it was tried and withdrawn, and the reason is worth keeping.

    The partition is genuinely not reproducible — `StratifiedGroupKFold` assigns
    differently across scikit-learn releases, which is why `splits.json` records
    the versions it was drawn under — so a record of it *should* travel. What
    stops it is that the file stores absolute image paths and nothing re-roots
    them on load, so a copy on another machine is a manifest every one of whose
    paths is wrong. Relative paths are a schema change (#233).
    """
    assert check_ignore(path), f"{path} would be committed"


def test_the_fold_manifest_is_not_in_the_index_either():
    """An ignore rule says nothing about a file already added.

    `git rm --cached` is what removes one, and this is the check that would have
    caught forgetting it — the same guard `test_no_dataset_version_file_is_tracked`
    makes for the dataset.
    """
    completed = subprocess.run(
        ["git", "ls-files", "--", "ml/data/splits"],
        cwd=REPO_ROOT,
        capture_output=True,
        stdin=subprocess.DEVNULL,
    )
    tracked = [
        name
        for name in completed.stdout.decode(errors="replace").split()
        if not name.endswith(".gitkeep")
    ]

    assert tracked == [], f"the fold manifest is still in the index: {tracked}"
