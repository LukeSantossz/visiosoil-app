"""The probe's order: what it checks before it spends a model call."""

import pytest

from src import llm, pipeline, probe, sources


def test_the_probe_reads_the_digest_before_it_builds(monkeypatch, tmp_path):
    """A server that cannot name the model stops the run before the chain
    runs, rather than after it has built a cell it then discards (SPEC 0151)."""
    built = []

    def refuse(self):
        raise llm.ModelRefused("no digest")

    monkeypatch.setattr(sources, "fetch_sources", lambda manifest, transport: [])
    monkeypatch.setattr(llm.OllamaClient, "model_digest", refuse)
    monkeypatch.setattr(
        pipeline, "build_cell", lambda *args, **kwargs: built.append(args)
    )

    with pytest.raises(llm.ModelRefused):
        probe.main(["--cell", "Argilosa|tb_oxidic", "--out", str(tmp_path)])

    assert built == []
    assert list(tmp_path.iterdir()) == []


def test_the_probe_writes_the_outcomes_groundings(monkeypatch, tmp_path):
    """The manifest carries what the build recorded, and the cell does not
    (SPEC 0161)."""
    import json

    entry = {
        "attempt": 1,
        "tip": "Uma dica.",
        "supported": True,
        "quote": "trecho",
        "found": True,
    }
    cell = {
        "status": "abstained",
        "disclaimer": pipeline.ABSTENTION_DISCLAIMER,
        "tips": [],
        "sources": [],
        "limitations": [],
    }
    outcome = pipeline.BuildOutcome(
        key="Argilosa|tb_oxidic",
        queries=[],
        kept=[],
        cell=cell,
        attempts=1,
        groundings=[entry],
        coverage={"fósforo": ["https://example.org/0"]},
    )
    monkeypatch.setattr(sources, "fetch_sources", lambda manifest, transport: [])
    monkeypatch.setattr(llm.OllamaClient, "model_digest", lambda self: "d")
    monkeypatch.setattr(pipeline, "build_cell", lambda *args, **kwargs: outcome)

    probe.main(["--cell", "Argilosa|tb_oxidic", "--out", str(tmp_path)])

    manifest = json.loads(
        next(tmp_path.glob("*.manifest.json")).read_text(encoding="utf-8")
    )
    written_cell = json.loads(
        next(tmp_path.glob("*.cell.json")).read_text(encoding="utf-8")
    )
    assert manifest["groundings"] == [entry]
    assert manifest["coverage"] == {"fósforo": ["https://example.org/0"]}
    assert "groundings" not in written_cell
