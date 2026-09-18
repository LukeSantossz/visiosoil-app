"""The `LLMClient` seam and its Ollama implementation.

ADR 0001 specified this seam, ADR 0022 kept it "so a rebuild can move vendor
without a rewrite", and ADR 0023 is that rebuild moving: the default is a local
open-source model served by Ollama, and the paid provider becomes a second
implementation behind the same protocol.

Everything model-specific lives here. The chain in `pipeline.py` never sees an
HTTP call, a prompt, or a JSON quirk, which is what lets every pipeline test run
without a model.
"""

from __future__ import annotations

import json
import re
import urllib.request
from pathlib import Path
from typing import Any, Callable

from src.sources import FetchedSource

PROMPTS_DIR = Path(__file__).resolve().parent.parent / "prompts"
OLLAMA_URL = "http://localhost:11434"

HttpPost = Callable[[str, dict[str, Any]], dict[str, Any]]


class ModelRefused(Exception):
    """The model returned something the step cannot use.

    Raised rather than defaulted: a grading step that silently reads an
    unparseable answer as "relevant" would admit every document, and nobody
    would learn.
    """


def http_transport(url: str) -> str:
    """Reads a source over HTTP. Used by the probe, never by a test."""
    request = urllib.request.Request(
        url, headers={"User-Agent": "visiosoil-corpus-build/1.0"}
    )
    # 60 s rather than 30: institutional sites are slow, and a source that times
    # out fails the whole build by design, so the cost of being impatient is a
    # build that stops on a source that was merely slow.
    with urllib.request.urlopen(request, timeout=60) as response:  # noqa: S310
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def _post(url: str, payload: dict[str, Any]) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=300) as response:  # noqa: S310
        return json.loads(response.read().decode("utf-8"))


def load_prompt(name: str) -> tuple[str, str]:
    """The text of prompt [name] and its version.

    Prompts live in files rather than string literals because the run manifest
    records a prompt version, and a prompt embedded in code cannot be versioned
    separately from the code that sends it.
    """
    path = PROMPTS_DIR / f"{name}.md"
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^version:\s*(\S+)\s*$", text, re.MULTILINE)
    if not match:
        raise ValueError(f"{path} has no `version:` line")
    return text, match.group(1)


def parse_json_object(raw: str) -> dict[str, Any]:
    """The first JSON object in [raw].

    Small models wrap JSON in prose or in a fenced block even when told not to.
    Extracting the object is a tolerance about *formatting*; it is not a
    tolerance about content, which `cell.py` refuses to grant.
    """
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, re.DOTALL)
    candidate = fenced.group(1) if fenced else None
    if candidate is None:
        start = raw.find("{")
        end = raw.rfind("}")
        if start == -1 or end <= start:
            raise ModelRefused(f"no JSON object in model output: {raw[:200]!r}")
        candidate = raw[start : end + 1]
    try:
        parsed = json.loads(candidate)
    except json.JSONDecodeError as error:
        raise ModelRefused(f"model output is not JSON: {error}") from error
    if not isinstance(parsed, dict):
        raise ModelRefused("model output is JSON but not an object")
    return parsed


def parse_yes_no(raw: str) -> bool:
    """A binary grade from [raw], or [ModelRefused]."""
    lowered = raw.strip().lower()
    for token in ("yes", "sim", "true", "relevante"):
        if re.search(rf"\b{token}\b", lowered):
            return True
    for token in ("no", "não", "nao", "false", "irrelevante"):
        if re.search(rf"\b{token}\b", lowered):
            return False
    raise ModelRefused(f"grade is neither yes nor no: {raw[:120]!r}")


class OllamaClient:
    """`LLMClient` over a local Ollama server.

    Deterministic as far as the runtime allows: temperature 0 and a recorded
    seed, both of which land in the run manifest. A rerun that diverges is
    itself a finding rather than a nuisance.
    """

    def __init__(
        self,
        *,
        model: str = "qwen2.5:7b",
        seed: int = 1234,
        base_url: str = OLLAMA_URL,
        post: HttpPost | None = None,
    ) -> None:
        self.model = model
        self.seed = seed
        self._base_url = base_url
        self._post = post or _post
        self._prompts = {
            name: load_prompt(name)
            for name in ("transform", "grade", "generate", "ground")
        }

    @property
    def prompt_versions(self) -> dict[str, str]:
        return {name: version for name, (_, version) in self._prompts.items()}

    def model_digest(self) -> str:
        """The digest Ollama reports for the loaded model, or a stated unknown."""
        try:
            payload = self._post(f"{self._base_url}/api/show", {"model": self.model})
        except Exception:  # noqa: BLE001 - the manifest records what it could read
            return "unknown"
        return str(payload.get("digest") or payload.get("model_info", {}) or "unknown")

    def _complete(self, prompt: str) -> str:
        payload = self._post(
            f"{self._base_url}/api/generate",
            {
                "model": self.model,
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0, "seed": self.seed},
            },
        )
        return str(payload.get("response", ""))

    def transform_queries(self, question: str, *, count: int) -> list[str]:
        template, _ = self._prompts["transform"]
        raw = self._complete(
            template.replace("{{question}}", question).replace(
                "{{count}}", str(count)
            )
        )
        queries = parse_json_object(raw).get("queries")
        if not isinstance(queries, list) or not queries:
            raise ModelRefused("transform returned no queries")
        return [str(q) for q in queries][:count]

    def grade_document(self, query: str, document: FetchedSource) -> bool:
        template, _ = self._prompts["grade"]
        raw = self._complete(
            template.replace("{{query}}", query).replace(
                "{{document}}", document.text[:6000]
            )
        )
        return parse_yes_no(raw)

    def generate_cell(
        self, question: str, documents: list[FetchedSource]
    ) -> dict[str, Any]:
        template, _ = self._prompts["generate"]
        rendered = "\n\n".join(
            f"[{index}] {doc.title}\n{doc.text[:6000]}"
            for index, doc in enumerate(documents)
        )
        raw = self._complete(
            template.replace("{{question}}", question).replace(
                "{{documents}}", rendered
            )
        )
        return parse_json_object(raw)

    def is_grounded(self, tip_text: str, cited_texts: list[str]) -> bool:
        template, _ = self._prompts["ground"]
        raw = self._complete(
            template.replace("{{claim}}", tip_text).replace(
                "{{evidence}}", "\n\n".join(text[:6000] for text in cited_texts)
            )
        )
        return parse_yes_no(raw)
