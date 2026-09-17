# The corpus is built by local open-source models, and Tier 2 leaves v1

The corpus build runs against **local open-source models served by Ollama on the
Developer's machine**, reached through the `LLMClient` and `SearchClient` seams
ADR 0001 specified and ADR 0022 kept. The paid provider ADR 0022 pinned becomes a
second implementation behind the same seams, selected by configuration, and is
what a funded rebuild uses. **Tier 2 — live per-record research — leaves v1**: a
key the corpus does not cover is answered by saying so, not by escalating.

This narrows two of ADR 0022's decisions and reverses one of its consequences. It
does not touch the architecture that record established: the corpus is still
built offline, still reviewed by a human before a user reads it, and the app
still composes on the device with no per-record request.

## Status

Accepted. Narrows
[ADR 0022](0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md)
on provider choice and on where the build runs, and reverses its "Tier 2 ships
enabled in v1" consequence. ADR 0022 is not retired: everything else in it
stands, and this record is only readable against it.

## Context

ADR 0022 was written against a **$50 one-time allowance that was never
released**. Three of its decisions rest on that allowance existing:

| ADR 0022 decided | What it assumed |
|---|---|
| The build is configured against one paid provider, for the Batch API's 50% discount | A budget to discount |
| The source allowlist is enforced by the provider's `allowed_domains` parameter | Access to that provider's server-side search tool |
| Tier 2 ships enabled, with a fail-closed spend cap | A cap with something in it |

None of the three survives a zero budget, and **no record covers building the
corpus without one**. The gap is not a detail: with no provider and no runway,
ADR 0022's plan has no first slice that can run, so the design would sit unbuilt
until money appeared.

The hardware that changes the answer is already here. The Developer's machine is
an RTX 3070 with 8 GB of VRAM and 31 GB of system memory, with Ollama installed —
enough to serve a 7–8 B model quantised, comfortably, and a 12–14 B model with
offload. That is not a frontier model, and the design does not need one, for a
reason specific to this pipeline: **the substance comes from the fetched sources,
not from the model's parametric memory.** The pipeline is grounded generation
over documents it retrieves, which is the regime where a small model is closest
to a large one — `small-language-models.md` records RETRO at 7.5 B reaching GPT-3
at 175 B once retrieval carries the facts, and `rag-auto-corretivo.md` records
CRAG's grader as deliberately *external and light*, plug-and-play rather than a
capability of the generator.

The second change is about honesty rather than money. ADR 0022 recorded Tier 2 as
shipping enabled while two of its three predicates could not fire — `userQuestion`
needs a free-text input nobody has built, `regionalContradiction` needs a
`.tflite` artifact that does not exist. With no budget the third, `corpusMiss`,
cannot fire either. Shipping the code for a tier that cannot serve a single
request would repeat a debt this repository already carries twice, in
`ClassificationVerdict` and `ImageQualityAnalyzer`: implemented, tested, and
called by nobody.

## Decision

### The build runs on local models, reached through the seams that already exist

`LLMClient` and `SearchClient` stay exactly as ADR 0001 specified and ADR 0022
kept. What changes is which implementation is the default:

| Seam | Default | Swappable to |
|---|---|---|
| `LLMClient` | Ollama on `localhost:11434` | The paid provider ADR 0022 named |
| `SearchClient` | **Open** — decided at slice 2's gate | The provider's server-side `web_search` |
| Verifier | A local model of a **different family** than the generator | A second vendor via a gateway |

Two implementations behind one seam is not an abstraction invented for this
record. ADR 0001 specified those seams, ADR 0022 kept them for exactly this
reason — "so a rebuild can move without a rewrite" — and this is the rebuild
moving.

### The allowlist moves from the platform into our code, and that is a cost

ADR 0022 bought one real thing with its pinned provider: `allowed_domains`
enforced the source policy **at the platform**, where our code could not get it
wrong. A local build has no such parameter, so §8's tier list becomes a filter we
implement and test. This is stated as a price rather than waved past: the
allowlist is now our correctness problem, and the injection fixture of §12.4 is
the test that it holds.

### Cross-provider verification becomes cross-family verification

