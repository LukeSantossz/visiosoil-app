"""A distance guard in the descriptor space the released regression scores in
(SPEC 0176).

Fitted on one training side's patch rows: the standardisation `fit_probe`
fits, one centroid per class in that space, and one variance per feature,
pooled within class. A patch's distance is a diagonal Mahalanobis distance to
its nearest centroid, divided by the feature count under the root so 1.0 is
one pooled standard deviation per feature:

    sqrt( mean_j ( (z_j - mu_c,j)^2 / sigma^2_j ) )

A photograph's score is the mean of its patches' distances, as the app
aggregates its probabilities. Four centroids and one variance vector: the
whole guard is 5 x 26 floats beside the scaler the contract already carries.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from sklearn.preprocessing import StandardScaler


@dataclass(frozen=True)
class Guard:
    """One fitted guard: the scaler's statistics, the class centroids in the
    standardised space, and the pooled variance per feature."""

    mean: np.ndarray
    scale: np.ndarray
    centroids: np.ndarray
    variance: np.ndarray


def fit_guard(features, labels, *, classes: int) -> Guard:
    """Fit the guard on a training side's patch rows and their labels.

    The scaler is a default `StandardScaler`, which is the transform
    `fit_probe`'s standardise step fits on the same rows. The variance divides
    the pooled within-class sum of squares by the rows less the classes, the
    unbiased pooled estimate.
    """
    features = np.asarray(features, dtype=np.float64)
    labels = np.asarray(labels)
    absent = [index for index in range(classes) if not np.any(labels == index)]
    if absent:
        raise ValueError(
            f"the training side holds no patch of class index {absent}; a "
            "centroid cannot be the mean of nothing"
        )
    if len(features) <= classes:
        raise ValueError(
            f"{len(features)} patch row(s) for {classes} classes leave no degree "
            "of freedom for the pooled variance"
        )

    scaler = StandardScaler().fit(features)
    z = scaler.transform(features)
    centroids = np.stack([z[labels == index].mean(axis=0) for index in range(classes)])
    residual = z - centroids[labels]
    variance = (residual**2).sum(axis=0) / (len(z) - classes)
    flat = np.flatnonzero(variance <= 0.0)
    if flat.size:
        raise ValueError(
            f"feature(s) {flat.tolist()} have no within-class spread on this "
            "training side, so a distance along them is undefined"
        )
    return Guard(
        mean=scaler.mean_.copy(),
        scale=scaler.scale_.copy(),
        centroids=centroids,
        variance=variance,
    )


def patch_distances(guard: Guard, features) -> np.ndarray:
    """Each patch row's distance to its nearest class centroid."""
    z = (np.asarray(features, dtype=np.float64) - guard.mean) / guard.scale
    squared = (z[:, None, :] - guard.centroids[None, :, :]) ** 2 / guard.variance
    return np.sqrt(squared.mean(axis=2).min(axis=1))


def photograph_score(guard: Guard, block) -> float:
    """A photograph's score: the mean of its patches' distances."""
    return float(np.mean(patch_distances(guard, block)))
