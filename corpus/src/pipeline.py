"""The CRAG chain that builds one cell.

Four steps: transform the question into one query per management topic, grade
each document for relevance, generate a cited cell from what survived, and check
that every tip is actually supported by what it cites.

It is CRAG-shaped rather than Self-RAG-shaped for the reason
`llm-wiki/wiki/rag-auto-corretivo.md` records: **the grader is external and
light**, plug-and-play rather than a capability the generator has to be trained
into. That is what makes a 7-8 B local model adequate here, and it is why
dropping the graders would have measured prose quality and called it pipeline
feasibility.

The chain is a bounded sequence run once per cell, not a graph. ADR 0022 §20.4
refuses an orchestration framework for exactly this shape.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol

from src.cell import (
    CellValidationError,
    build_cell_payload,
    source_payload,
    validate_cell,
)
from src.keys import describe_key
from src.sources import FetchedSource

SUBSTANCE_DISCLAIMER = (
    "Orientação consultiva, baseada em fontes públicas citadas. "
    "Não substitui análise laboratorial nem avaliação técnica presencial."
)
"""The advisory stance is a decision this design took, not a sentence a model
improvises.

The first probe run wrote "podem não refletir orientações definitivas", which
hedges about the *sources* instead of stating what the feature is. A disclaimer
the model writes varies per cell and drifts per model, so the build sets it and
whatever the model offered is discarded."""

ABSTENTION_DISCLAIMER = (
    "Nenhuma fonte elegível sustentou uma orientação para esta combinação. "
    "Consulte a assistência técnica local."
)

MANAGEMENT_TOPICS = (
    "calagem",
    "fósforo",
    "potássio",
    "matéria orgânica",
    "água",
    "o que a classe de textura implica e o que não implica",
)
"""The topics the transform step writes one query for each of, in order.

Fixed here rather than left to the model: asked for "different angles", it
wrote three broad questions about fertility, and the phosphorus circular a
judge asked for was graded irrelevant to all of them (SPEC 0153)."""

TOPIC_LIMITATIONS = {
    "calagem": "As fontes consultadas não tratam de calagem.",
    "fósforo": "As fontes consultadas não tratam de fósforo.",
    "potássio": "As fontes consultadas não tratam de potássio.",
    "matéria orgânica": "As fontes consultadas não tratam de matéria orgânica.",
    "água": "As fontes consultadas não tratam do manejo da água.",
    "o que a classe de textura implica e o que não implica": (
        "As fontes consultadas não tratam do que a classe de textura implica "
        "e do que não implica."
    ),
}
"""The limitation a cell carries for a topic no kept source covers (SPEC 0162).

