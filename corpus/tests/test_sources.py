"""The curated manifest *is* the allowlist.

A source the manifest does not list is refused before it is fetched, not fetched
and filtered afterwards. The difference matters: filtering afterwards means the
page was already retrieved, and ADR 0023 moved allowlist enforcement out of a
provider's platform and into this code, so this is where it has to hold.
"""

import json

import pytest

from src.sources import (
    SourceFetchError,
    SourceManifest,
    SourceNotAllowed,
    fetch_sources,
)


def manifest(tmp_path, entries):
    path = tmp_path / "substance.manifest.json"
    path.write_text(json.dumps({"sources": entries}), encoding="utf-8")
    return SourceManifest.load(path)


def entry(url, title="Fonte", publisher="Embrapa", tier=1):
    return {"url": url, "title": title, "publisher": publisher, "tier": tier}


def test_a_source_outside_the_manifest_is_refused(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a")])

    with pytest.raises(SourceNotAllowed) as excinfo:
        allowed.entry_for("https://elsewhere.invalid/x")

    assert "elsewhere.invalid" in str(excinfo.value)


def test_a_listed_source_resolves_to_its_entry(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a", title="A")])

    assert allowed.entry_for("https://example.org/a").title == "A"


def test_the_manifest_records_a_digest_for_what_was_fetched(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a")])

    def transport(url):
        assert url == "https://example.org/a"
        return "<html><body><p>Texto da fonte.</p></body></html>"

    fetched = fetch_sources(allowed, transport=transport)

    assert len(fetched) == 1
    assert fetched[0].text == "Texto da fonte."
    # A source that changes under us has to be visible rather than silent, so the
    # run manifest carries the digest of what was actually read.
    assert len(fetched[0].digest) == 64
    assert fetched[0].digest == fetch_sources(allowed, transport=transport)[0].digest


def test_an_unreachable_source_fails_the_build(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a")])

    def transport(url):
        raise OSError("connection refused")

    # A cell citing a source that could not be read must not be produced with a
    # citation pointing at nothing.
    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=transport)

    assert "https://example.org/a" in str(excinfo.value)


def test_an_empty_document_fails_the_build(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a")])

    with pytest.raises(SourceFetchError):
        fetch_sources(allowed, transport=lambda url: "<html><body></body></html>")


def test_extraction_drops_markup_and_scripts(tmp_path):
    allowed = manifest(tmp_path, [entry("https://example.org/a")])
    html = (
        "<html><head><script>ignore()</script><style>p{}</style></head>"
        "<body><h1>Título</h1><p>Primeiro.</p><p>Segundo.</p></body></html>"
    )

    fetched = fetch_sources(allowed, transport=lambda url: html)

    assert "ignore()" not in fetched[0].text
    assert "p{}" not in fetched[0].text
    assert "Título" in fetched[0].text
    assert "Primeiro." in fetched[0].text


def test_a_manifest_entry_without_a_url_is_refused(tmp_path):
    path = tmp_path / "substance.manifest.json"
    path.write_text(json.dumps({"sources": [{"title": "sem url"}]}), encoding="utf-8")

    with pytest.raises(ValueError):
        SourceManifest.load(path)
