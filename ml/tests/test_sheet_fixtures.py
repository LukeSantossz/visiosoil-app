"""The synthetic A4-sheet scenes are what their generator writes (SPEC 0091).

`scripts/generate_sheet_fixtures.py` writes `test/fixtures/sheet/`, and the Dart
reader is graded against it. Comparing bytes here means a fixture edited by
hand, or a generator changed without regenerating, fails in CI rather than
leaving the Dart tests grading against scenes nothing can reproduce. The
generator avoids every transcendental function for exactly this reason, so the
bytes hold on an AVX-512 runner too.
"""

from __future__ import annotations

import json

import scripts.generate_sheet_fixtures as generator


def test_the_sheet_fixtures_regenerate(tmp_path):
    golden = generator.generate(tmp_path)

    for entry in golden["cases"]:
        committed = generator.FIXTURES_DIR / entry["file"]
        assert (tmp_path / entry["file"]).read_bytes() == committed.read_bytes(), (
            f"{entry['file']} is not what the generator writes; regenerate with "
            "`cd ml && python scripts/generate_sheet_fixtures.py`"
        )
    assert (tmp_path / "golden.json").read_text(encoding="utf-8") == (
        generator.FIXTURES_DIR / "golden.json"
    ).read_text(encoding="utf-8")


def test_the_golden_describes_its_own_expectations():
    """A cropped scene has a corner outside its frame, and a whole one has none."""
    golden = json.loads((generator.FIXTURES_DIR / "golden.json").read_text(encoding="utf-8"))
    expectations = {entry["name"]: entry["expected"] for entry in golden["cases"]}
    assert set(expectations.values()) == {"sheet", "cropped", "notFound"}

    for entry in golden["cases"]:
        if "corners" not in entry:
            continue
        inside = [
            0 <= x <= entry["width"] - 1 and 0 <= y <= entry["height"] - 1
            for x, y in entry["corners"]
        ]
        if entry["expected"] == "cropped":
            assert not all(inside), entry["name"]
        elif entry["expected"] == "sheet":
            assert all(inside), entry["name"]
