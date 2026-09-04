"""The frozen-encoder arm of the E0 gate (SPEC 0054, from SPEC 0044).

MobileNetV2 with ImageNet weights, global-average-pooled to 1280 floats per
patch, with a linear probe over them. The backbone is the same one the incumbent
arm fine-tunes, and holding it fixed across the two is what makes the contrast
between them a statement about *fine-tuning versus a linear probe on frozen
features* rather than about two architectures at once.

Nothing here decides anything. The selection, the standardisation, the
aggregation back to one prediction per photograph and every fold artifact are
:func:`src.arms.probe.probe_fold`, shared with the descriptor arm; this module
contributes a featuriser and the cache that makes calling it twenty-five times
affordable.

**The cache is the acceptance criterion, not the optimisation.** The arm is 25
folds over the same 204 photographs, so recomputing 5,100 embeddings per fold
would spend almost all of the arm's cost re-deriving a deterministic function of
the pixels. It is keyed by the photograph's path, its rows are the patch grid in
grid order, and it carries the **manifest digest** — a store drawn from another
dataset version is refused by name rather than read, because embeddings served
from the wrong pixels are a result attributed to data that did not produce it,
and nothing downstream could detect it.

TensorFlow is imported on first use rather than at module import, the way
``src.dataset`` imports it and for the same reason: reading a cached feature,
checking a store's provenance and binding the arm all have to be possible on a
machine with no training stack. ``tests/test_encoder_arm.py`` asserts the
property holds.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Callable, Mapping, Sequence

import numpy as np

from ..manifest import dataset_root, manifest_digest, manifest_path

#: MobileNetV2's pooled feature width. A fact about the architecture, asserted
#: against the real backbone rather than enforced on every encoder: the store
#: records whatever width it was given, so a fake encoder in a test and the real
#: one cannot be mistaken for each other.
ENCODER_EMBEDDING_DIM = 1280

#: Where the cache lives, under the arm's own directory, so a re-run of the arm
#: reuses it and a run of another arm cannot read it.
CACHE_DIRNAME = "encoder_features"

#: The store's identity: what it was drawn from, and under what arithmetic.
CACHE_SIDECAR_FILENAME = "index.json"
CACHE_SCHEMA_VERSION = 1

#: How a patch is scaled before it reaches the weights, recorded in the store
#: because it is the one thing that can be wrong without being visible. Every
#: embedding of a store written under another convention has the right shape,
#: the right provenance and no meaning.
PREPROCESSING_CONVENTION = "divide_255_then_rescale_2_offset_-1"

#: Patches per forward pass. A photograph's whole grid is 25 patches at the
#: configured geometry, so this batches a photograph in one call; the cap is
#: here so that a larger dish cannot make one call's activations unbounded.
FORWARD_BATCH_PATCHES = 64

#: Suffix of the scratch file an entry is written to before it is renamed into
#: place. Named rather than inlined so a partially written entry is recognisable
#: on disk as one.
TEMPORARY_SUFFIX = ".tmp"

#: One MobileNetV2 per input size, per process. Building it loads 14 MB of
#: ImageNet weights and takes seconds; a fold asks for the encoder once per
#: photograph that missed the cache, so building per call would cost more than
#: the forward passes it exists to perform.
_BACKBONE_BY_INPUT_SIZE: dict[int, object] = {}


def _tensorflow():
    """Return the TensorFlow module, importing it on first use."""
    import tensorflow as tf

    return tf


def prepare_for_mobilenet_v2(patches: np.ndarray) -> np.ndarray:
    """Scale ``uint8`` patches into the range MobileNetV2's weights expect.

    Two steps, written out rather than folded into ``x / 127.5 - 1``, because
    they are the two the rest of this project performs and the point is that
    this path and the incumbent's are the same arithmetic:
    ``preprocess.normalize_mobilenet_v2`` divides by 255, and the
    ``Rescaling(2.0, offset=-1.0)`` layer ``model.build_model`` bakes in after
    the input maps [0, 1] to [-1, 1]. A patch therefore reaches these frozen
    weights exactly as it reaches the fine-tuned ones, which is the condition
    under which the two arms are contrasting fine-tuning against a probe rather
    than two preprocessings.

    It coincides with ``keras.applications.mobilenet_v2.preprocess_input``. That
    is a check on the convention, not the reason for it: this project's
    normalisation contract is declared in ``spec.json`` and asserted by
    ``tests/test_tflite_inference.py``, and following the exported contract is
    what keeps the arm comparable to the model that would ship.

    Getting this wrong is invisible: embeddings computed from [0, 1] pixels have
    the same shape, the same dtype and no meaning.
    """
    scaled = np.asarray(patches, dtype=np.float32) / 255.0
    return scaled * 2.0 - 1.0


def feature_cache_directory(arm_dir: Path | str) -> Path:
    """Where one arm's patch embeddings are cached."""
    return Path(arm_dir) / CACHE_DIRNAME


