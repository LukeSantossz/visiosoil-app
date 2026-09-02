"""Where a training writes its checkpoint, and how a reader finds it again.

Deliberately free of TensorFlow. Resolving an artifact path is a question about
a directory, not about a model, and the reporting layer has to answer it on a
machine where the training stack cannot be installed — the same property
`src.crossval` was built around.
"""

from __future__ import annotations

from pathlib import Path

#: What `train_fold` saves the refit model as, and the first thing a reader
#: looks for. Named here rather than repeated as a literal at each end, so the
#: writer and the reader cannot disagree about it.
CHECKPOINT_FILENAME = "model.keras"

#: The Keras 2 format. Nothing in this repository writes it; it is accepted so
#: that a checkpoint produced before the `.keras` format still loads. Carried
#: forward unchanged by SPEC 0047, which moves this resolution rather than
#: changing what it resolves.
LEGACY_CHECKPOINT_FILENAME = "model.h5"


def find_model_checkpoint(output_dir: Path | str) -> Path:
    """The model checkpoint in ``output_dir``, preferring the `.keras` format.

    Args:
        output_dir: The directory a training wrote its checkpoint into.

    Returns:
        The path to the checkpoint.

    Raises:
        FileNotFoundError: When neither format is present, naming both paths it
            tried. Both, because "not found" is ambiguous about which format was
            expected, and the caller reading the message is usually the person
            deciding whether the training ran at all.
    """
    output_dir = Path(output_dir)
    checkpoint = output_dir / CHECKPOINT_FILENAME
    legacy = output_dir / LEGACY_CHECKPOINT_FILENAME

    if checkpoint.exists():
        return checkpoint
    if legacy.exists():
        return legacy
    raise FileNotFoundError(
        f"Model checkpoint not found: tried {checkpoint} and {legacy}"
    )