ADR 0022's reasoning was that a verifier sharing the generator's vendor is not an
independent check. Locally the same argument holds one level down: the verifier
runs a model from a **different family and different pre-training lineage** than
the generator — not the same model at a different temperature, which would check
nothing. The requirement is recorded as *different family*, and which two
families is a slice-2 measurement rather than a guess here.

### The build runs on the Developer's machine, not in CI

ADR 0022 §20.5 put the build in CI under manual dispatch, and named the two
guards that followed from a repository secret over a finite budget: a required
confirmation input and a spend ledger that fails closed. **Both guards exist to
protect money, and there is no money to protect.** CI also cannot serve a local
model without paying for a GPU runner, which would reintroduce the cost the
decision exists to avoid.

The guard that replaces them answers a different question — not "was this
affordable" but "can this be reproduced": the build writes a **run manifest**
committed beside the corpus, recording model names and digests, the resolved
source list, the prompt versions and the seed. A corpus whose manifest does not
reproduce is not a corpus.

### Tier 2 leaves v1

The three predicates stay in the design and none of them is built. A key the
corpus does not cover composes to `insufficient_evidence` and the surface says
there is no coverage for that region — which §6.5 already defines as a valid
composition and §13 already requires the interface to state.

The output contract does not change. `followUpQuestions` and `alerts` were always
optional with documented defaults, so a later Tier 2 fills fields that already
exist rather than forcing a second migration.

## Options rejected

- **Wait for the budget.** Rejected. It defers the entire feature on a
  contingency with no date, when the hardware to build a first corpus is already
  on the desk and the app half needs no model at all.
- **Pin the local provider the way ADR 0022 pinned the paid one.** Rejected for
  the opposite reason ADR 0022 gave. Pinning bought a discount and a
  platform-enforced allowlist; locally there is no discount and no platform, so
  pinning would buy nothing and cost the funded rebuild a rewrite.
- **Keep the paid path as the default and treat local as a fallback.** Rejected
  as a record that describes a build nobody can run. The default should be the
  path that works today.
- **Build both paths fully and choose at run time, as a first-class matrix.**
  Rejected on maintenance, not on principle: two complete implementations must
  both be tested against every cell, and the second has no user until a budget
  exists. The seam is kept; only one side of it is implemented now, and the spec
  that adds the other says so.
- **Ship Tier 2 disabled behind a flag.** Rejected. This repository already
  carries two implemented-and-uncalled features, each waiting on a wiring spec,
  and both are recorded as debt. A third would be a choice to repeat a known
  mistake.
- **Serve Tier 2 from the Developer's own Ollama.** Rejected as a demonstration
  presented as a product. It works while one machine is on, and an agronomist in
  a field reaches nothing.
- **Drop the corpus and answer everything live from a local model.** Rejected for
  the reason ADR 0022 gave and this record does not weaken: an unreviewed model
  answering agronomic questions at runtime is the risk the whole design exists to
  remove, and running it locally removes the cost, not the risk.

## Consequences

- **The feature can be built starting today**, with no spend and no external
  account. The app half needs no model at all and the build half needs a model
  that is already installed.
- **Quality is lower than the paid path and the gap is unmeasured.** No local
  model was run against a cell before this record; the calibration probe that
  ADR 0022 costed at $1 becomes free and its purpose is unchanged — measure one
  cell before building fifty. It now measures quality rather than price.
- **The allowlist is our code's responsibility**, with a test rather than a
  platform behind it.
- **A funded rebuild is a configuration change, not a rewrite**, because the seam
  survives and the corpus format does not depend on who generated it.
- **The corpus is reproducible rather than affordable.** The run manifest is what
  a reader checks, and a build that will not reproduce fails.
- **Tier 2's absence is visible to the user**, as a statement that a region is
  not covered. That is a smaller feature than ADR 0022 described and an honest
  one, and it removes the durable cap-exhaustion state the UI/UX terminal was
  asked for.
- **`ProxyResearchService` has no caller in v1.** With Tier 2 gone and the corpus
  fetched rather than queried per record, its only v1 use is corpus fetch, which
  is slice 8's. Until then it is transport with no route — recorded here so the
  next reader does not mistake it for dead code.