def feature_cache_path(arm_dir: Path | str, image_path: str) -> Path:
    """The cache entry holding one photograph's whole grid, in grid order.

    One file per photograph rather than one per patch: the row index *is* the
    patch index, so the key SPEC 0054 describes — the path and the patch index —
    is preserved while a fold reads 204 files instead of 5,100.

    Named by the digest of the path rather than by the path, because a dataset
    path carries separators and, on Windows, a drive letter and a length limit.
    The digest is a function of the path the fold manifest carries, verbatim, so
    a version reached by another absolute path misses the cache rather than
    hitting the wrong entry.
    """
    stem = hashlib.sha256(str(image_path).encode("utf-8")).hexdigest()
    return feature_cache_directory(arm_dir) / f"{stem}.npy"


def encoder_featuriser(
    arm_dir: Path | str,
    cfg: Mapping,
    *,
    encoder: Callable[[np.ndarray], np.ndarray] | None = None,
    digest: str | None = None,
) -> Callable[[Mapping, Mapping], np.ndarray]:
    """Return the featuriser :func:`src.arms.probe.probe_fold` calls.

    The returned callable takes one split entry and the configuration and
    returns a ``(n_patches, n_features)`` array — one row per patch, in the
    order the grid cuts them — which is the contract both arms are written
    against.

    Args:
        arm_dir: ``models/<version>/<arm>``. The cache lives under it, so every
            fold of the arm shares one store and a re-run reuses it.
        cfg: The resolved configuration, read for the patch size and for the
            dataset version whose manifest identifies the store.
        encoder: The forward pass, taking a ``(n, S, S, 3)`` float32 batch
            already in [-1, 1] and returning ``(n, width)``. Omitted, it is the
            frozen MobileNetV2, built on the first cache miss and not before: a
            fold whose photographs are all cached must not pay for loading
            weights it will not use.
        digest: The manifest digest to key the store by, for a caller that
            already holds one — ``fold_manifest["manifest_digest"]`` is the same
            value. Omitted, it is read from the configured dataset version.

    Raises:
        ValueError: If a store already under ``arm_dir`` was drawn from another
            manifest, cut under another patch geometry, or written under another
            preprocessing convention.
    """
    image_size = int(cfg["data"]["image_size"])
    store = _FeatureStore(
        arm_dir,
        digest=_configured_digest(cfg) if digest is None else digest,
        geometry=_patch_geometry_identity(cfg),
    )
    embed = _mobilenet_v2_encoder(image_size) if encoder is None else encoder

    def features(entry: Mapping, call_cfg: Mapping) -> np.ndarray:
        _require_one_patch_size(call_cfg, image_size)
        # The grid the configuration in force implies, without decoding
        # anything. It is also the gate: a photograph the patch grid refuses is
        # refused here, by the name `src.patches` gives it, before a file is
        # opened and before the cache is consulted.
        expected = _photograph_patch_count(entry, call_cfg)

        cached = store.read(entry["path"], expected)
        if cached is not None:
            return cached

        # The cut is reached through `src.dataset` rather than reimplemented
        # here. The resample, the EXIF transpose and the grid live there, and a
        # second implementation of the cut is the mixture ADR 0018 exists to
        # remove — which is why the private names are imported rather than
        # copied.
        from ..dataset import _measurement_of, _photograph_patches, photograph_scale

        measurement = _measurement_of(entry, photograph_scale(call_cfg))
        computed = _embed(_photograph_patches(entry, measurement, call_cfg), embed)
        store.write(entry["path"], computed)
        return computed

    return features