A fixed table rather than the model's words: what the sources leave out cannot
be quoted, so it cannot be grounded, and a limitation the build states from its
own grading is true by construction."""

OLD_SOURCE_YEARS = 10
"""A source more than this many years older than the build has its age
surfaced in `limitations` (research-agent.md §8.3, SPEC 0225)."""


def age_limitation(year: int) -> str:
    """The fixed sentence for a kept source published in [year].

    It states the age and nothing else: the build does not check that nothing
    newer contradicts the source. Its digits are a year, not an amount, and the
    number rule of SPEC 0160 reads tips, not limitations."""
    return f"Uma das fontes consultadas é de {year}, há mais de dez anos."


_NUMBER = re.compile(
    r"(?<!\w)(?<!\w-)\d+(?:[.,]\d+)?|[¼-¾⅐-⅟↉]"
)
"""A number: digits with an optional decimal part, not preceded by a word
character nor by a hyphen glued to one, or any Unicode fraction glyph. So "18",
"90%", "5,5", "-2%", "½", "⅜" and the "33" of "CT 33" are numbers, while "P2O5"
and "Mehlich-1" are names (SPEC 0160)."""

_NOT_A_NUMBER = re.compile(
    r"\bMehlich[\s-]?\d\b"
    r"|\b(?:argil|minera)\w*\s+(?:do\s+tipo\s+)?[12]:1(?![\d:]|[.,]\d)",
    re.IGNORECASE,
)
"""Names and ratios that carry digits without stating an amount: the Mehlich
extractant, spaced or hyphenated, and a clay mineral's layer ratio, "argilas
1:1" or "minerais do tipo 2:1", which is what clay activity turns on. A ratio
outside that context, such as a mixing ratio, stays a number (SPEC 0160)."""


def states_a_number(text: str) -> bool:
    """Whether [text] states a number, which a tip never does (SPEC 0160).

    The advisory stance forbids doses and critical levels, and the generate
    prompt asks for the direction a source's numbers show instead. A prompt rule
    is one the model can ignore, so the build checks it.
    """
    return _NUMBER.search(_NOT_A_NUMBER.sub("", text)) is not None


class LLMClient(Protocol):
    """What the pipeline needs of a model.

    A protocol rather than a class so a fake satisfies it structurally, and so
    the funded rebuild ADR 0023 anticipates swaps the implementation without
    touching the chain.
    """

    def transform_query(self, question: str, *, topic: str) -> str: ...

    def grade_document(self, query: str, document: FetchedSource) -> bool: ...

    def generate_cell(
        self, question: str, documents: list[FetchedSource]
    ) -> dict[str, Any]: ...

    def ground(self, tip_text: str, cited_texts: list[str]) -> "Grounding": ...


@dataclass(frozen=True)
class Grounding:
    """One grounding check: its verdict and the passage the model quoted for it.

    [supported] is the verdict the build acts on. [quote] and [found] are kept
    so whoever judges a run can read which passage held a tip, or why it did
    not (SPEC 0161).
    """

    supported: bool
    quote: str
    found: bool


@dataclass
class BuildOutcome:
    """What one cell build produced, and enough of how to make it readable."""

    key: str
    queries: list[str]
    kept: list[FetchedSource]
    cell: dict[str, Any]
    attempts: int
    rejections: list[str] = field(default_factory=list)
    groundings: list[dict[str, Any]] = field(default_factory=list)
    """Every grounding check, rejected attempts included, in order."""
    coverage: dict[str, list[str]] = field(default_factory=dict)
    """Each management topic, mapped to the URLs graded relevant to it."""


def build_cell(
    key: str,
    sources: list[FetchedSource],
    *,
    client: LLMClient,
    max_attempts: int = 2,
    now: datetime | None = None,
) -> BuildOutcome:
    """Builds the cell for [key] from [sources].

    [max_attempts] bounds the generate-and-check loop, so a model that will not
    ground cannot make the build spin. Exhausting it abstains, which is an answer
    the composition rule already defines rather than a failure.
    """
    built_at = now or datetime.now(timezone.utc)
    accessed_at = built_at.isoformat().replace("+00:00", "Z")
    # The model is told what the key means, never the key itself (SPEC 0152).
    question = describe_key(key)
    queries = [
        client.transform_query(question, topic=topic) for topic in MANAGEMENT_TOPICS
    ]
    _require_queries(queries)

    # Every source is graded against every topic, so the build knows which
    # topics its sources cover; stopping at the first relevant topic would leave
    # the rest unknown (SPEC 0162).
    coverage: dict[str, list[str]] = {topic: [] for topic in MANAGEMENT_TOPICS}
    kept: list[FetchedSource] = []
    for document in sources:
        covered = [
            topic
            for topic, query in zip(MANAGEMENT_TOPICS, queries)
            if client.grade_document(query, document)
        ]
        if covered:
            kept.append(document)
        for topic in covered:
            coverage[topic].append(document.url)
    limitations = [
        TOPIC_LIMITATIONS[topic] for topic in MANAGEMENT_TOPICS if not coverage[topic]
    ] + [
        age_limitation(document.year)
        for document in kept
        if document.year is not None
        and built_at.year - document.year > OLD_SOURCE_YEARS
    ]

    if not kept:
        # Nothing relevant survived grading, so there is nothing to assert from.
        return BuildOutcome(
            key=key,
            queries=queries,
            kept=kept,
            cell=_abstention(sources=[], limitations=[]),
            attempts=0,
            rejections=["no document passed relevance grading"],
            coverage=coverage,
        )

    source_array = [source_payload(s, accessed_at=accessed_at) for s in kept]
    rejections: list[str] = []
    groundings: list[dict[str, Any]] = []

    for attempt in range(1, max_attempts + 1):
        generated = client.generate_cell(question, kept)
        # Checked **before** normalising, because a default applied to a missing
        # field hides the fact that the model did not produce it: a missing
        # `status` became "grounded" and missing `tips` became `[]`, so
        # malformed output composed into a grounded cell carrying no guidance.
        _require_generated_shape(generated)
        cell = build_cell_payload(
            status=generated["status"],
            # Not `generated["disclaimer"]`: see SUBSTANCE_DISCLAIMER.
            disclaimer=SUBSTANCE_DISCLAIMER,
            tips=generated["tips"],
            sources=source_array,
            # Derived from coverage, never the model's, and only on a grounded
            # cell: an abstention carries none, however it abstained (SPEC 0162).
            limitations=limitations if generated["status"] == "grounded" else [],
        )
        # Validated before grounding: a cell that does not satisfy the contract
        # is a build failure however well supported its claims are, and this is
        # the check a page's injected instruction runs into.
        validate_cell(cell, source_count=len(source_array))

        # A number is refused before grounding is asked: the stance forbids it
        # however well the source supports it (SPEC 0160). Limitations are the
        # build's own sentences, so only tips are read (SPEC 0162).
        numeric = [
            f"states a number: {tip['text']}"
            for tip in cell["tips"]
            if states_a_number(tip["text"])
        ]
        unsupported = list(numeric)
        if not numeric:
            for tip in cell["tips"]:
                grounding = client.ground(
                    tip["text"], [kept[i].text for i in tip["citations"]]
                )
                groundings.append(
                    {
                        "attempt": attempt,
                        "tip": tip["text"],
                        "supported": grounding.supported,
                        "quote": grounding.quote,
                        "found": grounding.found,
                    }
                )
                if not grounding.supported:
                    unsupported.append(tip["text"])
        if not unsupported:
            return BuildOutcome(
                key=key,
                queries=queries,
                kept=kept,
                cell=cell,
                attempts=attempt,
                rejections=rejections,
                groundings=groundings,
                coverage=coverage,
            )
        rejections.extend(unsupported)

    # The model would not ground within the bound. Abstaining is honest; shipping
    # the last attempt would publish a claim the grounding check rejected.
    return BuildOutcome(
        key=key,
        queries=queries,
        kept=kept,
        cell=_abstention(sources=source_array, limitations=[]),
        attempts=max_attempts,
        rejections=rejections,
        groundings=groundings,
        coverage=coverage,
    )


def _require_generated_shape(generated: Any) -> None:
    """Refuses model output the contract does not describe.

    Every field the prompt asks for must be present and of the right type. A
    default here would be this module deciding what the model meant.
    """
    if not isinstance(generated, dict):
        raise CellValidationError("generation did not return an object")
    # `limitations` is not asked for: the build derives them (SPEC 0162), and
    # one the model sends anyway is ignored rather than read.
    for field, expected in (("status", str), ("tips", list)):
        if field not in generated:
            raise CellValidationError(f"generation omitted {field!r}")
        if not isinstance(generated[field], expected):
            raise CellValidationError(
                f"generation returned {field!r} as "
                f"{type(generated[field]).__name__}, not {expected.__name__}"
            )


def _require_queries(queries: Any) -> None:
    """Refuses a transform step that did not do its job.

    The point of the step is one phrasing per management topic, so a missing
    one — or a blank one — is a step that silently did not run.
    """
    from src.llm import ModelRefused

    if not isinstance(queries, list) or len(queries) != len(MANAGEMENT_TOPICS):
        raise ModelRefused(
            f"transform returned {len(queries) if isinstance(queries, list) else '?'} "
            f"queries, not {len(MANAGEMENT_TOPICS)}"
        )
    for query in queries:
        if not isinstance(query, str) or not query.strip():
            raise ModelRefused(f"transform returned a blank query: {query!r}")
        if "_" in query or "|" in query:
            # Graded against an identifier, CT 33 was dropped on every query
            # (SPEC 0152).
            raise ModelRefused(
                f"transform returned a query carrying an identifier: {query!r}"
            )


def _abstention(
    *, sources: list[dict[str, Any]], limitations: list[str]
) -> dict[str, Any]:
    cell = build_cell_payload(
        status="abstained",
        disclaimer=ABSTENTION_DISCLAIMER,
        tips=[],
        sources=sources,
        limitations=limitations,
    )
    validate_cell(cell, source_count=len(sources))
    return cell


__all__ = [
    "ABSTENTION_DISCLAIMER",
    "SUBSTANCE_DISCLAIMER",
    "BuildOutcome",
    "CellValidationError",
    "Grounding",
    "LLMClient",
    "MANAGEMENT_TOPICS",
    "build_cell",
]
