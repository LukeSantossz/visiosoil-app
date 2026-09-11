# The research agent runs at build time and ships a reviewed corpus; the app reads it deterministically, and live research is a capped escalation

The Research Agent's expensive work — query transformation, web search, source
grading, generation with citations, grounding checks — moves out of the request
path and into a build step that runs once per corpus release. Its output is a
versioned, human-reviewed data artifact keyed by texture class, federative unit
and biome. At runtime the app reads that corpus through the existing app↔proxy
contract, with no model call and no network dependency beyond fetching the
corpus itself. Live per-record research survives as a third tier, reached only
through deterministic predicates and bounded by an explicit spend cap.

This supersedes [ADR 0001](0001-research-agent-advisory-web-grounded.md), whose
direction was sound and whose named provider stack no longer exists on the tier
the project can use.

## Status

Accepted. Supersedes [ADR 0001](0001-research-agent-advisory-web-grounded.md),
which is marked Retired in place per the durable-numbering rule. The full design
is modelled in
[`docs/architecture/research-agent.md`](../architecture/research-agent.md).

Accepting this ADR records the decision *direction*. It is **not** a Spec Gate
pass. No `lib/` code and no proxy code ships with it, and every delivery slice
passes its own Spec Gate (`.standards/docs/standards/spec_method.md`) before any
code is written.

## Context

ADR 0001 chose a bounded corrective-RAG chain, executed per request inside a
Cloudflare Worker, powered by Groq's free tier and Tavily's free search tier. The
app-side half of that design shipped and is in the repository today:
`ResearchService`, `HttpTransport`, `ProxyResearchService`, the
`management_tips` Drift table at schema v4, `ManagementTipsRepository`, the
providers and the Details section, with seven test files covering them. The
proxy was never built, and `researchServiceProvider` still returns
`UnavailableResearchService`.

Re-auditing the decision in September 2026 found three facts that falsify it as
written. The first two were checked against primary sources; the third is
arithmetic over published limits.

**The named model is gone.** Groq's deprecation page records
`llama-3.3-70b-versatile` as announced on 2026-06-17 and shut down on
2026-08-16, with the note that "this deprecation applies to free and
developer-tier usage; enterprise customers with a committed-spend contract are
not affected." The recommended replacements are `openai/gpt-oss-120b` and
`qwen/qwen3.6-27b`.

**The pipeline tier does not fit the free tier it was chosen for.** Groq's free
limits for `gpt-oss-120b` are 30 requests per minute, 1,000 requests per day,
8,000 tokens per minute and 200,000 tokens per day, at organisation scope. The
ten-step pipeline in ADR 0001 issues roughly fifteen model calls per request —
one query transformation, one grading call per candidate document, one
generation, two graders and three consistency samples — over a context dominated
by fetched source text. At an estimated 53,000 tokens per request, the daily
token ceiling admits **about four requests per day across all users**; dropping
consistency sampling raises it to about seven. The token estimate is this
record's own and is not measured; the ceiling it is divided into is published.
Tavily's free tier, at 1,000 credits per month against three searches per
request, is not the binding constraint. Groq's daily token budget is.

**The pipeline exceeds the client that was built for it.**
`ProxyResearchService` applies a 20-second per-attempt timeout and retries up to
three times. Fifteen largely sequential model calls plus three searches and five
page fetches do not complete inside 20 seconds, so every request would time out
and each timeout would spend the budget twice more.

Two further observations reframe the problem rather than falsify the old answer.

ADR 0001 states its own limiting condition: "**Thin inputs** (texture + location
+ date) cap specificity." Taken seriously, that is a statement about the size of
the function's domain. The model emits four classes (ADR 0016, SPEC 0046) and
location resolves to a bounded set of regions. The per-request agent was
recomputing, on every capture, a function whose domain has on the order of a
hundred points.

The knowledge base the original design cites for provenance, the maintainer's
`llm-wiki`, holds 507 pages of which 424 carry `area: machine-learning`. A
search for soil, agronomy or Embrapa content returns nine pages, all concerning
UAV remote sensing. It is a knowledge base of *method* — how to build this kind
of system — and contains no agronomic *domain* content. It cannot serve as a RAG
corpus for the tips themselves, and this record does not ask it to.

## Decided

### The expensive pipeline runs at build time, not per request

The corrective-RAG chain ADR 0001 designed is kept almost intact and moved. It
runs offline, once per corpus release, producing a versioned JSON artifact. Per
unit of work it becomes affordable precisely because the number of units is
fixed and small rather than proportional to usage.

