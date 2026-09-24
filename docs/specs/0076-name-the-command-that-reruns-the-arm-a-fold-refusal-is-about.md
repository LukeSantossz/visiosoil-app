# SPEC: fix(ml): name the command that re-runs the arm a fold refusal is about

## Problem

When `load_arm_predictions` refuses an arm, it names a command that fails for
two arms. For a missing fold of the shuffled control, it names
`python -m src.crossval --arm shuffled_control`, and `require_control_matches_arm`
refuses that command. For the population probe, both the missing-fold hint and
the digest refusal name `src.crossval`, which has no arm by that name. The probe
is run by `scripts/run_population_probe.py`.

## Scope

- Includes:
  - One helper in `ml/src/crossval.py` that builds the re-run command from the
    arm directory: `--shuffled-control` for the control,
    `scripts/run_population_probe.py` for the population probe, and
    `src.crossval --arm <name>` for every other arm. Each command carries
    `--version <version>`.
  - Both refusals in `load_arm_predictions` use the helper: the missing-fold
    `FileNotFoundError`, and the digest refusal that SPEC 0074 added, which
    adds `--force`.
  - Tests for the three shapes, each asserting that the named command is one
    its entry point accepts.
- Does NOT include:
  - Any change to what is refused or when. Only the command in the message
    changes.
  - Refusal messages outside `load_arm_predictions`, such as the stale-fold
    plan in `plan_arm_run`.
  - The ablation and D6 arms. They are in `ARM_TRAINERS`, so
    `src.crossval --arm <name>` already runs them.
  - Any change to the scripts' command-line interfaces.

## Acceptance Criteria

- `a_missing_fold_names_a_command_the_arm_accepts`: for `descriptors`,
  `shuffled_control` and `population_probe`, the `FileNotFoundError` names a
  command that the arm's entry point parses and does not refuse, with the arm's
  version.
- `a_digest_refusal_names_a_command_the_arm_accepts`: the same three arms, for
  the digest refusal, and the command carries `--force`.
- `the_population_probe_is_rerun_by_its_own_script`: the probe's command is
  `python scripts/run_population_probe.py --version <version>`, and it contains
  no `src.crossval`.
