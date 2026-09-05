"""The linear-probe fold trainer both new E0 arms are built on (SPEC 0054).

:func:`probe_fold` does what :func:`src.train.train_fold` does, with a
featuriser in place of the network — a sibling implementation of one protocol
and **not** a wrapper around it, so nothing here calls into `train.py`. It
selects the probe's regularisation strength on the inner folds of one outer
fold's training side, refits on the whole training side, predicts the test side,
and writes the same four artifacts the incumbent writes — so ``evaluate.py``,
the contrasts and the pooling read a completed fold without knowing which arm
produced it.

The classical-descriptor arm and the frozen-encoder arm differ only in where
their features come from. Implementing the protocol once and parameterising it
by :class:`Featuriser` is what makes a contrast between them a statement about
the features: two hand-written fold trainers could differ in the nesting, in
where the scaler was fitted or in how a photograph's patches were folded back
into one prediction, and a difference in the result could then be attributed to
none of them.

Two rules here are what make an arm comparable to the incumbent rather than
merely runnable:

- **A photograph's patches are scored, and their distributions averaged.** Not
  their features pooled. SPEC 0054's Alternatives Considered rejects pooling
  because the incumbent averages distributions: an arm that pooled features
  would differ from it in the aggregation as well as in the method.
- **The scaler is fitted on the training side alone.** Fitting it on everything
  leaks the test side's distribution into every arm at once, which flatters them
  all by about the same amount and therefore hides in the contrasts rather than
  showing up as one arm doing implausibly well.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Mapping, Protocol, Sequence

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from ..crossval import (
    RUNTIME_FILENAME,
    assert_selection_is_nested,
    fold_directory,
    write_fold_cost,
    write_fold_predictions,
    write_selection_audit,
)
from ..dataset import (
    derive_repeat_seed,
    fold_split,
    inner_folds,
    permute_labels_by_group,
    verify_images,
)

#: The regularisation strengths selection chooses between. Five points a decade
#: apart, fixed here and before the run for the reason SPEC 0054 fixes the
#: descriptor groups: every selection dimension is paid for out of the same
#: inner folds, and at 77 groups a finer grid buys selection variance rather
#: than a better setting. Recorded in the audit, so a fold says which grid it
#: chose from rather than referring the reader to this constant.
C_GRID = (0.01, 0.1, 1.0, 10.0, 100.0)

#: An explicit iteration cap, so a run cannot differ by how long it happened to
#: iterate. `lbfgs` stops at a tolerance it usually reaches well inside this;
#: what the cap removes is the case where it does not and two otherwise
#: identical runs stop at different points.
MAX_ITER = 1000

#: Fixed, and not derived from the repeat seed. `lbfgs` on a dense matrix is
#: deterministic, so this decides nothing today; it is set because leaving a
#: `random_state` at its default is how a solver change turns a reproducible arm
#: into an unreproducible one without any diff saying so.
PROBE_RANDOM_STATE = 0

#: Step names of the fitted pipeline, so a caller — or a test asserting where
#: the standardisation statistics came from — can reach either half by name.
STANDARDISE_STEP = "standardise"
PROBE_STEP = "probe"

#: What the selection audit records as the rule it chose under. The same
#: aggregation the fold is finally scored with, applied to the inner validation
#: side: selecting on patch-level accuracy would choose the setting that is best
#: at a quantity nothing reports.
SELECTION_CRITERION = (
    "mean photograph-level accuracy over the inner folds, ties to the "
    "strongest regularisation"
)


class Featuriser(Protocol):
    """One photograph's patches, as rows of features.

    This is the contract an arm implements to plug into :func:`probe_fold`. It
    is called once per split entry, with the entry the fold manifest yields —
    ``{"path", "label", "class", "group"}`` — and the resolved configuration.

    Returns:
        A ``(n_patches, n_features)`` real-valued array: **one row per patch of
        that photograph**, in a deterministic order, with the same
        ``n_features`` for every entry of a run. Every row must be finite, and a
        photograph must yield at least one.

    A featuriser is a function of the photograph's pixels and of the
    configuration, and of nothing else. In particular it must not read
    ``entry["label"]`` or ``entry["class"]``: those are the answer, they are
    permuted under the shuffled control, and features derived from them would
    make every arm score perfectly while measuring nothing.

    It is called several times for the same photograph within one fold — once
    per inner fold that holds it, and again for the refit. :func:`probe_fold`
    memoises the result by path for the duration of the fold, so a featuriser
    only needs to be *deterministic*, not cheap; one whose cost is real across
    folds, like the frozen encoder's, caches across the run itself.
    """

    def __call__(self, entry: Mapping, cfg: Mapping) -> np.ndarray: ...


def fit_probe(
    features,
    labels,
    *,
    c: float,
    max_iter: int = MAX_ITER,
    random_state: int = PROBE_RANDOM_STATE,
) -> Pipeline:
    """Standardise ``features`` and fit a multinomial logistic regression on them.

    A pipeline rather than two calls, because the two must not be separated: the
    scaler's statistics have to come from the rows the probe was fitted on and
    from no others, and a pipeline makes that a property of the object instead
    of a rule every caller has to remember. It also carries the transform to
    prediction time, so the test side is standardised with the training side's
    statistics rather than with its own.

    `multi_class` is not passed. It is deprecated across the pinned scikit-learn
    range, and `lbfgs` is already multinomial for more than two classes, so
    naming it would trade a warning for nothing.
    """
    return Pipeline(
        [
            (STANDARDISE_STEP, StandardScaler()),
            (
                PROBE_STEP,
                LogisticRegression(
                    C=float(c),
                    penalty="l2",
                    solver="lbfgs",
                    max_iter=int(max_iter),
                    random_state=int(random_state),
                ),
            ),
        ]
    ).fit(np.asarray(features, dtype=np.float64), np.asarray(labels))


def probe_fold(
    cfg: dict,
    fold_manifest: dict,
    *,
    arm_dir: Path | str,
    arm: str,
    repeat: int,
    fold: int,
    featuriser: Featuriser,
    shuffled_control: bool = False,
    verify: bool = True,
    forced: bool = False,
) -> dict:
    """Select, refit and predict one outer fold of a probe arm, writing its artifacts.

    Args:
        cfg: The resolved configuration.
        fold_manifest: The fold manifest the run is scored against.
        arm_dir: ``models/<version>/<arm>``.
        arm: Name of the experimental arm.
        repeat: Repeat index.
        fold: Outer fold index.
        featuriser: The arm's features, per the :class:`Featuriser` contract.
        shuffled_control: Permute ``texture_class`` across groups within this
            fold's training side, leaving the test side untouched.
        verify: Decode every referenced image before building anything. The
            orchestrator verifies once for the whole run and passes ``False``.

    Returns:
        The runtime record this fold ran under.
    """
    # Imported here rather than at module scope because `src.train` imports
    # TensorFlow, and a descriptor arm that needed the training stack to seed
    # itself would be a descriptor arm that cannot run where TensorFlow cannot
    # be installed. Seeding is shared with the incumbent rather than
    # reimplemented: SPEC 0054 requires both arms to be seeded exactly as it is,
    # and the runtime record is what a later comparison reads to decide whether
    # two runs are comparable at all.
    from ..train import _by_class, _relabel, control_seed, seed_everything

    runtime = seed_everything(
        derive_repeat_seed(cfg["data"]["seed"], repeat),
        deterministic_ops=cfg["training"]["deterministic_ops"],
    )

    directory = fold_directory(arm_dir, repeat, fold)
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / "config.json", "w") as handle:
        json.dump(cfg, handle, indent=2)
    # Persisted here rather than recomputed later because evaluation frequently
    # runs on another machine: a value derived at evaluation time would describe
    # that host and silently claim to describe this one.
    with open(directory / RUNTIME_FILENAME, "w") as handle:
        json.dump(runtime, handle, indent=2)

    split = fold_split(fold_manifest, repeat, fold)
    inner = inner_folds(fold_manifest, repeat, fold, cfg["evaluation"]["inner_k"])

    permutation_seed = None
    if shuffled_control:
        permutation_seed = control_seed(cfg["data"]["seed"], repeat, fold)
        # The training side only. The test side is never passed to the
        # permutation, which is what makes "the test side is untouched" a
        # property of the call graph rather than of a comment.
        permuted = permute_labels_by_group(split["train"], permutation_seed)
        labels_by_group = {entry["group"]: entry["label"] for entry in permuted}
        classes_by_group = {entry["group"]: entry["class"] for entry in permuted}
        split["train"] = permuted
        inner = [
            {
                side: _relabel(entries, labels_by_group, classes_by_group)
                for side, entries in inner_split.items()
            }
            for inner_split in inner
        ]

    if verify:
        verify_images(_by_class(split["train"] + split["test"]))

    print(
        f"repeat {repeat} fold {fold}: "
        f"{len(split['train'])} training and {len(split['test'])} test "
        f"photograph(s) over "
        f"{len({e['group'] for e in split['train']})} training and "
        f"{len({e['group'] for e in split['test']})} test group(s)"
    )

    selection_group_ids = [
        entry["group"]
        for inner_split in inner
        for side in ("train", "val")
        for entry in inner_split[side]
    ]
    test_group_ids = [entry["group"] for entry in split["test"]]
    # Before the first inner fit, not after the last: a leak found at write time
    # has already cost the whole selection budget.
    assert_selection_is_nested(selection_group_ids, test_group_ids, repeat, fold)

    # One block of features per photograph, for the whole fold. Every inner fold
    # holds most of the training side and the refit holds all of it, so without
    # this the arm would featurise each photograph about `inner_k` times over.
    # Keyed by path because features are a function of the pixels: a featuriser
    # whose output moved with the entry's label would be reading the answer, and
    # this key does not let a permuted label produce different features.
    cache: dict[str, np.ndarray] = {}

    seconds: list[float] = []
    accuracies: list[list[float]] = []
    for index, inner_split in enumerate(inner):
        started = time.monotonic()
        print(
            f"  inner fold {index + 1}/{len(inner)} — selecting C over "
            f"{len(C_GRID)} value(s)"
        )
        features, labels, _ = _patch_matrix(
            inner_split["train"], cfg, featuriser, cache
        )
        accuracies.append(
            [
                _photograph_accuracy(
                    fit_probe(features, labels, c=candidate),
                    inner_split["val"],
                    cfg,
                    featuriser,
                    cache,
                )
                for candidate in C_GRID
            ]
        )
        seconds.append(time.monotonic() - started)

    mean_accuracy = [float(value) for value in np.mean(accuracies, axis=0)]
    selected = _select(C_GRID, mean_accuracy)

    write_selection_audit(
        arm_dir,
        repeat,
        fold,
        selection_group_ids=selection_group_ids,
        test_group_ids=test_group_ids,
        inner_k=cfg["evaluation"]["inner_k"],
        chosen={
            "C": float(selected),
            "c_grid": [float(candidate) for candidate in C_GRID],
            # Recorded per candidate, not just for the winner: at this size the
            # grid ties often, and a reader who cannot see the ties cannot tell
            # a setting that won from one that merely sorted first.
            "mean_accuracy_per_c": [
                {"C": float(candidate), "mean_accuracy": value}
                for candidate, value in zip(C_GRID, mean_accuracy, strict=True)
            ],
            "max_iter": MAX_ITER,
            "criterion": SELECTION_CRITERION,
            "shuffled_control": bool(shuffled_control),
            "permutation_seed": permutation_seed,
        },
        refit_group_count=len({entry["group"] for entry in split["train"]}),
    )

    print(f"  refitting on the whole training side at C = {selected}")
    started = time.monotonic()
    features, labels, _ = _patch_matrix(split["train"], cfg, featuriser, cache)
    model = fit_probe(features, labels, c=selected)
    seconds.append(time.monotonic() - started)

    # No checkpoint is written. The incumbent saves `model.keras` because a
    # fitted network is expensive to reproduce; a probe is a refit away from its
    # features, and a pickled estimator is a file that stops loading on the next
    # scikit-learn release. `fine_tune.json` is absent for the same kind of
    # reason: there is no backbone here that could have been unfrozen.
    write_fold_predictions(
        arm_dir,
        repeat=repeat,
        fold=fold,
        arm=arm,
        classes=cfg["classes"],
        records=_predict(model, split["test"], cfg, featuriser, cache),
        shuffled_control=shuffled_control,
        manifest_digest=fold_manifest["manifest_digest"],
        forced=forced,
    )
    # A "training" is one selection pass over an inner fold, plus the refit —
    # the same unit `train_fold` records, and the one a cost table contrasting
    # the arms has to be counting for both. It is not a count of fitted models:
    # an inner pass here fits the whole grid, as an inner pass there runs every
    # epoch. `evaluate` pairs this count with the seconds one-to-one.
    write_fold_cost(arm_dir, repeat, fold, len(seconds), seconds)
    return runtime


def _select(grid: Sequence[float], mean_accuracy: Sequence[float]) -> float:
    """The setting the inner folds chose, ties to the strongest regularisation.

    Ties are the common case at this size, not an edge: an inner validation side
    is a few dozen photographs, so several settings classify exactly the same
    ones and the criterion has to say which of them wins. The smallest ``C`` is
    the most regularised, which is the conservative reading of "the inner folds
    could not tell these apart".

    Written as the minimum of the winners rather than as the first ``argmax``,
    which agrees only while ``grid`` happens to be sorted and would then quietly
    stop matching the criterion the audit records.
    """
    best = max(mean_accuracy)
    return min(
        candidate
        for candidate, value in zip(grid, mean_accuracy, strict=True)
        if value == best
    )


def _patch_matrix(
    entries: Sequence[Mapping],
    cfg: Mapping,
    featuriser: Featuriser,
    cache: dict[str, np.ndarray] | None = None,
) -> tuple[np.ndarray, np.ndarray, list[int]]:
    """Featurise ``entries`` into patch rows, their labels, and their block sizes.

    A photograph contributes all of its patches, each carrying that photograph's
    label. Labels are repeated here, beside the rows they belong to, so the two
    cannot be assembled out of step by a caller that iterated differently.
    """
    if not entries:
        raise ValueError(
            "a probe was asked to featurise an empty set of photographs; a fold "
            "side with nothing in it cannot fit or score anything"
        )

    cache = {} if cache is None else cache
    blocks: list[np.ndarray] = []
    for entry in entries:
        block = cache.get(entry["path"])
        if block is None:
            block = np.asarray(featuriser(entry, cfg), dtype=np.float64)
            # Checked once per photograph per fold rather than on every cache
            # hit: the finiteness scan reads the whole block, and a fold asks
            # for the training side `inner_k` times over.
            _require_a_patch_block(entry, block)
            cache[entry["path"]] = block
        if blocks and block.shape[1] != blocks[0].shape[1]:
            raise ValueError(
                f"the featuriser returned {block.shape[1]} feature(s) for "
                f"{entry['path']} and {blocks[0].shape[1]} for the first "
                "photograph of this side; one fold is one feature space, and "
                "two widths cannot both be it"
            )
        blocks.append(block)

    counts = [len(block) for block in blocks]
    features = np.concatenate(blocks, axis=0)
    labels = np.concatenate(
        [
            np.full(count, int(entry["label"]), dtype=np.int64)
            for entry, count in zip(entries, counts, strict=True)
        ]
    )
    return features, labels, counts


def _require_a_patch_block(entry: Mapping, block: np.ndarray) -> None:
    """Refuse a featuriser's output that would be wrong in silence.

    Every way of breaking the contract here produces a file of the right shape
    under the right labels: an empty block averages to NaN, a one-dimensional
    block turns one photograph's features into as many patches as it has
    columns, and a NaN row poisons a mean that still writes four numbers.
    """
    where = entry["path"]
    if block.ndim != 2:
        raise ValueError(
            f"the featuriser returned a {block.ndim}-dimensional array for "
            f"{where}; a photograph's features are (n_patches, n_features), one "
            "row per patch"
        )
    if len(block) < 1:
        raise ValueError(
            f"the featuriser returned no patch for {where}; every photograph "
            "needs a block of at least one row, or its prediction is the mean "
            "of nothing"
        )
    if not np.isfinite(block).all():
        raise ValueError(
            f"the featuriser returned a non-finite value for {where}; it would "
            "reach the probe as a feature and leave every prediction of this "
            "fold undefined"
        )


def _predict(
    model,
    test_entries: Sequence[Mapping],
    cfg: Mapping,
    featuriser: Featuriser,
    cache: dict[str, np.ndarray] | None = None,
) -> list[dict]:
    """Predict the fold's test side, keeping the full distribution per photograph.

    The distribution and not the argmax: a group's prediction is the argmax of
    the mean of its photographs' distributions, and that cannot be recovered
    from per-photograph labels.

    One row per photograph, from several rows per photograph. The probe scores
    patches, and each photograph's block of patch distributions is averaged back
    into one here — the same rule `train._predict` applies to the incumbent's
    output, which is what makes a contrast between the two a statement about the
    method rather than about the aggregation (SPEC 0054).

    The mean rather than a vote over the patches, for SPEC 0053's reason:
    patches of one photograph share lighting, preparation and soil, so a patch
    is not a unit of evidence, and a vote would throw away the confidence the
    distribution carries.
    """
    features, _, counts = _patch_matrix(test_entries, cfg, featuriser, cache)
    probabilities = _full_distributions(model, features, len(cfg["classes"]))

    # Verified, not trusted. Every way of being wrong here is silent: a short
    # block list drops the last photographs, and a disagreeing total shifts
    # every block after the first onto a neighbour's patches. Both produce a
    # file of the right shape under the right labels.
    total = sum(counts)
    if len(probabilities) != total:
        raise ValueError(
            f"the probe returned {len(probabilities)} row(s) for "
            f"{len(test_entries)} photograph(s) whose features hold {total}; a "
            "mean taken over the wrong rows would mislabel every prediction in "
            "the fold"
        )

    records = []
    start = 0
    for entry, count in zip(test_entries, counts, strict=True):
        block = probabilities[start : start + count]
        start += count
        records.append(
            {
                "path": entry["path"],
                "group": entry["group"],
                "label": int(entry["label"]),
                "probabilities": [float(value) for value in block.mean(axis=0)],
            }
        )
    return records


def _full_distributions(model, features: np.ndarray, num_classes: int) -> np.ndarray:
    """`predict_proba`, widened to one column per configured class.

    `LogisticRegression` returns one column per class it was *fitted* on, in
    `classes_` order. A fold whose training side never held a class — which the
    fold generator makes unlikely and does not make impossible — therefore gets
    a narrower matrix back, and writing it as-is would slide every class's
    probability one column to the left: a wrong distribution under the right
    label, in a file of exactly the right shape.
    """
    fitted = np.asarray(model.classes_, dtype=np.int64)
    if fitted.min() < 0 or fitted.max() >= num_classes:
        raise ValueError(
            f"the probe was fitted on class labels {fitted.tolist()}, which are "
            f"not indices into the {num_classes} configured class(es); the fold "
            "manifest and the class list disagree"
        )

    scored = np.asarray(model.predict_proba(features), dtype=np.float64)
    if scored.shape[1] != len(fitted):
        raise ValueError(
            f"the probe returned {scored.shape[1]} column(s) for "
            f"{len(fitted)} fitted class(es)"
        )

    distributions = np.zeros((len(scored), num_classes), dtype=np.float64)
    distributions[:, fitted] = scored
    return distributions


def _photograph_accuracy(
    model,
    entries: Sequence[Mapping],
    cfg: Mapping,
    featuriser: Featuriser,
    cache: dict[str, np.ndarray] | None = None,
) -> float:
    """Share of ``entries`` the model gets right, one vote per photograph.

    Scored through :func:`_predict`, so selection reads the same aggregation the
    fold is finally reported under. Selecting on patch-level accuracy would
    choose the setting that is best at a quantity nothing reports, and at 25
    patches per photograph it would also weight the photographs by their dish
    size.
    """
    records = _predict(model, entries, cfg, featuriser, cache)
    correct = sum(
        int(np.argmax(record["probabilities"]) == record["label"])
        for record in records
    )
    return correct / len(records)