Three properties follow that no per-request variant offers. A human reviews every
cell before it reaches a user, which is the mechanism the risk framework this
project's own notes describe assigns to high-stakes output. Nothing is generated
while a user waits, so runtime hallucination risk is not mitigated but absent.
And indirect prompt injection from fetched pages, the primary threat ADR 0001
named, is contained at build time behind a human reader instead of reaching the
device.

### The corpus is two layers, and the runtime key is their composition

The substantive agronomic content varies with soil and biome; the institutional
sources vary with the federative unit. Splitting on that boundary gives the
composite key without paying the cross product.

| Layer | Cells | Content |
|---|---|---|
| Substance | 4 classes × 6 biomes = 24 | The management guidance and its citations |
| Source overlay | 27 federative units | State extension service, state agency, state-specific guidance |

A lookup for `(class, federative unit, biome)` composes the biome cell with the
unit's overlay. The composition is deterministic and involves no model.

The alternative, materialising every `(class, unit, biome)` triple, produces
roughly 208 cells against 51. It costs about three and a half times more to
build, and — the reason that matters more — it multiplies the human review from
51 artifacts to 208 and scatters a single agronomic error across every state a
biome spans.

### Runtime is a deterministic read, and escalation is gated by predicates, not by a model

Three tiers, with the boundary between the second and third decided by cheap,
testable predicates. The decision to escalate is never itself a model call,
because a model call on the escalation decision reintroduces per-request cost on
every capture.

| Tier | When | Cost | Offline |
|---|---|---|---|
| 0 — build | Once per corpus release | Fixed, budgeted | n/a |
| 1 — lookup | Every request | None | Yes |
| 2 — live research | Only on an escalation predicate | Metered, capped | No |

Tier 2 escalates when, and only when, the user asked a free-text question about
the record, structured soil context for the coordinate contradicts the
classification, or the region has no corpus cell. When the cap is exhausted it
degrades to Tier 1 and says so — permanently, because the allowance is one-time
rather than a renewing quota.

An ambiguous verdict is deliberately **not** an escalation. Two candidate classes
are two Tier 1 lookups, rendered as two readings rather than merged into one
answer. That is free, offline and already reviewed; what it gives up is synthesis
of the two, and the fallback if that proves inadequate is precomputing the six
class pairs per biome.

Tier 2 must not offer to research a record whose classification never ran. ADR
0011 and ADR 0015 bind here: `notAnalysed` conflates six causes, and no surface
may offer retry on it until SPEC 0035 lands.

### The app sends a region, never a coordinate

Because the corpus key is a region, the proxy needs no precise location. The app
resolves the federative unit and biome on device and sends those codes. Today
`ProxyResearchService` sends `record.latitude` and `record.longitude` verbatim,
with no consent gate equivalent to the one ADR 0007 requires for sharing. This
decision removes the egress rather than gating it, which is the stronger
remedy and costs nothing because the coordinates were never what the lookup
needed.

### Providers are pinned where portability is expensive and swapped where it is cheap

Portability costs asymmetrically, so it is bought asymmetrically.

At build time the work is a one-off batch job. Routing it through a gateway
forfeits the Batch API's 50% discount and the server-side search tool whose
`allowed_domains` parameter enforces the source allowlist at the platform rather
than in our code. On this project's one-time budget that trades roughly $25 of
capability for roughly $3 of fee. The build is therefore configured against one
provider, while keeping the `LLMClient` and `SearchClient` seams ADR 0001
specified, so a rebuild can move without a rewrite.

At Tier 2 the dependency is live and the volume is small. A gateway's
cross-provider fallback earns its fee there, because a provider outage otherwise
becomes a failed user request.

The deeper protection against lock-in is structural rather than contractual: the
build's output is reviewed JSON. If the provider disappears, the corpus keeps
working. Only a rebuild is exposed, and a rebuild is an occasion to re-choose a
model anyway — as the deprecation in Context demonstrates.

### Groundedness is verified by a different provider than the one that generated it

This repository already requires cross-provider review for code, on the ground
that a reviewer sharing the author's vendor is not an independent check. The
same reasoning applies to generated guidance. The corpus is generated by one
provider and its claims verified against their cited sources by another, at
build time where the cost of a second pass is affordable.

### The response contract is unchanged; the request sheds the coordinates

