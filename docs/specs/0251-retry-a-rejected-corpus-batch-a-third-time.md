# SPEC: fix(corpus): retry a rejected corpus batch a third time

## Problem

The corpus builder stops after two generated attempts even when its second prompt already names exactly why the first attempt was rejected, so a grounded correction has no final bounded opportunity to replace a refused claim.

## Design Decision

`build_cell` defaults `max_attempts` to three. The existing batch loop, rejection reasons, prompt-size cap, and feedback block remain unchanged: the third attempt receives only the reasons produced by the second attempt. Callers that explicitly pass a limit retain that limit, so probes that need two attempts remain deterministic.

## Alternatives Considered

- Apply the uncommitted change from worktree 0232. Rejected because it predates the current batch architecture and would remove its prompt-size and rejection-feedback safeguards.
- Retry without a bound. Rejected because a model that cannot ground a claim would consume unbounded time and resources.
- Keep two attempts. Rejected because a correction that follows the second rejection is needlessly discarded.

## Scope

- Includes:
  - `corpus/src/pipeline.py`: change only the default attempt bound from two to three and its documentation;
  - `corpus/tests/test_pipeline.py`: prove the default reaches and uses a third attempt, and that an explicit bound still wins.
- Does NOT include:
  - prompt wording, `OllamaClient`, rejection reasons, batch size, or the prompt-size limit;
  - rebuilding or publishing `assets/corpus/`;
  - any mobile-app behavior.

## Acceptance Criteria

- `default_attempt_limit_is_three`: two refused attempts followed by a supported third attempt produce a grounded cell with `attempts == 3`; the third prompt receives the second refusal's feedback.
- `explicit_attempt_limit_is_preserved`: a caller passing `max_attempts: 2` stops after two attempts even when a third scripted response is available.
- `corpus/tests/test_pipeline.py` passes under Python 3.12.

## Reproducibility

Python 3.12. Run `python -m pytest tests/test_pipeline.py` from `corpus/`, then `python -m pytest` from `corpus/`.

## Risks and Assumptions

- **Cost and latency:** a failed batch can make one additional local-model call. The three-attempt bound limits that cost.
- **Assumption:** a second rejection contains feedback sufficient for a third attempt to correct; a third failure still abstains.
