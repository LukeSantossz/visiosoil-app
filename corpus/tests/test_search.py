"""Live search for the unit overlays, filtered by the source policy.

The Developer's 2026-09-17 decision was hybrid: the substance layer is curated,
and the 27 unit overlays — which only have to find a state agency's page — may
search. That split is why this module exists and why `sources.py` refuses
anything the manifest does not list: **the two halves enforce the allowlist
differently because they face different risks.**

ADR 0023 moved allowlist enforcement off a provider's platform and into this
code, so a result whose domain is not admitted by §8.1 is dropped here, before it
is fetched — not graded and dropped later, which would mean it was already read.
"""

import pytest

from src.search import (
    ALLOWLIST,
    SearchResult,
    WebSearch,
    tier_for_domain,
)


def fake_transport(results):
    def transport(query):
        return list(results)

    return transport


def test_a_result_outside_the_allowlist_is_dropped():
    search = WebSearch(
        transport=fake_transport(
            [
                ("https://www.embrapa.br/a", "Embrapa"),
                ("https://blogdosolo.example/x", "Blog"),
            ]
        )
    )

    found = search.find("agência estadual BR-SP")

    assert [r.url for r in found] == ["https://www.embrapa.br/a"]


def test_a_dropped_result_is_never_returned_for_fetching():
    # The point of filtering here rather than after grading: a page outside the
    # policy is never read at all.
    search = WebSearch(transport=fake_transport([("https://x.invalid/a", "X")]))

    assert search.find("q") == []


def test_a_kept_result_carries_the_tier_its_domain_earns():
    search = WebSearch(
        transport=fake_transport(
            [
                ("https://www.embrapa.br/a", "Embrapa"),
                ("https://www.scielo.br/j/x", "SciELO"),
            ]
        )
    )

    found = search.find("q")

    assert [r.tier for r in found] == [1, 3]


def test_a_subdomain_of_an_admitted_domain_is_admitted():
    assert tier_for_domain("infoteca.cnptia.embrapa.br") == 1
    assert tier_for_domain("www.ibge.gov.br") == 1


def test_a_domain_that_merely_ends_with_an_admitted_one_is_not():
    # `notembrapa.br` is not a subdomain of `embrapa.br`, and a suffix match
    # would admit it. The boundary is a label, not a string.
    assert tier_for_domain("notembrapa.br") is None
    assert tier_for_domain("embrapa.br.evil.example") is None


def test_any_federal_gov_domain_is_tier_one():
    assert tier_for_domain("www.gov.br") == 1
    assert tier_for_domain("mapa.gov.br") == 1


def test_a_state_agency_domain_is_tier_two():
    assert tier_for_domain("www.emater.mg.gov.br") == 2
    assert tier_for_domain("www.iac.sp.gov.br") == 2


def test_a_university_domain_is_tier_three():
    assert tier_for_domain("esalq.usp.br") == 3
    assert tier_for_domain("www.ufv.br") == 3


def test_the_allowlist_admits_no_tier_beyond_the_policy():
    for entry in ALLOWLIST:
        assert entry.tier in (1, 2, 3, 4)


def test_results_are_deduplicated_by_url():
    search = WebSearch(
        transport=fake_transport(
            [("https://www.embrapa.br/a", "A"), ("https://www.embrapa.br/a", "A")]
        )
    )

    assert len(search.find("q")) == 1


def test_a_result_limit_is_honoured():
    search = WebSearch(
        transport=fake_transport(
            [(f"https://www.embrapa.br/{i}", str(i)) for i in range(10)]
        )
    )

    assert len(search.find("q", limit=3)) == 3


def test_a_transport_failure_is_loud():
    def failing(query):
        raise OSError("no network")

    with pytest.raises(OSError):
        WebSearch(transport=failing).find("q")


def test_a_search_result_is_a_value():
    result = SearchResult(url="https://www.embrapa.br/a", title="A", tier=1)

    assert result.url.endswith("/a")
    assert result.tier == 1
