# Corpus third correction attempt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a rejected corpus batch one additional, bounded correction attempt without changing the existing feedback or batching model.

**Architecture:** `build_cell` already delegates each source batch to `_build_batch`, which repeats generation, refusal checks, and grounding until `max_attempts` is exhausted. The change only raises the public default to three; tests use the existing scripted client to prove the third prompt receives the second rejection reason and callers can still set two explicitly.

**Tech Stack:** Python 3.12, pytest, local Ollama-client protocol fakes.

---

### Task 1: Specify the third-attempt behavior

**Files:**
- Modify: `corpus/tests/test_pipeline.py`
- Test: `corpus/tests/test_pipeline.py`

- [ ] **Step 1: Add the failing default-limit test beside the retry-feedback tests.**

```python
def test_default_attempt_limit_is_three():
    numeric = "Em solo argiloso, o nível crítico é 18 mg dm-3."
    directional = "Em solo argiloso, o nível crítico é menor."
    client = SequencedClient(
        [generation_with(numeric), generation_with(numeric), generation_with(directional)],
        grounded=[True],
    )

    outcome = build_cell(QUESTION, [source(0)], client=client)

    assert outcome.cell["status"] == "grounded"
    assert outcome.attempts == 3
    assert client.told[0] == []
    assert client.told[1] == client.told[2]
    assert client.told[2][0].startswith(f'"{numeric}": ')
```

- [ ] **Step 2: Add the explicit-bound regression test.**

```python
def test_explicit_attempt_limit_is_preserved():
    numeric = "Em solo argiloso, o nível crítico é 18 mg dm-3."
    directional = "Em solo argiloso, o nível crítico é menor."
    client = SequencedClient(
        [generation_with(numeric), generation_with(numeric), generation_with(directional)],
        grounded=[True],
    )

    outcome = build_cell(QUESTION, [source(0)], client=client, max_attempts=2)

    assert outcome.cell["status"] == "abstained"
    assert outcome.attempts == 2
    assert len(client.told) == 2
```

- [ ] **Step 3: Run the focused tests and confirm the new default test fails with two attempts.**

Run: `python -m pytest tests/test_pipeline.py -k "default_attempt_limit_is_three or explicit_attempt_limit_is_preserved"`

Expected: `default_attempt_limit_is_three` fails because the current default exhausts after two attempts; `explicit_attempt_limit_is_preserved` passes.

### Task 2: Raise the default bound

**Files:**
- Modify: `corpus/src/pipeline.py`
- Test: `corpus/tests/test_pipeline.py`

- [ ] **Step 1: Change only the default parameter and describe the three-attempt bound.**

```python
def build_cell(
    key: str,
    sources: list[FetchedSource],
    *,
    client: LLMClient,
    max_attempts: int = 3,
    now: datetime | None = None,
) -> BuildOutcome:
```

Keep `_build_batch`, `REFUSAL_REASONS`, `rejected_block`, and `REJECTED_TIP_CHAR_LIMIT` unchanged.

- [ ] **Step 2: Run the focused tests.**

Run: `python -m pytest tests/test_pipeline.py -k "default_attempt_limit_is_three or explicit_attempt_limit_is_preserved"`

Expected: `2 passed`.

- [ ] **Step 3: Run the affected corpus suite.**

Run: `python -m pytest tests/test_pipeline.py`

Expected: all tests pass.

- [ ] **Step 4: Commit the implementation.**

```bash
git add corpus/src/pipeline.py corpus/tests/test_pipeline.py
git commit -m "fix(corpus): retry a rejected batch a third time"
```

### Task 3: Verify and publish the branch

**Files:**
- Modify: none
- Test: `corpus/tests/`

- [ ] **Step 1: Run the full corpus suite.**

Run: `python -m pytest`

Expected: all corpus tests pass.

- [ ] **Step 2: Inspect the committed diff.**

Run: `git status --short && git diff main...HEAD --check`

Expected: clean status and no whitespace errors.

- [ ] **Step 3: Push the remote branch.**

```bash
git push -u origin fix/retry-corpus-rejections
```

Expected: the remote tracking branch is created without rewriting history.