def encoder_probe_fold(
    cfg: Mapping,
    fold_manifest: Mapping,
    *,
    arm_dir: Path | str,
    arm: str,
    repeat: int,
    fold: int,
    shuffled_control: bool = False,
    verify: bool = True,
) -> dict:
    """Run one outer fold of the frozen-encoder arm, with ``train_fold``'s signature.

    A binding and nothing more: the featuriser is bound to ``arm_dir``, so every
    fold of the arm shares one cache, and everything else is
    :func:`src.arms.probe.probe_fold`. An arm that reimplemented the selection,
    the standardisation or the aggregation would differ from the arm it is
    contrasted against in more than its features, and a difference between them
    could not then be attributed to either.

    Imported inside the call rather than at module scope, so that reading the
    cache or the store's provenance never pulls in the shared trainer or what it
    depends on.
    """
    from .probe import probe_fold

    return probe_fold(
        cfg,
        fold_manifest,
        arm_dir=arm_dir,
        arm=arm,
        repeat=repeat,
        fold=fold,
        featuriser=encoder_featuriser(arm_dir, cfg),
        shuffled_control=shuffled_control,
        verify=verify,
    )


def _backbone(image_size: int):
    """The frozen MobileNetV2 for this input size, built once per process."""
    cached = _BACKBONE_BY_INPUT_SIZE.get(image_size)
    if cached is not None:
        return cached

    tf = _tensorflow()
    backbone = tf.keras.applications.MobileNetV2(
        input_shape=(image_size, image_size, 3),
        include_top=False,
        # The pooling is part of the representation being measured, not a
        # convenience: SPEC 0054's arm is the *global-average-pooled* embedding,
        # and letting the probe see the 5 x 5 x 1280 map instead would give it
        # spatial features the contrast was never registered over.
        pooling="avg",
        weights="imagenet",
    )
    backbone.trainable = False
    width = int(backbone.output_shape[-1])
    if width != ENCODER_EMBEDDING_DIM:
        # A post-condition of "MobileNetV2, global-average-pooled", checked once
        # per process. The arm SPEC 0054 registers is the 1280-d pooled
        # embedding; a backbone that pooled to another width would still fill a
        # feature matrix, and the cache would carry it as if it were this arm's.
        raise ValueError(
            f"the frozen backbone pools to {width} features and this arm is the "
            f"{ENCODER_EMBEDDING_DIM}-d MobileNetV2 embedding"
        )
    _BACKBONE_BY_INPUT_SIZE[image_size] = backbone
    return backbone


def _mobilenet_v2_encoder(image_size: int) -> Callable[[np.ndarray], np.ndarray]:
    """The default forward pass, deferring the backbone until it is needed."""

    def embed(batch: np.ndarray) -> np.ndarray:
        # `__call__` rather than `predict`: a batch is one photograph's grid,
        # and `predict` builds a dataset and a progress bar around it, which at
        # 5,100 batches costs more than the forward passes.
        return np.asarray(_backbone(image_size)(batch, training=False))

    return embed


def _embed(
    patches: Sequence[np.ndarray], encoder: Callable[[np.ndarray], np.ndarray]
) -> np.ndarray:
    """Embed one photograph's grid, in grid order, batching the forward pass."""
    blocks: list[np.ndarray] = []
    for start in range(0, len(patches), FORWARD_BATCH_PATCHES):
        batch = prepare_for_mobilenet_v2(
            np.stack(patches[start : start + FORWARD_BATCH_PATCHES])
        )
        block = np.asarray(encoder(batch), dtype=np.float32)
        if block.ndim != 2 or block.shape[0] != len(batch):
            raise ValueError(
                f"the encoder returned {block.shape} for a batch of "
                f"{len(batch)} patch(es); a featuriser owes the fold trainer one "
                "row per patch"
            )
        blocks.append(block)

    return np.concatenate(blocks, axis=0)


def _photograph_patch_count(entry: Mapping, cfg: Mapping) -> int:
    """How many patches this entry's grid holds, without decoding it.

    Reached through `src.dataset` so a photograph refused there is refused here,
    by the same name and before the cache is consulted.
    """
    from ..dataset import photograph_patch_counts

    return photograph_patch_counts([entry], cfg)[0]


