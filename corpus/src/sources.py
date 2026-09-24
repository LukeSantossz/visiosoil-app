"""The curated source set, which *is* the allowlist.

ADR 0023 moved allowlist enforcement out of a provider's platform — where
`allowed_domains` used to enforce it — and into this code. So the manifest is not
a hint: a URL it does not list cannot be fetched, and the refusal happens before
the request rather than as a filter on the result. Filtering afterwards would
mean the page had already been read.

Curated here means a committed list of source URLs, not a folder of PDFs. The
property wanted is that no page the build did not choose reaches the model, and a
manifest gives that while also recording, per source, the digest of what was
actually fetched — so a source that changes under us is visible rather than
silent.

A PDF source may name the passage it contributes, as a page range beside its URL.
Choosing the passage is curation, the same reviewed act as choosing the source,
and it is what makes an extension document usable at all: its first pages are a
cover, a catalogue card and a table of contents.
"""

from __future__ import annotations

import hashlib
import io
import json
import re
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from typing import Callable, Iterable

from pypdf import PdfReader
from pypdf.errors import DependencyError, PyPdfError

PASSAGE_CHAR_LIMIT = 6000
"""How much of one document the model reads. The client cuts at this length, so
a PDF passage longer than it is refused at fetch rather than cut there without a
word — the first probe run read nothing past a title, the author affiliations and
an abstract because of that silent cut. HTML sources are still cut, since no
passage can be named for them yet."""

PDF_SIGNATURE = b"%PDF-"
"""What makes a body a PDF. Not the URL's suffix and not `Content-Type`, which
institutional repositories set inconsistently."""

PDF_SIGNATURE_WINDOW = 1024
"""How far into a body readers look for the signature. A body carrying it
anywhere in that window is kept as bytes, so one that does not open with it is
refused rather than decoded into noise that passes for prose."""


class SourceNotAllowed(Exception):
    """A URL the manifest does not list."""


class SourceFetchError(Exception):
    """A listed source that could not be read, or that carried no text.

    Fatal by design: a cell citing a source that could not be read would ship a
    citation pointing at nothing.
    """


@dataclass(frozen=True)
class SourceEntry:
    """One curated source, as the manifest lists it."""

    url: str
    title: str
    publisher: str | None
    tier: int | None
    pages: tuple[int, int] | None = None
    """Physical pages of a PDF, 1-based and inclusive — page 1 is the cover, not
    the page printed "1"."""


@dataclass(frozen=True)
class FetchedSource:
    """A source that was read, with the digest of what was read."""

    url: str
    title: str
    publisher: str | None
    tier: int | None
    text: str
    digest: str
    pages: tuple[int, int] | None = None


class SourceManifest:
    """The allowlist, loaded from `corpus/sources/*.manifest.json`."""

    def __init__(self, entries: Iterable[SourceEntry]) -> None:
        self._by_url = {entry.url: entry for entry in entries}
        if not self._by_url:
            raise ValueError("a source manifest with no sources cannot ground a cell")

    @classmethod
    def load(cls, path: Path) -> "SourceManifest":
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        entries = []
        for index, item in enumerate(raw.get("sources", [])):
            url = item.get("url")
            if not url:
                raise ValueError(f"source {index} in {path} has no url")
            entries.append(
                SourceEntry(
                    url=url,
                    title=item.get("title") or url,
                    publisher=item.get("publisher"),
                    tier=item.get("tier"),
                    pages=_page_range(item.get("pages"), index=index, path=path),
                )
            )
        return cls(entries)

    @property
    def entries(self) -> list[SourceEntry]:
        return list(self._by_url.values())

    def entry_for(self, url: str) -> SourceEntry:
        """The entry for [url], or [SourceNotAllowed]."""
        entry = self._by_url.get(url)
        if entry is None:
            raise SourceNotAllowed(
                f"{url} is not in the source manifest; the manifest is the "
                f"allowlist, so a source is added there before it is read"
            )
        return entry


def _page_range(raw: object, *, index: int, path: Path) -> tuple[int, int] | None:
    """The `pages` of manifest entry [index], refused unless it is a range.

    Checked at load, before anything is fetched: a malformed range is a manifest
    error, and the manifest is the reviewed half.
    """
    if raw is None:
        return None
    if (
        not isinstance(raw, list)
        or len(raw) != 2
        # `bool` is an `int` in Python, and `[true, 2]` is not a page range.
        or not all(
            isinstance(page, int) and not isinstance(page, bool) for page in raw
        )
        or raw[0] < 1
        or raw[0] > raw[1]
    ):
        raise ValueError(
            f"source {index} in {path} has pages {raw!r}; pages is "
            f"[first, last], two physical page numbers from 1 with first <= last"
        )
    return raw[0], raw[1]


