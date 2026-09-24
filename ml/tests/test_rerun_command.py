"""SPEC 0076: a fold refusal names a command that re-runs the arm it is about.

`load_arm_predictions` refuses an arm with a missing fold, and an arm scored
against another manifest, and both refusals name the command that fixes it. A
command its entry point refuses sends the operator somewhere that does not work,
so each test asserts that the named command is one its entry point accepts.
"""

from __future__ import annotations

import json

import pytest

from src.crossval import (
    ARM_TRAINERS,
    PREDICTIONS_FILENAME,
    SHUFFLED_CONTROL_ARM,
    default_arm_name,
    fold_directory,
    load_arm_predictions,
    require_control_matches_arm,
)
from src.population_probe import POPULATION_PROBE_ARM
from tests.test_crossval import folds  # noqa: F401 - `folds` is a fixture
from tests.test_gate_criteria import _write_arm

ARMS = ("descriptors", SHUFFLED_CONTROL_ARM, POPULATION_PROBE_ARM)
VERSION = "v1"


def _command(message: str, lead: str) -> list[str]:
    """The command a refusal names, as its tokens."""
    return message.split(lead, 1)[1].split()


def _accepts(command: list[str], arm: str) -> None:
    """Assert the command's entry point parses it and runs `arm`."""
    if command[:2] == ["python", "scripts/run_population_probe.py"]:
        import scripts.run_population_probe as probe_script

        args = probe_script.parse_args(command[2:])
        assert arm == POPULATION_PROBE_ARM
        assert args.version == VERSION
        return

    assert command[:3] == ["python", "-m", "src.crossval"]
    shuffled = "--shuffled-control" in command
    named = command[command.index("--arm") + 1] if "--arm" in command else None
    resolved = default_arm_name(named, shuffled)
    require_control_matches_arm(resolved, shuffled)
    assert resolved in ARM_TRAINERS
    assert resolved == arm
    assert command[command.index("--version") + 1] == VERSION


@pytest.mark.parametrize("arm", ARMS)
def test_a_missing_fold_names_a_command_the_arm_accepts(tmp_path, folds, arm):  # noqa: F811
    arm_dir = tmp_path / "models" / VERSION / arm
    _write_arm(arm_dir, folds)
    (fold_directory(arm_dir, 0, 1) / PREDICTIONS_FILENAME).unlink()

    with pytest.raises(FileNotFoundError, match="repeat 0 fold 1") as raised:
        load_arm_predictions(arm_dir, folds)
    _accepts(_command(str(raised.value), "Run the arm with: "), arm)


@pytest.mark.parametrize("arm", ARMS)
def test_a_digest_refusal_names_a_command_the_arm_accepts(tmp_path, folds, arm):  # noqa: F811
    arm_dir = tmp_path / "models" / VERSION / arm
    _write_arm(arm_dir, folds, digest_of=lambda repeat, fold: "a" * 64)

    with pytest.raises(ValueError) as raised:
        load_arm_predictions(arm_dir, folds)
    command = _command(str(raised.value), "Re-run the arm: ")
    _accepts(command, arm)
    assert "--force" in command


def test_the_population_probe_is_rerun_by_its_own_script(tmp_path, folds):  # noqa: F811
    arm_dir = tmp_path / "models" / VERSION / POPULATION_PROBE_ARM
    _write_arm(arm_dir, folds)
    path = fold_directory(arm_dir, 0, 0) / PREDICTIONS_FILENAME
    record = json.loads(path.read_text())
    record["manifest_digest"] = "a" * 64
    path.write_text(json.dumps(record))

    with pytest.raises(ValueError) as raised:
        load_arm_predictions(arm_dir, folds)
    message = str(raised.value)
    assert f"python scripts/run_population_probe.py --version {VERSION}" in message
    assert "src.crossval" not in message
