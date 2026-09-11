# Research Agent: advisory, web-search-grounded, free/open-source engine behind a swappable proxy

The Research Agent turns a Soil Record's texture class plus location metadata (GPS, address, timestamp) into cited Management Tips. We decided it is **advisory, not prescriptive** (it informs and cites sources, it does not direct a field action); grounded by **live web search with citations** rather than pure LLM generation or a curated RAG corpus; powered by a **free/open-source tool-calling model** rather than a paid API (no budget); and reached only through a **backend proxy** that holds credentials and is **provider-swappable**, never by the app calling a model directly.

## Status

**Retired 2026-09-11**, superseded by
[ADR 0022](0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md).
Kept in place with its number and file, per the durable-numbering rule.

What this record got right is kept unchanged by its successor: the advisory
stance, grounding in citable sources, the abstain-or-emit rule, credentials
living server-side, and the app↔proxy HTTP contract as the stable boundary. The
app-side implementation built against that contract — `ResearchService`,
`ProxyResearchService`, the `management_tips` table, the repository, the
providers and the Details section — remains correct and is not rebuilt.

Three of its decisions did not survive re-audit in September 2026:

| This record decided | What was found |
|---|---|
| Groq's `llama-3.3-70b-versatile` on the free tier | Announced deprecated 2026-06-17 and shut down 2026-08-16 for free and developer tiers |
| A ten-step corrective-RAG chain per request, on a free tier | The published free daily token ceiling admits roughly four to seven requests per day across all users |
| That chain reached through `ProxyResearchService` | Its fifteen model calls do not complete within the client's 20-second timeout, so every request would time out and retry twice |

The pipeline design itself was not the error. ADR 0022 keeps it and moves it to
build time, where its cost is proportional to a fixed corpus rather than to
usage, and where a human can review its output before a user reads it.

### Decided
- **Provider stack** — Groq (Llama 3.3 70B free tier) for the tool-calling model + Tavily (free search tier) for web search, both behind swappable `LLMClient` / `SearchClient` interfaces in the proxy.
- **Proxy host** — Cloudflare Workers (free tier), JS/TS runtime. (Earlier topology question C1-vs-C2 is resolved in favour of a hosted proxy; an on-device Ollama prototype remains a documented future escape hatch, not the v1 path.)
- **App→proxy authentication** — a backend-verifiable Google **ID token** (JWT) carried as the bearer, so the proxy verifies the user offline (`aud` = OAuth Web client) and enforces per-user rate limits/quota. The existing `accessToken()` seam is the integration point but exposes only the Drive *access* token today, so a seam change (capture `idToken` + set `serverClientId`) is a prerequisite. This **depends on the OAuth Web client** tracked under the cloud-sync work (#55); see the architecture doc §5 for the gap and the `tokeninfo` fallback.
- **Pipeline tier** — a full/robust **bounded corrective-RAG chain** (multi-query transformation, source authority/recency filtering, grounding + answer grading, consistency sampling, abstain-or-emit), not a minimal single-shot pipeline and not an autonomous ReAct agent. Rationale and step-by-step in the architecture doc.

## Considered Options

### Grounding strategy
- **Pure LLM generation** — rejected: no verifiable sources, real risk of hallucinated agronomic advice; contradicts the cited-sources requirement.
- **Curated RAG corpus (e.g. embedded Embrapa guides)** — rejected for v1: building and maintaining the corpus (ingestion, updates, search infra) is disproportionate now; revisit as a hybrid if web-source quality proves insufficient.
- **Paid Claude + built-in `web_search` tool** — rejected for v1 on budget (Sonnet 4.6 $3/$15 per 1M + $10/1,000 searches); remains the quality benchmark and the swappable proxy keeps it a drop-in upgrade later.
- **On-device model** — rejected for v1: cannot run live search, and phone-sized models are too weak for trustworthy agronomic guidance. Retained as a privacy escape hatch (Ollama) if location-data egress ever becomes a blocker.

### Pipeline shape
- **Single-shot search → synthesize** — rejected as under-engineered: without grading/grounding checks it produces plausible-but-ungrounded tips, the exact failure the cited-sources rule exists to prevent.
- **Autonomous ReAct agent** — rejected as over-engineered and risky on a free model: non-convergent loops, unbounded LLM-call cost, and confident-but-empty reasoning. The task shape is fixed, so the proxy owns the loop rather than letting the model decide when to stop.
- **Bounded corrective-RAG chain** — chosen: the medium-risk tier (RAG + guardrails + citations + confidence/abstention) that matches an advisory, customer-facing-but-not-catastrophic feature.

## Consequences

- The feature is **network-dependent** — tension with the app's offline-first model; the graded, cited result is **cached per Soil Record** (read-through cache keyed by `uuid`, separate from the sync outbox) so a record's guidance survives offline.
- Free-tier **rate limits and quality below frontier models** raise the weight of the disclaimer ("validate with local soil analysis") and the advisory-not-prescriptive stance; the pipeline must be able to **abstain** rather than fabricate.
- **Credentials live server-side** in the proxy, never embedded in the mobile client.
- The proxy makes the engine **swappable** — start free (Groq/Tavily), upgrade to Claude later without rearchitecting the app↔proxy contract, which is the stable boundary.
- **Untrusted web content is a security surface** — the agent reads arbitrary pages, so indirect prompt injection (OWASP LLM01) is the primary threat; all fetched content is handled as data, never instructions, with least-privilege tools and sanitized output.
- **Thin inputs** (texture + location + date) cap specificity; the advisory stance stays honest until the app collects crop, season, and soil chemistry — only then is a Prescription justified.
- **Per-user auth couples the feature to Google sign-in** — viewing tips requires a signed-in account, and the proxy's token verification depends on the OAuth Web client from #55.