`ManagementTipsResult` parses exactly as implemented, so the Drift cache at
schema v4, `ManagementTipsRepository`, the providers, the Details section and
their tests are untouched. That is where the bulk of the shipped code lives, and
none of it is rebuilt.

The request body does change, in one place: `ProxyResearchService` stops sending
`latitude`, `longitude` and `address`, and sends region codes instead. It is a
contained change to one method plus a region resolver, and it is what the
previous subsection buys.

The endpoint itself keeps its path and its error codes. The proxy behind it
becomes a lookup, which is what fits inside Cloudflare Workers' 10 ms CPU limit
on the free plan. Tier 2 arrives as a separate endpoint rather than a mode of
this one, so a capped, online-only, per-record path can never be confused with
the free, offline, cacheable one. This is the payoff of the stable boundary ADR
0001 drew, and it is the part of that record this one keeps.

## Considered Options

### Where the research runs

- **Per request, as ADR 0001 specified** — rejected on the arithmetic in
  Context. At roughly four generations per day across all users, a single
  agronomist sampling a morning's worth of fields exhausts the entire
  organisation's daily budget.
- **Per request, with paid providers** — rejected for this budget. The same
  one-time allowance buys about 500 runtime generations that are consumed and
  gone, none of them human-reviewed, or the entire corpus built with a frontier
  model with budget remaining for rebuilds. The comparison is not close.
- **At build time, as decided** — chosen. The domain is small and stable enough
  to enumerate, which is the precondition, and the precondition is a documented
  property of the inputs rather than an assumption.

### Region granularity

- **Federative unit alone** — rejected as agronomically dishonest. Soil does not
  follow state borders, and a single cell for a state spanning two biomes
  averages away the distinction that matters most.
- **Biome alone** — rejected as losing the institutional layer. Which extension
  service a user should consult is a state fact.
- **Full cross product of unit and biome** — rejected on review cost, not on
  money. 208 reviewed artifacts against 51, with each agronomic correction
  applied once per state rather than once per biome.
- **Biome substance with a unit overlay, as decided** — chosen. It yields the
  composite key at the review cost of the coarser one.

### Live research

- **Omit it entirely** — rejected. A free-text question about a specific record
  has an unbounded input space that precompilation cannot serve, and that is the
  case where an agent is genuinely the right tool.
- **Make it the default path** — rejected; this is ADR 0001's position and the
  Context falsifies it.
- **Capped escalation behind deterministic predicates, as decided** — chosen.

## Consequences

- **The feature stops being network-dependent for its main path.** Tier 1 answers
  from a corpus that can ship with the app, which resolves the tension ADR 0001
  recorded between this feature and the app's offline-first stance rather than
  merely caching around it.
- **Guidance becomes reviewable before it is published**, and review becomes the
  release gate. This is a process obligation the previous design did not create:
  someone must read 51 artifacts, and a corpus release is blocked until they do.
- **Specificity is capped at the corpus key.** Two records of the same class in
  the same biome and state receive the same guidance. This is honest about what
  the inputs support — ADR 0001 said as much — but it is a real limitation and
  the interface must not imply otherwise.
- **The corpus is coupled to the model's class list.** If a future ADR changes
  the four classes, cells for changed classes are orphaned. The artifact
  therefore carries a class-list version and the build derives keys from
  `SoilTextureLabels.ordered` rather than a literal, so the breakage is loud.
- **Tier 2 ships enabled, and two of its three predicates cannot fire yet.**
  `userQuestion` needs a free-text input that the result surface does not have,
  which is the UI/UX terminal's to build; `regionalContradiction` needs a
  classification to exist, and no `.tflite` artifact is tracked. Until those
  land, Tier 2 serves only `corpusMiss`. Both are specified and tested against
  fixtures now.
- **A one-time allowance makes Tier 2 finite.** Its cap does not reset monthly,
  so exhaustion is a durable state the interface must present as such. The same
  arithmetic makes the twice-yearly rebuild cadence funded for one year and not
  the second; that gap is recorded rather than discovered.
- **The corpus release is blocked until a reviewer is named.** Human review is
  the release gate and no one is identified for it. The build slices proceed; the
  release does not.
- **A rebuild is auditable rather than reproducible.** The artifact records the
  model identifier, the date, the prompts and the retrieved sources, so a later
  rebuild can be compared against its predecessor even when the original model
  no longer exists.
- **The token estimates in Context are estimates.** The first item of
  implementation is a single-cell calibration probe that measures real usage
  before the corpus budget is committed.
