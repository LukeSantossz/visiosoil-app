"""Live search for the unit overlays, filtered by the source policy of §8.1.

The Developer's 2026-09-17 decision was hybrid: the substance layer is curated,
because that is where quality decides everything and the source set is small and
well known; the 27 unit overlays, which only have to find a state agency's page,
may search.

**The two halves enforce the allowlist differently because they face different
risks.** `sources.py` refuses any URL its manifest does not list, because a
substance cell is where a poisoned page would do real damage. Here the search
returns whatever it returns and this module drops what §8.1 does not admit —
before anything is fetched, so a page outside the policy is never read at all.

ADR 0023 is why this code exists: it moved allowlist enforcement off a provider's
platform, where `allowed_domains` used to do it, and into this repository.
"""

from __future__ import annotations

import json
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Callable

Transport = Callable[[str], list[tuple[str, str]]]
"""Takes a query and returns `(url, title)` pairs. Injected so every test here
runs without a network."""


@dataclass(frozen=True)
class AllowedDomain:
    """One entry of the allowlist, with the tier §8.1 gives it."""

    domain: str
    tier: int
    note: str = ""


@dataclass(frozen=True)
class SearchResult:
    url: str
    title: str
    tier: int


ALLOWLIST: tuple[AllowedDomain, ...] = (
    # Tier 1 — Brazilian federal research and extension, official statistics.
    AllowedDomain("gov.br", 1, "every federal domain, including MAPA and ANA"),
    AllowedDomain("embrapa.br", 1),
    AllowedDomain("ibge.gov.br", 1),
    # Tier 2 — state extension services and state agencies. `*.gov.br` already
    # admits these at tier 1 by suffix, so they are listed explicitly *before* it
    # is consulted, to earn the tier the policy actually gives them.
    AllowedDomain("emater.mg.gov.br", 2),
    AllowedDomain("emater.rs.gov.br", 2),
    AllowedDomain("iac.sp.gov.br", 2),
    AllowedDomain("epagri.sc.gov.br", 2),
    AllowedDomain("iapar.br", 2),
    AllowedDomain("emparn.rn.gov.br", 2),
    AllowedDomain("epamig.br", 2),
    AllowedDomain("incaper.es.gov.br", 2),
    AllowedDomain("pesagro.rj.gov.br", 2),
    # Tier 3 — universities and peer-reviewed literature.
    AllowedDomain("scielo.br", 3),
    AllowedDomain("usp.br", 3),
    AllowedDomain("ufv.br", 3),
    AllowedDomain("ufrgs.br", 3),
    AllowedDomain("unesp.br", 3),
    AllowedDomain("ufla.br", 3),
    AllowedDomain("ufsm.br", 3),
    AllowedDomain("unicamp.br", 3),
    # Tier 4 — international institutional bodies. §8.1 lets these support a
    # claim but never carry one alone.
    AllowedDomain("fao.org", 4),
    AllowedDomain("isric.org", 4),
    AllowedDomain("usda.gov", 4),
)

_STATE_AGENCIES = tuple(e for e in ALLOWLIST if e.tier == 2)
"""Consulted before the tier-1 suffixes, since most end in `.gov.br` and would
otherwise be promoted to tier 1 by a broader entry."""

FEDERATIVE_UNITS = (
    "ac", "al", "am", "ap", "ba", "ce", "df", "es", "go", "ma", "mg", "ms",
    "mt", "pa", "pb", "pe", "pi", "pr", "rj", "rn", "ro", "rr", "rs", "sc",
    "se", "sp", "to",
)
"""The 27 two-letter codes `.gov.br` gives the states and the Federal District.

The explicit tier-2 list above names nine agencies, and the unit overlays are
keyed by all 27 units, so the other eighteen states matched the `gov.br` entry
and were returned as **tier 1** — a state extension page presented as federal
evidence, which §8.2 then reads as stronger than it is.

The separator is structural rather than a list somebody has to keep complete:
`.gov.br` delegates state and municipal government under `<org>.<uf>.gov.br`,
so the label immediately before `gov.br` decides it. **The price is stated**:
this also catches municipal domains, which §8.1 does not name at all. Tier 2
over-credits a municipality slightly; tier 1 misrepresented an entire state.
"""


def _is_state_gov_br(host: str) -> bool:
    """Whether [host] sits under `<uf>.gov.br` rather than federal `gov.br`."""
    labels = host.lower().rstrip(".").split(".")
    if len(labels) < 3 or labels[-2:] != ["gov", "br"]:
        return False
    return labels[-3] in FEDERATIVE_UNITS


def _is_within(host: str, domain: str) -> bool:
    """Whether [host] is [domain] or a subdomain of it.

    The boundary is a **label**, not a string: a suffix match would admit
    `notembrapa.br`, and a prefix match would admit `embrapa.br.evil.example`.
    """
    host = host.lower().rstrip(".")
    domain = domain.lower()
    return host == domain or host.endswith("." + domain)


def tier_for_domain(host: str) -> int | None:
    """The tier §8.1 gives [host], or null when the policy does not admit it."""
    for entry in _STATE_AGENCIES:
        if _is_within(host, entry.domain):
            return entry.tier
    if _is_state_gov_br(host):
        return 2
    for entry in ALLOWLIST:
        if entry.tier != 2 and _is_within(host, entry.domain):
            return entry.tier
    return None


def duckduckgo_transport(query: str) -> list[tuple[str, str]]:
    """The production transport. Used by the build, never by a test.

    DuckDuckGo's instant-answer endpoint rather than a scraped results page: it
    returns JSON, it has no key, and it does not depend on a page layout that
    changes without notice. It returns fewer results than a full search, which is
    acceptable for a lookup whose target is one agency's own page.
    """
    url = "https://api.duckduckgo.com/?" + urllib.parse.urlencode(
        {"q": query, "format": "json", "no_html": "1", "no_redirect": "1"}
    )
    request = urllib.request.Request(
        url, headers={"User-Agent": "visiosoil-corpus-build/1.0"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:  # noqa: S310
        payload = json.loads(response.read().decode("utf-8"))

    found: list[tuple[str, str]] = []
    for topic in payload.get("RelatedTopics", []):
        for item in topic.get("Topics", [topic]):
            first = item.get("FirstURL")
            if first:
                found.append((first, item.get("Text", "")))
    if payload.get("AbstractURL"):
        found.insert(0, (payload["AbstractURL"], payload.get("Heading", "")))
    return found


class WebSearch:
    """Search, with §8.1 applied to the results before anything is fetched."""

    def __init__(self, *, transport: Transport | None = None) -> None:
        self._transport = transport or duckduckgo_transport

    def find(self, query: str, *, limit: int = 8) -> list[SearchResult]:
        """The admitted results for [query], in the order the engine gave them.

        A transport failure propagates: a search that silently returned nothing
        would make an overlay cell abstain for a reason nobody could see.
        """
        if limit <= 0:
            # The bound below is checked after a result is appended, so a limit
            # of zero returned one.
            return []

        seen: set[str] = set()
        results: list[SearchResult] = []
        for url, title in self._transport(query):
            if url in seen:
                continue
            seen.add(url)
            host = urllib.parse.urlparse(url).hostname or ""
            tier = tier_for_domain(host)
            if tier is None:
                continue
            results.append(SearchResult(url=url, title=title, tier=tier))
            if len(results) >= limit:
                break
        return results
