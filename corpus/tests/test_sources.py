"""The curated manifest *is* the allowlist.

A source the manifest does not list is refused before it is fetched, not fetched
and filtered afterwards. The difference matters: filtering afterwards means the
page was already retrieved, and ADR 0023 moved allowlist enforcement out of a
provider's platform and into this code, so this is where it has to hold.
"""

import json

import pytest

from src.sources import (
    PASSAGE_CHAR_LIMIT,
    SourceFetchError,
    SourceManifest,
    SourceNotAllowed,
    fetch_sources,
)
from tests.pdf_documents import make_pdf


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


# --- The allowlist has to survive a redirect ---------------------------------


def test_the_production_transport_refuses_a_redirect(tmp_path):
    """A redirect is a second request, and the allowlist has to reach it.

    `urlopen` follows redirects by default and only the first URL was checked, so
    an allowlisted server that redirected to an internal or loopback address
    would have the build fetch that destination and feed its text to the
    pipeline. Refusing redirects outright is the smaller surface: a curated
    source that moved is a manifest entry to update, which is a reviewed act.
    """
    from src.llm import RedirectRefused, _NoRedirect

    handler = _NoRedirect()

    with pytest.raises(RedirectRefused) as excinfo:
        handler.redirect_request(
            None, None, 302, "Found", {}, "http://169.254.169.254/latest/meta-data"
        )

    assert "169.254.169.254" in str(excinfo.value)


def test_a_redirect_refusal_names_both_ends(tmp_path):
    from src.llm import RedirectRefused, _NoRedirect

    class Request:
        full_url = "https://www.scielo.br/a"

    with pytest.raises(RedirectRefused) as excinfo:
        _NoRedirect().redirect_request(
            Request(), None, 301, "Moved", {}, "https://elsewhere.invalid/x"
        )

    message = str(excinfo.value)
    assert "scielo.br" in message
    assert "elsewhere.invalid" in message


# --- A PDF source is read, and only the passage the manifest names -------------

PDF_URL = "https://example.org/sistema-de-producao.pdf"


def pdf_entry(pages=None):
    item = entry(PDF_URL)
    if pages is not None:
        item["pages"] = pages
    return item


def test_a_pdf_source_is_read_as_text(tmp_path):
    allowed = manifest(tmp_path, [pdf_entry()])
    pdf = make_pdf(["Solos argilosos oxídicos retêm fósforo."])

    fetched = fetch_sources(allowed, transport=lambda url: pdf)

    assert fetched[0].text == "Solos argilosos oxídicos retêm fósforo."


def test_a_pdf_passage_is_the_page_range_the_manifest_names(tmp_path):
    """An extension document opens with a cover, a catalogue card and a table of
    contents, so reading from page 1 feeds the model everything but guidance."""
    allowed = manifest(tmp_path, [pdf_entry(pages=[2, 3])])
    pdf = make_pdf(
        [
            "Capa e ficha catalográfica.",
            "Primeira página do trecho.",
            "Segunda página do trecho.",
            "Referências.",
        ]
    )

    fetched = fetch_sources(allowed, transport=lambda url: pdf)

    assert fetched[0].text == "Primeira página do trecho. Segunda página do trecho."
    assert fetched[0].pages == (2, 3)


def test_a_pdf_passage_longer_than_the_budget_is_refused(tmp_path):
    """The model reads PASSAGE_CHAR_LIMIT characters of a document. A passage
    longer than that used to be cut without a word; it is refused instead, so the
    fix is a narrower range in the manifest rather than a silent loss."""
    allowed = manifest(tmp_path, [pdf_entry(pages=[1, 1])])
    at_budget = make_pdf(["a" * PASSAGE_CHAR_LIMIT])
    over_budget = make_pdf(["a" * (PASSAGE_CHAR_LIMIT + 1)])

    assert len(fetch_sources(allowed, transport=lambda url: at_budget)[0].text) == (
        PASSAGE_CHAR_LIMIT
    )
    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=lambda url: over_budget)

    message = str(excinfo.value)
    assert PDF_URL in message
    assert str(PASSAGE_CHAR_LIMIT + 1) in message


def test_a_pdf_without_a_text_layer_fails_the_build(tmp_path):
    # A scanned document has pages and no text. Citing it would ship a citation
    # the model never read.
    allowed = manifest(tmp_path, [pdf_entry()])

    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=lambda url: make_pdf(["", ""]))

    assert PDF_URL in str(excinfo.value)


def test_an_unreadable_pdf_fails_the_build(tmp_path):
    allowed = manifest(tmp_path, [pdf_entry()])

    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=lambda url: b"%PDF-1.4\ntruncated")

    assert PDF_URL in str(excinfo.value)


def test_a_page_range_beyond_the_document_is_refused(tmp_path):
    allowed = manifest(tmp_path, [pdf_entry(pages=[2, 5])])
    pdf = make_pdf(["Um.", "Dois.", "Três."])

    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=lambda url: pdf)

    assert PDF_URL in str(excinfo.value)


def test_a_page_range_on_a_source_that_is_not_a_pdf_is_refused(tmp_path):
    """A range means the curator believed the source is a PDF. If it is not,
    that belief is wrong, and reading the whole page instead would hide it."""
    allowed = manifest(tmp_path, [pdf_entry(pages=[1, 1])])

    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(
            allowed, transport=lambda url: "<html><body><p>Texto.</p></body></html>"
        )

    assert PDF_URL in str(excinfo.value)


def test_a_body_in_bytes_that_is_not_a_pdf_is_refused(tmp_path):
    allowed = manifest(tmp_path, [pdf_entry()])

    with pytest.raises(SourceFetchError) as excinfo:
        fetch_sources(allowed, transport=lambda url: b"<html>binary?</html>")

    assert PDF_URL in str(excinfo.value)


@pytest.mark.parametrize(
    "pages",
    [[0, 2], [3, 1], [-1, 2], [1], [1, 2, 3], "1-2", [1.0, 2], [True, 2], {}],
)
def test_a_malformed_page_range_is_refused_at_load(tmp_path, pages):
    path = tmp_path / "substance.manifest.json"
    path.write_text(json.dumps({"sources": [pdf_entry(pages=pages)]}), encoding="utf-8")

    with pytest.raises(ValueError) as excinfo:
        SourceManifest.load(path)

    assert "pages" in str(excinfo.value)


def test_the_committed_substance_manifest_loads():
    """The manifest the probe reads by default parses under the schema, and the
    Developer's 2026-09-18 decision holds in it: the substance of the cell comes
    from tier 1, Embrapa's extension material."""
    from src.probe import DEFAULT_MANIFEST

    committed = SourceManifest.load(DEFAULT_MANIFEST)

    assert sum(1 for source in committed.entries if source.tier == 1) >= 2
