"""The run manifest: what ADR 0023 put in place of a spend ledger.

The question changed with the provider. ADR 0022 guarded a finite budget and
asked "was this affordable"; a local build spends nothing, so the guard that
replaces it asks **"can this be reproduced"**. A corpus whose manifest does not
reproduce is not a corpus.

It records the model and its digest, the prompt versions, the seed, the digest of
every source as it was actually read, and how many attempts the cell took — that
last one because a cell that abstained after two grounding rejections reads
differently from one that grounded first try, and a verdict should not hide
which it was.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from src.sources import FetchedSource


@dataclass
class RunManifest:
    key: str
    model: str
    model_digest: str
    prompt_versions: dict[str, str]
    seed: int
    sources: list[FetchedSource]
    attempts: int
    built_at: datetime = field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    rejections: list[str] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "model": self.model,
            "modelDigest": self.model_digest,
            "promptVersions": dict(self.prompt_versions),
            "seed": self.seed,
            "attempts": self.attempts,
            "builtAt": self.built_at.isoformat().replace("+00:00", "Z"),
            "rejections": list(self.rejections),
            "sources": [
                {
                    "url": source.url,
                    "title": source.title,
                    "publisher": source.publisher,
                    "tier": source.tier,
                    "digest": source.digest,
                }
                for source in self.sources
            ],
        }
