"""The run manifest, and where an unreviewed cell is allowed to land.

ADR 0023 replaced ADR 0022's spend ledger with a run manifest, because the
question changed: not "was this affordable" but "can this be reproduced". A
corpus whose manifest does not reproduce is not a corpus.
"""

import json

import pytest

from src.cell import CellValidationError, validate_cell
from src.manifest import RunManifest
from src.probe import write_output
from src.sources import FetchedSource


def source(index=0):
    return FetchedSource(
        url=f"https://example.org/{index}",
        title=f"Fonte {index}",
        publisher="Embrapa",
        tier=1,
        text="Conteúdo.",
        digest=f"{index}" * 64,
    )


def cell():
    return {
        "status": "grounded",
        "disclaimer": "Orientação consultiva.",
        "tips": [{"text": "Uma dica.", "citations": [0]}],
        "sources": [
            {
                "title": "Fonte 0",
                "url": "https://example.org/0",
                "publisher": "Embrapa",
                "tier": 1,
                "accessedAt": "2026-09-17T00:00:00.000Z",
            }
        ],
        "limitations": [],
    }


def test_the_manifest_records_the_model_and_the_prompt_versions():
    manifest = RunManifest(
        key="Argilosa|tb_oxidic",
        model="qwen2.5:7b",
        model_digest="sha256:abc",
        prompt_versions={"transform": "1", "grade": "1", "generate": "1"},
        seed=1234,
        sources=[source()],
        attempts=1,
    )

    payload = manifest.to_json()

    assert payload["model"] == "qwen2.5:7b"
    assert payload["modelDigest"] == "sha256:abc"
    assert payload["promptVersions"]["generate"] == "1"


def test_the_manifest_records_the_seed():
    manifest = RunManifest(
        key="k",
        model="m",
        model_digest="d",
        prompt_versions={},
        seed=7,
        sources=[source()],
        attempts=1,
    )

    assert manifest.to_json()["seed"] == 7


def test_the_manifest_records_a_digest_per_source():
    manifest = RunManifest(
        key="k",
        model="m",
        model_digest="d",
        prompt_versions={},
        seed=1,
        sources=[source(0), source(1)],
        attempts=1,
    )

    digests = {s["url"]: s["digest"] for s in manifest.to_json()["sources"]}

    assert digests["https://example.org/0"] == "0" * 64
    assert digests["https://example.org/1"] == "1" * 64


def test_the_manifest_records_the_attempts():
    # A cell that abstained after two grounding rejections reads differently from
    # one that grounded first try, and the verdict should not hide which it was.
    manifest = RunManifest(
        key="k",
        model="m",
        model_digest="d",
        prompt_versions={},
        seed=1,
        sources=[source()],
        attempts=2,
    )

    assert manifest.to_json()["attempts"] == 2


def test_the_cell_is_written_to_out_not_to_assets(tmp_path):
    manifest = RunManifest(
        key="Argilosa|tb_oxidic",
        model="m",
        model_digest="d",
        prompt_versions={},
        seed=1,
        sources=[source()],
        attempts=1,
    )

    written = write_output(cell(), manifest, out_dir=tmp_path)

    # Unreviewed generated guidance must never land where the app loads reviewed
    # guidance from. The review gate is what moves it, and it is blocked.
    assert "assets" not in str(written.cell_path)
    assert written.cell_path.parent == tmp_path
    assert json.loads(written.cell_path.read_text(encoding="utf-8"))["status"] == "grounded"
    assert json.loads(written.manifest_path.read_text(encoding="utf-8"))["key"] == (
        "Argilosa|tb_oxidic"
    )


def test_the_produced_cell_matches_the_fixture_contract():
    # The app reads cells through one contract; a build that can emit a shape the
    # app rejects is a build that ships a broken release.
    validate_cell(cell(), source_count=1)


def test_a_cell_missing_a_disclaimer_fails_the_contract():
    broken = cell()
    broken["disclaimer"] = "   "

    with pytest.raises(CellValidationError):
        validate_cell(broken, source_count=1)


def test_a_cell_with_no_sources_but_tips_fails_the_contract():
    broken = cell()
    broken["sources"] = []

    with pytest.raises(CellValidationError):
        validate_cell(broken, source_count=0)


def test_the_run_manifest_records_the_page_range_its_digest_covers():
    """A digest of a passage is only readable beside the pages it covers, and the
    committed range can change between two runs of the same cell."""
    passage = FetchedSource(
        url="https://example.org/sistema.pdf",
        title="Sistema de Produção",
        publisher="Embrapa",
        tier=1,
        text="Trecho.",
        digest="a" * 64,
        pages=(12, 15),
    )
    manifest = RunManifest(
        key="k",
        model="m",
        model_digest="d",
        prompt_versions={},
        seed=1,
        sources=[passage, source(1)],
        attempts=1,
    )

    recorded = {s["url"]: s["pages"] for s in manifest.to_json()["sources"]}

    assert recorded["https://example.org/sistema.pdf"] == [12, 15]
    assert recorded["https://example.org/1"] is None