Transport = Callable[[str], str | bytes]
"""Returns a page as decoded `str`, or a PDF as its undecoded `bytes`."""


def fetch_sources(
    manifest: SourceManifest,
    *,
    transport: Transport,
) -> list[FetchedSource]:
    """Reads every source the manifest lists, in order.

    [transport] is injected so the whole pipeline is testable without a network.
    """
    fetched = []
    for entry in manifest.entries:
        # Goes through `entry_for` rather than trusting the loop, so the
        # allowlist is enforced on the one path that fetches.
        allowed = manifest.entry_for(entry.url)
        try:
            body = transport(allowed.url)
        except Exception as error:  # noqa: BLE001 - re-raised with the url named
            raise SourceFetchError(
                f"{allowed.url} could not be read: {error}"
            ) from error
        text = _passage_text(allowed, body)
        if not text.strip():
            raise SourceFetchError(
                f"{allowed.url} carried no readable text; a cell cannot cite it"
            )
        fetched.append(
            FetchedSource(
                url=allowed.url,
                title=allowed.title,
                publisher=allowed.publisher,
                tier=allowed.tier,
                text=text,
                digest=hashlib.sha256(text.encode("utf-8")).hexdigest(),
                pages=allowed.pages,
            )
        )
    return fetched


def _passage_text(entry: SourceEntry, body: str | bytes) -> str:
    """The text [entry] contributes, from the [body] its transport returned."""
    if isinstance(body, str):
        if entry.pages is not None:
            raise SourceFetchError(
                f"{entry.url} names pages {list(entry.pages)} but is not a PDF; "
                f"the manifest believes something about this source that is not "
                f"true"
            )
        return extract_text(body)
    if not body.startswith(PDF_SIGNATURE):
        raise SourceFetchError(
            f"{entry.url} returned bytes that do not open with {PDF_SIGNATURE!r}; "
            f"nothing here reads them"
        )
    text = extract_pdf_text(body, entry.pages, url=entry.url)
    if len(text) > PASSAGE_CHAR_LIMIT:
        raise SourceFetchError(
            f"{entry.url} yields a passage of {len(text)} characters, above the "
            f"{PASSAGE_CHAR_LIMIT} the model reads; name or narrow its pages in "
            f"the manifest rather than let the rest be cut"
        )
    return text


def extract_pdf_text(
    body: bytes, pages: tuple[int, int] | None, *, url: str
) -> str:
    """The text on [pages] of the PDF [body], whitespace collapsed.

    [pages] is inclusive and 1-based; `None` reads the whole document. A range
    past the last page is refused rather than clipped, since clipping would read
    a passage the curator did not choose.
    """
    try:
        reader = PdfReader(io.BytesIO(body))
        count = len(reader.pages)
        first, last = pages or (1, count)
        if last > count:
            raise SourceFetchError(
                f"{url} names pages {first}-{last} and has {count}; the manifest "
                f"points past the end of the document"
            )
        text = " ".join(
            reader.pages[number - 1].extract_text() or ""
            for number in range(first, last + 1)
        )
    # `DependencyError` is what an AES-encrypted file raises, and it is not a
    # `PyPdfError`, so naming only the latter let it escape without the URL.
    except (PyPdfError, DependencyError) as error:
        raise SourceFetchError(f"{url} is not a readable PDF: {error}") from error
    return re.sub(r"\s+", " ", text).strip()


class _TextExtractor(HTMLParser):
    """Keeps text, drops markup, and drops what is never prose."""

    _SKIP = {"script", "style", "noscript", "template"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._parts: list[str] = []
        self._skipping = 0

    def handle_starttag(self, tag, attrs):
        if tag in self._SKIP:
            self._skipping += 1

    def handle_endtag(self, tag):
        if tag in self._SKIP and self._skipping:
            self._skipping -= 1

    def handle_data(self, data):
        if not self._skipping:
            self._parts.append(data)

    @property
    def text(self) -> str:
        joined = " ".join(part.strip() for part in self._parts if part.strip())
        return re.sub(r"\s+", " ", joined).strip()


def extract_text(html: str) -> str:
    """The readable text of [html].

    Deliberately simple: the sources are institutional documents, not
    applications, and a dependency that renders JavaScript would be a dependency
    that runs a page's code — which is precisely what §10 refuses.
    """
    parser = _TextExtractor()
    parser.feed(html)
    parser.close()
    return parser.text
