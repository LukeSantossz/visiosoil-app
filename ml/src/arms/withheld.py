"""The arms that withhold a capture population from their training side (SPEC 0057).

Each is its base arm with one thing removed and nothing else changed: every
entry whose `source_group` is the population SPEC 0040 D6 restricts leaves the
training side, the inner selection folds included. The **test side is
untouched**, the fold manifest is untouched, and the digest is untouched — which
is what makes the pair a paired contrast rather than two runs that happen to
resemble each other.

Two consequences of keeping the partition still are worth naming, because both
are what the design bought:

- The comparison is **paired on the group** by construction. Redrawing the folds
  without the population would produce a second manifest whose group set matches
  the first only by coincidence of the seed, and nothing would check that it
  still did.
- Whichever configuration ADR 0021 settles on, **that run is the E0 gate's arm**,
  already computed. SPEC 0056's reuse rule verifies that rather than assuming
  it, refusing the reuse if the configuration, the manifest digest or the
  library versions have moved in between.
"""

from __future__ import annotations

from typing import Callable, Mapping

from ..manifest import ARCHIVE_CLASSES, dataset_root, read_manifest, source_groups_by_image
from ..sensitivity import WITHHELD_POPULATION


def population_withholder(cfg: Mapping) -> Callable[[Mapping], bool]:
    """A predicate true for entries from the withheld capture population.

    Read from the manifest's `source_group` column and never inferred. A filter
    that guessed the population from pixel dimensions would be a guess about the
    very thing the experiment is measuring.

    Raises:
        ValueError: If a fold entry names a photograph the manifest does not
            hold. That is a fold manifest and a dataset version disagreeing
            about which images exist, and no filter should absorb it — the arm
            that kept the population would silently train on more.
    """
    data = cfg["data"]
    manifest = read_manifest(
        dataset_root(data["datasets_dir"], data["dataset_version"]), ARCHIVE_CLASSES
    )
    populations = source_groups_by_image(manifest)

    def leaves(entry: Mapping) -> bool:
        try:
            population = populations[entry["path"]]
        except KeyError:
            raise ValueError(
                f"{entry['path']} is in the folds and not in the manifest of "
                f"{data['dataset_version']}, so its capture population is "
                f"unknown and it cannot be withheld or kept deliberately"
            ) from None
        return population == WITHHELD_POPULATION

    return leaves


def descriptor_fold_without_population(cfg: Mapping, fold_manifest: Mapping, **kwargs):
    """The descriptor arm, with the withheld population out of its training side."""
    from .descriptors import descriptor_features
    from .probe import probe_fold

    return probe_fold(
        cfg,
        fold_manifest,
        featuriser=descriptor_features,
        withhold=population_withholder(cfg),
        **kwargs,
    )


def cnn_fold_without_population(cfg: Mapping, fold_manifest: Mapping, **kwargs):
    """The incumbent, with the withheld population out of its training side.

    Imported inside the call, as the arm registry's other CNN thunk is: naming
    this arm should not pull in TensorFlow for a caller that only wanted to know
    the arm exists.
    """
    from ..train import train_fold

    return train_fold(
        cfg, fold_manifest, withhold=population_withholder(cfg), **kwargs
    )
