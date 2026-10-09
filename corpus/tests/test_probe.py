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
