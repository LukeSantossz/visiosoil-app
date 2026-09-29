"""The checkpoint filename, declared once (SPEC 0047, SPEC 0084).

SPEC 0047 made one resolver the path every reader took. Its only reader was the
TFLite export, and SPEC 0084 removed both, so its three resolver criteria went
with them. Neither remaining test needs TensorFlow, which is itself one of the
criteria: resolving an artifact path is a question about a directory, and the
reporting layer answers it on machines where the training stack cannot be
installed.
"""

import ast
import re
from pathlib import Path

SRC = Path(__file__).resolve().parents[1] / "src"


def test_resolver_needs_no_tensorflow():
    """The module reaches no part of the training stack.

    Asserted over its imports rather than over the environment, so it holds in
    CI — where TensorFlow *is* installed and an import would succeed — as well
    as on a machine without it. An environment-dependent version of this test
    would pass in CI while the property was already broken.
    """
    tree = ast.parse((SRC / "model_paths.py").read_text(encoding="utf-8"))

    imported = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported.update(alias.name.split(".")[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported.add(node.module.split(".")[0])

    assert imported, "the module imports nothing, so this asserts nothing"
    assert not imported & {"tensorflow", "keras", "tf_keras"}


def test_the_checkpoint_filename_is_declared_once():
    """`train.py` saves through the constant, and no resolver is left over.

    The TFLite export was the only reader of a checkpoint, and SPEC 0084 removed
    it together with `find_model_checkpoint`. What #30 is about still holds on
    the writing side: a re-inlined filename would be a second source for the
    next reader to disagree with, and no behavioural test would see it.
    """
    import src.model_paths as model_paths

    assert not hasattr(model_paths, "find_model_checkpoint")

    source = (SRC / "train.py").read_text(encoding="utf-8")
    assert "CHECKPOINT_FILENAME" in source, "train.py does not use CHECKPOINT_FILENAME"

    # The literal filename, outside the module that declares it. A comment may
    # mention it; a path expression may not.
    code = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert not re.search(r'["\']model\.keras["\']', code), (
        "train.py repeats the checkpoint filename as a literal"
    )
    assert not re.search(r'["\']model\.h5["\']', code), (
        "train.py repeats the legacy checkpoint filename as a literal"
    )