def _configured_digest(cfg: Mapping) -> str:
    """The digest of the manifest the configured dataset version was listed in.

    :func:`manifest.manifest_digest` and not :func:`manifest.unmeasured_digest`.
    The two answer different questions, and only one of them identifies the
    pixels an embedding was computed from: `unmeasured_digest` deliberately
    blanks the four scale columns so that it is stable across the write
    `measure_scale.py` performs — and those columns are exactly what decides
    where a patch is cut. A cache keyed by it would survive a re-measurement
    that moves every patch of every photograph. `manifest_digest` is over the
    file's bytes, covers the measurement, and is the value the fold manifest
    already carries and `load_folds_for_config` already verifies, so the cache
    and the folds are refused by the same fact.
    """
    root = dataset_root(cfg["data"]["datasets_dir"], cfg["data"]["dataset_version"])
    path = manifest_path(root)
    if not path.exists():
        raise FileNotFoundError(
            f"no manifest at {path}, so the encoder feature cache cannot be "
            f"keyed to the data it would hold. The cache is refused rather than "
            f"written unkeyed: an embedding whose provenance is unknown cannot "
            f"be shown to belong to the photographs a result is reported over"
        )
    return manifest_digest(root)


def _patch_geometry_identity(cfg: Mapping) -> dict:
    """Everything outside the manifest that decides where a patch is cut.

    The manifest digest covers the *measurement* — the dish and the millimetres
    per pixel each photograph was read at — because those live in the manifest.
    It cannot cover the three values in `config.yaml` that move the grid over
    the same pixels, and a store keyed on the digest alone would go on serving
    embeddings of the old grid after any of them changed. The row-count check in
    :meth:`_FeatureStore.read` catches a change that alters how many patches a
    dish carries; these catch one that does not, which is the case that would
    otherwise pass silently.
    """
    return {
        "image_size": int(cfg["data"]["image_size"]),
        "canonical_mm_per_px": float(cfg["preprocessing"]["canonical_mm_per_px"]),
        "patch_stride_fraction": float(cfg["preprocessing"]["patch_stride_fraction"]),
    }


def _require_one_patch_size(cfg: Mapping, image_size: int) -> None:
    """Refuse a call whose grid is not the one the store and encoder were built for."""
    called_with = int(cfg["data"]["image_size"])
    if called_with != image_size:
        raise ValueError(
            f"this featuriser was built for data.image_size {image_size} and was "
            f"called with {called_with}. The frozen backbone is built for one "
            "input size and the cache is keyed to one grid; build a second "
            "featuriser rather than passing a second configuration"
        )


