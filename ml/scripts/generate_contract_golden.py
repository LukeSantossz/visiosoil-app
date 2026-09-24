"""Generate the descriptor-contract golden (SPEC 0079).

Writes `test/fixtures/contract/golden.json`: a contract written by
`src.contract.descriptor_contract` from the real `arms.probe.fit_probe` fitted on
seeded synthetic features, and a few photographs — blocks of patch feature rows
— each with the distribution the fitted pipeline gives it. The Dart reader must
reproduce every distribution.

The fit is not byte-stable across the scikit-learn versions the requirements
allow, so this file is not compared with a regeneration. `tests/test_contract.py`
asserts that it is consistent with itself instead.

Run from the `ml/` directory:

    python scripts/generate_contract_golden.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from src.arms.probe import fit_probe  # noqa: E402
from src.config import load_config  # noqa: E402
from src.contract import descriptor_contract  # noqa: E402
from src.descriptors import feature_names  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
GOLDEN_PATH = REPO_ROOT / "test" / "fixtures" / "contract" / "golden.json"

#: Patches per golden photograph: one, the grid's floor, a full dish.
PHOTOGRAPH_SIZES = {"one_patch": 1, "the_grid_floor": 9, "a_full_dish": 25}


def build_golden() -> dict:
    cfg = load_config()
    classes = len(cfg["classes"])
    width = len(feature_names())
    rng = np.random.default_rng(79)

    centres = rng.normal(0.0, 2.0, size=(classes, width))
    labels = np.repeat(np.arange(classes), 40)
    features = centres[labels] + rng.normal(0.0, 1.0, size=(len(labels), width))
    pipeline = fit_probe(features, labels, c=1.0)
    contract = descriptor_contract(
        pipeline, cfg, model_version="golden", dataset_version="synthetic"
    )

    photographs = []
    for index, (name, count) in enumerate(PHOTOGRAPH_SIZES.items()):
        # Centred on one class, so the distributions are not all flat.
        patches = centres[index % classes] + rng.normal(0.0, 4.0, size=(count, width))
        photographs.append(
            {
                "name": name,
                "patches": [[float(value) for value in row] for row in patches],
                "distribution": [
                    float(value) for value in pipeline.predict_proba(patches).mean(axis=0)
                ],
            }
        )
    return {
        "spec": "0079",
        "generator": "ml/scripts/generate_contract_golden.py",
        "tolerance": {"relative": 1e-9, "absolute": 1e-12},
        "contract": contract,
        "photographs": photographs,
    }


def main() -> None:
    GOLDEN_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(GOLDEN_PATH, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(build_golden(), indent=2) + "\n")
    print(f"wrote {GOLDEN_PATH}")


if __name__ == "__main__":
    main()
