"""The cell contract, enforced where cells are produced.

The app reads every cell through one reader (`CorpusComposer`'s `CorpusCell`), so
a build that can emit a shape the app rejects is a build that ships a broken
release. The same rules are therefore checked here, at the point of production,
where the failure names the cell instead of reaching a device.

It is also the boundary that makes indirect prompt injection a build failure
rather than a release. A page can persuade a model to emit anything; it cannot
persuade this module to accept it.
"""

from __future__ import annotations

from typing import Any, Iterable

STATUSES = ("grounded", "abstained")
"""What a *cell* may be. `insufficient_evidence` is a property of a composition
that found no cell, so a cell can never carry it."""


class CellValidationError(Exception):
    """A cell that does not satisfy the contract the app reads it through."""


def validate_cell(cell: dict[str, Any], *, source_count: int) -> None:
    """Raises [CellValidationError] unless [cell] is one the app can read."""
    status = cell.get("status")
    if status not in STATUSES:
        raise CellValidationError(
            f"cell status {status!r} is not one of {STATUSES}"
        )

    disclaimer = cell.get("disclaimer")
    if not isinstance(disclaimer, str) or not disclaimer.strip():
        raise CellValidationError("cell has no disclaimer; every cell carries one")

    tips = cell.get("tips")
    if not isinstance(tips, list):
        raise CellValidationError("cell tips must be a list")

    if status == "abstained" and tips:
        raise CellValidationError(
            "an abstained cell carries no tips; it abstained because it would "
            "not assert"
        )

    for position, tip in enumerate(tips):
        text = tip.get("text")
        if not isinstance(text, str) or not text.strip():
            raise CellValidationError(f"tip {position} has no text")
        citations = tip.get("citations")
        if not isinstance(citations, list) or not citations:
            raise CellValidationError(
                f"tip {position} has no citation; an uncited tip is the failure "
                f"the cited-sources rule exists to prevent"
            )
        for citation in citations:
            if not isinstance(citation, int) or not 0 <= citation < source_count:
                raise CellValidationError(
                    f"tip {position} has a citation {citation!r} with only "
                    f"{source_count} source(s)"
                )


def build_cell_payload(
    *,
    status: str,
    disclaimer: str,
    tips: Iterable[dict[str, Any]],
    sources: Iterable[dict[str, Any]],
    limitations: Iterable[str],
) -> dict[str, Any]:
    """Assembles a cell from the fields the contract names, and only those.

    Rebuilding rather than passing a model's object through is what stops a page
    smuggling a field into the artifact by persuading the model to emit one.
    """
    return {
        "status": status,
        "disclaimer": disclaimer,
        "tips": [
            {
                "text": tip["text"],
                "citations": list(tip.get("citations", [])),
                **({"category": tip["category"]} if tip.get("category") else {}),
                **(
                    {"evidenceStrength": tip["evidenceStrength"]}
                    if tip.get("evidenceStrength")
                    else {}
                ),
            }
            for tip in tips
        ],
        "sources": list(sources),
        "limitations": list(limitations),
    }


def source_payload(source, *, accessed_at: str) -> dict[str, Any]:
    """One entry of a cell's `sources` array, in the app's shape."""
    return {
        "title": source.title,
        "url": source.url,
        "publisher": source.publisher,
        "tier": source.tier,
        "accessedAt": accessed_at,
    }