class _FeatureStore:
    """The on-disk embeddings of one arm, and the identity that makes them usable.

    Split from the featuriser because the two fail differently. A miss is
    ordinary and is answered by computing; a store that does not belong to this
    run is not a miss, and answering it by computing would silently write this
    version's embeddings beside another version's.
    """

    def __init__(self, arm_dir: Path | str, *, digest: str, geometry: Mapping):
        self._arm_dir = Path(arm_dir)
        self._directory = feature_cache_directory(arm_dir)
        self._sidecar_path = self._directory / CACHE_SIDECAR_FILENAME
        declared = {
            "schema_version": CACHE_SCHEMA_VERSION,
            "manifest_digest": digest,
            **geometry,
            "preprocessing": PREPROCESSING_CONVENTION,
            # Not known until the first entry is written. Recorded then, so a
            # store cannot come to hold two encoders' widths.
            "feature_width": None,
        }
        self._directory.mkdir(parents=True, exist_ok=True)
        if self._sidecar_path.exists():
            self._sidecar = self._read_sidecar()
            _require_store_agreement(self._sidecar_path, self._sidecar, declared)
        else:
            # Entries without a sidecar are entries whose provenance nothing
            # establishes — a store whose identity was deleted, or one a run
            # died before describing. Adopting them writes a sidecar claiming
            # this run's geometry over embeddings computed under some other one,
            # and `read` would then check only the row count, which a changed
            # canonical scale need not alter. The arm would train on embeddings
            # of soil it is no longer looking at, which is the exact failure the
            # store exists to refuse.
            orphans = sorted(self._directory.glob("*.npy"))
            if orphans:
                raise ValueError(
                    f"{self._directory} holds {len(orphans)} cached "
                    f"embedding(s) and no {CACHE_SIDECAR_FILENAME}, so nothing "
                    f"says what geometry they were computed under. Delete the "
                    f"directory and let the arm recompute them"
                )
            self._sidecar = declared
            _write_json_atomically(self._sidecar_path, declared)

    def read(self, image_path: str, expected_rows: int) -> np.ndarray | None:
        """One photograph's embeddings, or ``None`` when there is nothing to read.

        Everything that is not a complete array of the shape this grid implies
        is a miss: an absent file, a file whose header or data the writer never
        finished, and an array whose row count disagrees with the grid now in
        force. Recomputing is always safe — the embedding is a deterministic
        function of the pixels and the grid — and it is safer than trusting a
        file whose completeness nothing established.
        """
        path = feature_cache_path(self._arm_dir, image_path)
        if not path.exists():
            return None
        try:
            stored = np.load(path, allow_pickle=False)
        except (ValueError, OSError, EOFError):
            # A half-written entry: `np.load` reads the declared shape out of
            # the header and refuses when the data behind it is short.
            return None

        if stored.ndim != 2 or stored.shape[0] != expected_rows:
            return None
        width = self._sidecar.get("feature_width")
        if width is not None and stored.shape[1] != width:
            return None
        return np.ascontiguousarray(stored, dtype=np.float32)

    def write(self, image_path: str, features: np.ndarray) -> Path:
        """Record one photograph's embeddings, whole or not at all."""
        self._record_feature_width(int(features.shape[1]))
        path = feature_cache_path(self._arm_dir, image_path)
        _write_array_atomically(path, features)
        return path

    def _read_sidecar(self) -> dict:
        try:
            recorded = json.loads(self._sidecar_path.read_text(encoding="utf-8"))
        except (ValueError, OSError) as unreadable:
            raise ValueError(
                f"{self._sidecar_path} cannot be read, so the cache beside it "
                f"cannot be shown to belong to any dataset version: {unreadable}. "
                f"Delete {self._directory} and let the arm recompute it"
            ) from unreadable
        if not isinstance(recorded, dict):
            raise ValueError(
                f"{self._sidecar_path} does not record a cache identity, so the "
                f"embeddings beside it have no provenance. Delete "
                f"{self._directory} and let the arm recompute it"
            )
        return recorded

    def _record_feature_width(self, width: int) -> None:
        """Pin the store to one encoder's output width, on the first entry."""
        recorded = self._sidecar.get("feature_width")
        if recorded is None:
            self._sidecar["feature_width"] = width
            _write_json_atomically(self._sidecar_path, self._sidecar)
            return
        if recorded != width:
            raise ValueError(
                f"{self._directory} holds {recorded}-column embeddings and this "
                f"encoder produces {width}. Two encoders' features in one store "
                f"would be pooled into one feature matrix; delete the directory "
                f"to recompute it under the encoder in force"
            )


def _require_store_agreement(
    sidecar_path: Path, recorded: Mapping, declared: Mapping
) -> None:
    """Refuse a store this run did not produce, naming every disagreement.

    Every field in one message, the way `dataset._require_config_agreement`
    reports a fold manifest: the reader is deciding whether to delete a
    directory, and one list is the difference between one decision and four.
    """
    disagreements = [
        f"  - {field}: the cache was written under {recorded.get(field)!r}, this "
        f"run is {declared[field]!r}"
        for field in declared
        # The width is not part of the store's identity: it is unknown until the
        # first entry is written, and `_record_feature_width` refuses a second
        # encoder's width where that belongs, at the write.
        if field != "feature_width" and recorded.get(field) != declared[field]
    ]
    if disagreements:
        raise ValueError(
            f"{sidecar_path} does not describe this run:\n"
            + "\n".join(disagreements)
            + f"\nThe cache is refused rather than read: an embedding served "
            f"from another dataset version, another patch size or another "
            f"preprocessing has the right shape and no meaning, and nothing "
            f"downstream could detect it. Delete {sidecar_path.parent} to "
            f"recompute it."
        )


def _write_array_atomically(path: Path, array: np.ndarray) -> None:
    """Write ``array`` so that ``path`` never holds a partial one.

    The bytes are written to a scratch file, flushed to the device, and only
    then renamed over the destination — `os.replace` is atomic on both
    platforms this runs on. Without the fsync a crash can leave the rename
    committed and the data not, which is the one failure the rename is here to
    prevent; a scratch file left behind by a failure is removed, so a later run
    does not have to reason about it.
    """
    temporary = path.with_name(path.name + TEMPORARY_SUFFIX)
    try:
        with open(temporary, "wb") as handle:
            np.save(handle, array, allow_pickle=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def _write_json_atomically(path: Path, payload: Mapping) -> None:
    """The same guarantee for the sidecar, which is the store's identity."""
    temporary = path.with_name(path.name + TEMPORARY_SUFFIX)
    try:
        with open(temporary, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(dict(payload), handle, indent=2)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise
