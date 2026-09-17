"""The CRAG chain that builds one cell.

Four steps: transform the question into several queries, grade each document for
relevance, generate a cited cell from what survived, and check that every tip is
actually supported by what it cites.

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

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Protocol

from src.cell import (
    CellValidationError,
    build_cell_payload,
    source_payload,
    validate_cell,
)
from src.sources import FetchedSource

ABSTENTION_DISCLAIMER = (
    "Nenhuma fonte elegível sustentou uma orientação para esta combinação. "
    "Consulte a assistência técnica local."
)

QUERY_COUNT = 3
"""How many queries the transform step produces. More than one is the point of
the step: a single phrasing of an agronomic question retrieves one phrasing of
the literature."""


class LLMClient(Protocol):
    """What the pipeline needs of a model.

    A protocol rather than a class so a fake satisfies it structurally, and so
    the funded rebuild ADR 0023 anticipates swaps the implementation without
    touching the chain.
    """

    def transform_queries(self, question: str, *, count: int) -> list[str]: ...

    def grade_document(self, query: str, document: FetchedSource) -> bool: ...

    def generate_cell(
        self, question: str, documents: list[FetchedSource]
    ) -> dict[str, Any]: ...

    def is_grounded(self, tip_text: str, cited_texts: list[str]) -> bool: ...


@dataclass
class BuildOutcome:
    """What one cell build produced, and enough of how to make it readable."""

    key: str
    queries: list[str]
    kept: list[FetchedSource]
    cell: dict[str, Any]
    attempts: int
    rejections: list[str] = field(default_factory=list)


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
    accessed_at = (now or datetime.now(timezone.utc)).isoformat().replace(
        "+00:00", "Z"
    )
    queries = client.transform_queries(key, count=QUERY_COUNT)

    kept = [
        document
        for document in sources
        if any(client.grade_document(query, document) for query in queries)
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
        )

    source_array = [source_payload(s, accessed_at=accessed_at) for s in kept]
    rejections: list[str] = []

    for attempt in range(1, max_attempts + 1):
        generated = client.generate_cell(key, kept)
        cell = build_cell_payload(
            status=generated.get("status", "grounded"),
            disclaimer=generated.get("disclaimer", ""),
            tips=generated.get("tips", []),
            sources=source_array,
            limitations=generated.get("limitations", []),
        )
        # Validated before grounding: a cell that does not satisfy the contract
        # is a build failure however well supported its claims are, and this is
        # the check a page's injected instruction runs into.
        validate_cell(cell, source_count=len(source_array))

        unsupported = [
            tip["text"]
            for tip in cell["tips"]
            if not client.is_grounded(
                tip["text"], [kept[i].text for i in tip["citations"]]
            )
        ]
        if not unsupported:
            return BuildOutcome(
                key=key,
                queries=queries,
                kept=kept,
                cell=cell,
                attempts=attempt,
                rejections=rejections,
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
    "BuildOutcome",
    "CellValidationError",
    "LLMClient",
    "build_cell",
]
