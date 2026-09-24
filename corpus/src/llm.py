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

from src.sources import (
    PASSAGE_CHAR_LIMIT,
    PDF_SIGNATURE,
    PDF_SIGNATURE_WINDOW,
    FetchedSource,
)

PROMPTS_DIR = Path(__file__).resolve().parent.parent / "prompts"
OLLAMA_URL = "http://localhost:11434"

CONTEXT_TOKENS = 16384
"""The context every request asks for. Left unset, Ollama picks a default from
the machine's video memory — 4096 tokens on one with none — and cuts a longer
prompt without saying so, so the same model and seed read different prompts on
different machines. Three passages at `PASSAGE_CHAR_LIMIT` plus a template fit
with room to spare."""

MIN_CHARS_PER_TOKEN = 2
"""A floor Portuguese prose does not approach, so a prompt under
`PROMPT_CHAR_CEILING` fits the context in all but a table of bare numbers."""

PROMPT_CHAR_CEILING = CONTEXT_TOKENS * MIN_CHARS_PER_TOKEN

HttpPost = Callable[[str, dict[str, Any]], dict[str, Any]]


class RedirectRefused(Exception):
    """A source that redirected somewhere the manifest does not list.

    `urlopen` follows redirects by default, and `SourceManifest` validates only
    the URL the build asked for. An allowlisted server redirecting to an internal
    or loopback address would therefore have the build fetch that destination and
    feed its text into the corpus pipeline — the allowlist enforced on the first
    request only.

    Refusing outright is the smaller surface. A curated source that genuinely
    moved is a manifest entry to update, and updating the manifest is a reviewed
    act, which is the property the curated half exists to have.
    """


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Turns every redirect into [RedirectRefused]."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        origin = getattr(req, "full_url", "the source")
        raise RedirectRefused(
            f"{origin} redirected to {newurl}, which the source manifest does "
            f"not list; add it there if the source moved"
        )


class ModelRefused(Exception):
    """The model returned something the step cannot use.

    Raised rather than defaulted: a grading step that silently reads an
    unparseable answer as "relevant" would admit every document, and nobody
    would learn.
    """


_NO_REDIRECT_OPENER = urllib.request.build_opener(_NoRedirect())


def http_transport(url: str) -> str | bytes:
    """Reads a source over HTTP, refusing redirects.

    Used by the probe, never by a test. See [RedirectRefused] for why a redirect
    is a refusal rather than a hop.
    """
    request = urllib.request.Request(
        url, headers={"User-Agent": "visiosoil-corpus-build/1.0"}
    )
    # 60 s rather than 30: institutional sites are slow, and a source that times
    # out fails the whole build by design, so the cost of being impatient is a
    # build that stops on a source that was merely slow.
    with _NO_REDIRECT_OPENER.open(request, timeout=60) as response:  # noqa: S310
        return decode_body(response.read(), response.headers.get_content_charset())


def decode_body(raw: bytes, charset: str | None) -> str | bytes:
    """A PDF as its undecoded bytes, anything else as text in [charset].

    A PDF is binary, and decoding it would hand the HTML extractor whatever text
    survived — which it returns rather than failing. The signature is looked for
    across the window readers search, not only at the first byte, so a PDF behind
    a stray prefix stays bytes and is refused by the fetch.
    """
    if PDF_SIGNATURE in raw[:PDF_SIGNATURE_WINDOW]:
        return raw
    return raw.decode(charset or "utf-8", errors="replace")


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


_ACCENTS = str.maketrans("áàãâäéêèëíîìïóôõòöúûùüçñ", "aaaaaeeeeiiiiooooouuuucn")

_NEGATION = re.compile(r"\b(?:nao|not|nem)\b")
_NEGATED_POSITIVE = re.compile(
    r"\b(?:nao|not|nem)\s+(?:\w+\s+){0,2}?(?:yes|sim|true|relevante)\b"
)
_POSITIVE = re.compile(r"\b(?:yes|sim|true|relevante)\b")
_NEGATIVE = re.compile(r"\b(?:no|false|irrelevante)\b")


def parse_yes_no(raw: str) -> bool:
    """A binary grade from [raw], or [ModelRefused].

    **A negation attached to a positive word makes the answer negative.** That is
    the bug this shape exists for: "não relevante" contains `relevante`, so a
    loop that returned on the first positive token answered `True` to an explicit
    rejection — and the grader kept a source the model had thrown out, silently,
    on every cell.

    An answer carrying both polarities *without* that attachment — "sim e não" —
    is refused rather than resolved, because picking whichever token appears
    first turns a model's hedge into a decision nobody made.
    """
    lowered = raw.strip().lower().translate(_ACCENTS)

    if _NEGATED_POSITIVE.search(lowered):
        return False

    positive = bool(_POSITIVE.search(lowered))
    negative = bool(_NEGATIVE.search(lowered)) or bool(_NEGATION.search(lowered))

    if positive and negative:
        raise ModelRefused(f"grade says both yes and no: {raw[:120]!r}")
    if positive:
        return True
    if negative:
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
        """The digest Ollama reports for the loaded model.

        **Failure propagates.** The run manifest is the reproducibility guarantee
        ADR 0023 put in place of a spend ledger, and a corpus generated against a
        model nobody can name does not reproduce. Swallowing the lookup and
        writing "unknown" would let the build finish while quietly voiding the
        one thing that record exists to promise.
        """
        payload = self._post(f"{self._base_url}/api/show", {"model": self.model})
        digest = payload.get("digest")
        if not isinstance(digest, str) or not digest.strip():
            # A non-string passes `str()` and reaches `modelDigest` looking like
            # an identifier while naming nothing, and `RunManifest` performs no
            # runtime type check. The type is part of the promise.
            raise ModelRefused(
                f"ollama reported no usable digest for {self.model} "
                f"({digest!r}); the run manifest cannot identify what generated "
                f"the corpus"
            )
        return digest

    def _complete(self, prompt: str) -> str:
        if len(prompt) > PROMPT_CHAR_CEILING:
            # The server would cut it to the context and say nothing, so a
            # manifest listing more passages than the context holds fails here.
            raise ModelRefused(
                f"prompt is {len(prompt)} characters, above the "
                f"{PROMPT_CHAR_CEILING} a {CONTEXT_TOKENS}-token context is "
                f"sure to hold; list fewer passages or narrow them"
            )
        payload = self._post(
            f"{self._base_url}/api/generate",
            {
                "model": self.model,
                "prompt": prompt,
                "stream": False,
                "options": {
                    "temperature": 0,
                    "seed": self.seed,
                    "num_ctx": CONTEXT_TOKENS,
                },
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
                "{{document}}", document.text[:PASSAGE_CHAR_LIMIT]
            )
        )
        return parse_yes_no(raw)

    def generate_cell(
        self, question: str, documents: list[FetchedSource]
    ) -> dict[str, Any]:
        template, _ = self._prompts["generate"]
        rendered = "\n\n".join(
            f"[{index}] {doc.title}\n{doc.text[:PASSAGE_CHAR_LIMIT]}"
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
                "{{evidence}}",
                "\n\n".join(text[:PASSAGE_CHAR_LIMIT] for text in cited_texts),
            )
        )
        return parse_yes_no(raw)
