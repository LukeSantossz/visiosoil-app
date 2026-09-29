"""Where a training writes its checkpoint.

Deliberately free of TensorFlow. Resolving an artifact path is a question about
a directory, not about a model, and the reporting layer has to answer it on a
machine where the training stack cannot be installed — the same property
`src.crossval` was built around.

The TFLite export was the only reader of a checkpoint, and SPEC 0084 removed it
together with the resolver it called. The name stays declared here, so that the
next reader has one source to agree with.
"""

from __future__ import annotations

#: What `train_fold` saves the refit model as. Named here rather than repeated as
#: a literal where it is written, so a future reader and the writer cannot
#: disagree about it.
CHECKPOINT_FILENAME = "model.keras"
