# SPEC: fix(corpus): read the model digest from Ollama's tags list

## Problem

`OllamaClient.model_digest` asks `POST /api/show` for the model and reads a
top-level `digest` field. Ollama's `/api/show` has no such field. Its response
carries `license`, `modelfile`, `template`, `system`, `details`, `model_info`,
`capabilities` and `modified_at`, which is what Ollama 0.40.2 returned on
2026-10-09. The digest of a local model is reported by `GET /api/tags`, one
entry per model, next to its `name` and `model`.

So every real probe run fails with `ModelRefused: ollama reported no usable
digest for qwen2.5:7b (None)`. The unit tests did not catch it, because they
inject a `post` that returns `{"digest": ...}`, a shape the real server never
sends.

The failure also comes late. `probe.main` asks for the digest only after
`build_cell` has run the whole chain, so the cell that was just generated is
discarded. On 2026-10-09 the B1' re-probe (#251) lost a five-minute build that
way before a local workaround produced its output.

## Design Decision

**The digest is read from `GET /api/tags`.**

- `OllamaClient` gains an injected `get: HttpGet | None`, next to its `post`.
  `HttpGet` is `Callable[[str], dict[str, Any]]`.
- The default `_get` is a plain `urllib` GET with the 60 s timeout the
  transport already uses for a short request.
- `model_digest` looks for the entry in `models` whose `name` or `model`
  equals the client's model.
  - A model named without a tag is matched as `<name>:latest`, because that is
    how Ollama lists it.
  - What it keeps of the existing check: a digest that is missing, empty or
    not a string raises `ModelRefused` naming the digest, and a failing
    request propagates. ADR 0023's run manifest still never records
    "unknown".
  - New: a model that is not in the list raises `ModelRefused` naming the
    model.
- `/api/show` is no longer called.

**The probe reads the digest before it builds.** `probe.main` asks for the
digest right after it constructs the client and before `build_cell`.

- A server that cannot name the model then stops the run before any model
  call is spent.
- The value written to the run manifest is the same one, because nothing
  between the two points pulls or replaces a model.

## Alternatives Considered

- **Keep `/api/show` and read a digest out of `modelfile` or `details`.**
  Rejected. Neither carries the model's digest. `modelfile` names a blob path
  for the weights, which is the weights layer's digest, not the model's.
- **`GET /api/ps`.** Rejected. It lists only loaded models, so the answer would
  depend on whether a previous request had loaded the model, and before the
  first call it does not.
- **Record "unknown" when the lookup fails.** Rejected, as the existing
  docstring and test already reject it. The manifest exists to name the model.

## Scope

- Includes:
  - `corpus/src/llm.py`: `HttpGet`, `_get`, the `get` seam and
    `model_digest` reading `/api/tags`.
  - `corpus/src/probe.py`: the digest read before `build_cell`.
  - `corpus/tests/test_llm.py`: the digest tests rewritten against the tags
    shape.
  - A new probe test for the order.
- Does NOT include:
  - The request timeout of `_post`, the prompts, the source manifest, the
    pipeline, or any other part of the chain.
  - The B1' judgement itself, which #251 records.
  - Any app (Dart) code.

## Acceptance Criteria

- `the_digest_is_read_from_the_tags_list`: given a tags payload listing the
  client's model with digest `sha256:abc`, `model_digest` returns
  `sha256:abc`, and the URL it requests ends in `/api/tags`.
- `an_untagged_model_matches_its_latest_entry`: a client for `qwen2.5` finds
  the entry named `qwen2.5:latest`.
- `a_model_the_server_does_not_list_is_refused`: when no entry matches,
  `ModelRefused` is raised and its message names the model.
- `a_digest_that_is_not_a_string_is_refused`: a matching entry whose digest is
  a mapping, a list, a number or empty raises `ModelRefused` matching "digest".
- `an_unreadable_digest_fails_rather_than_becoming_unknown`: a `get` that
  raises `OSError` propagates it.
- `the_probe_reads_the_digest_before_it_builds`: when the digest lookup
  raises, `probe.main` raises before any model call and writes no output.

## Reproducibility

```sh
cd corpus
python -m pytest tests -q
# Against a running Ollama with the model pulled:
python -m src.probe --cell "Argilosa|tb_oxidic"
```

## Risks and Assumptions

- **Assumption: `/api/tags` keeps its `models[].name`, `models[].model` and
  `models[].digest` fields.** They are the documented shape and what 0.40.2
  returns. A change would fail loudly through `ModelRefused`, not silently.
- **Assumption: the digest `/api/tags` reports identifies the model build.**
  It is the manifest digest Ollama pulls by, which `ollama list` shows as the
  model's ID.
- **Risk: a model re-pulled between the lookup and the build.** The manifest
  would name the earlier build. This is a manual, single-operator run, and the
  previous order had the mirror-image risk.
