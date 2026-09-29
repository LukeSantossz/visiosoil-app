"""The cells the corpus is built of, derived rather than written down twice.

ADR 0022 names the coupling this exists to guard: if a future ADR changes the
four classes, cells for changed classes are orphaned, so **the build derives keys
from the model's class list rather than from a literal**, and the breakage is
loud. A list repeated here would satisfy itself while the corpus drifted away
from the model it is keyed to. ADR 0022 named `SoilTextureLabels.ordered`; since
SPEC 0083 the app has no class list of its own and labels a result with the
shipped contract's classes, so that is what the corpus reads.

The other three vocabularies are the design's own — clay-activity families,
land uses, federative units and biomes — and they are literals here because
nothing else in the repository owns them.
"""

from __future__ import annotations

import json
from pathlib import Path

LABELS_PATH = (
    Path(__file__).resolve().parent.parent.parent
    / "assets"
    / "models"
    / "spec.json"
)

CLAY_ACTIVITIES = ("tb_oxidic", "intermediate", "ta_less_weathered")
"""The three families of §5.1, split at 27 cmolc/kg of clay (SiBCS Ta/Tb)."""

LAND_USES = (
    "native_vegetation",
    "pasture",
    "annual_crop",
    "perennial_or_forest",
    "exposed_or_degraded",
)

BIOMES = (
    "amazonia",
    "cerrado",
    "mata_atlantica",
    "caatinga",
    "pampa",
    "pantanal",
)

UNITS = (
    "BR-AC", "BR-AL", "BR-AM", "BR-AP", "BR-BA", "BR-CE", "BR-DF",
    "BR-ES", "BR-GO", "BR-MA", "BR-MG", "BR-MS", "BR-MT", "BR-PA",
    "BR-PB", "BR-PE", "BR-PI", "BR-PR", "BR-RJ", "BR-RN", "BR-RO",
    "BR-RR", "BR-RS", "BR-SC", "BR-SE", "BR-SP", "BR-TO",
)


def read_texture_classes(path: Path | None = None) -> list[str]:
    """The class list the model emits, read from the contract the app ships.

    Fails loudly rather than falling back to a literal: a corpus keyed to a class
    list nobody can find is a corpus keyed to nothing.
    """
    source = Path(path) if path is not None else LABELS_PATH
    document = json.loads(source.read_text(encoding="utf-8"))
    classes = document.get("classes") if isinstance(document, dict) else None
    if not isinstance(classes, list) or not classes:
        raise ValueError(
            f"{source} carries no `classes` list; the corpus derives its keys "
            f"from that list and will not guess at one"
        )
    if not all(isinstance(name, str) and name for name in classes):
        raise ValueError(f"{source} carries `classes` that are not all names")
    return list(classes)


def substance_key(texture_class: str, clay_activity: str) -> str:
    """The key of one substance cell, in the shape the app looks it up by."""
    return f"{texture_class}|{clay_activity}"


def substance_keys(path: Path | None = None) -> list[str]:
    """Every substance cell: each class against each clay-activity family."""
    return [
        substance_key(texture_class, activity)
        for texture_class in read_texture_classes(path)
        for activity in CLAY_ACTIVITIES
    ]
