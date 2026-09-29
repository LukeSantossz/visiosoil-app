"""SPEC 0084: the TFLite export is gone, and nothing reaches for it.

ADR 0024 retired the conversion, SPEC 0082 made `src.release` the release, and
SPEC 0083 took the interpreter out of the app. The check is over source rather
than behaviour because a converter added back would pass every behavioural test
in this suite: nothing would run it.
"""

import re
from pathlib import Path

ML_ROOT = Path(__file__).resolve().parents[1]

#: A call into TensorFlow's converter, or a reach for the deleted module by
#: either of the names it was imported under.
EXPORT_REFERENCE = re.compile(r"\btf\.lite\b|\bsrc\.export\b|from \.export import")


def test_the_training_package_has_no_tflite_export():
    assert not (ML_ROOT / "src" / "export.py").exists()

    offenders = []
    for directory in ("src", "scripts"):
        for path in sorted((ML_ROOT / directory).rglob("*")):
            if path.suffix not in {".py", ".sh"} or "__pycache__" in path.parts:
                continue
            if EXPORT_REFERENCE.search(path.read_text(encoding="utf-8")):
                offenders.append(path.relative_to(ML_ROOT).as_posix())
    assert offenders == []

    makefile = (ML_ROOT / "Makefile").read_text(encoding="utf-8")
    assert not re.search(r"^export\s*:", makefile, re.MULTILINE)
