"""Reading the clay-activity family from a SiBCS class name.

The national soil map is classified to SiBCS's **third categorical level**, the
grandes grupos — and that level is itself defined with emphasis on clay activity
and base saturation, at the same 27 cmolc/kg threshold the design uses. So the
family is constitutive of the class name rather than something to infer from
outside it.

**The rule is order first, qualifier second**, and the order matters. `Ta`/`Tb`
appears in a great-group name only where it *differentiates*. Where the order
already implies the activity, the name carries no qualifier at all: a Latossolo is
low-activity by the definition of its own B horizon. Searching a Latossolo's name
for "Tb" finds nothing and would resolve it to unknown — in the most common order
of the Cerrado, which is where the `Argilosa|tb_oxidic` cell lives.

Where neither the order nor a qualifier settles it, the answer is null. §5.2
defines that as valid and not fatal: the substance layer answers generically and
the response says so.
"""

from __future__ import annotations

import re

TB = "tb_oxidic"
TA = "ta_less_weathered"
INTERMEDIATE = "intermediate"

_ORDER_DEFAULTS: dict[str, str | None] = {
    # Low-activity by the definition of the order itself, so the name carries no
    # qualifier and none should be looked for.
    "latossolo": TB,
    "nitossolo": TB,
    # Ta/Tb differentiates within these orders, so the qualifier decides and the
    # default is only what holds in its absence.
    "argissolo": TB,
    "cambissolo": INTERMEDIATE,
    "chernossolo": TA,
    "luvissolo": TA,
    "planossolo": INTERMEDIATE,
    "plintossolo": INTERMEDIATE,
    "vertissolo": TA,
    "espodossolo": TB,
    "gleissolo": INTERMEDIATE,
    # Neither the order nor, usually, a qualifier settles the activity of the
    # clay fraction — often because there is barely a clay fraction to speak of.
    "neossolo": None,
    "organossolo": None,
}

_UNACCENTED = str.maketrans(
    "áàãâäéêèëíîìïóôõòöúûùüçñ", "aaaaaeeeeiiiiooooouuuucn"
)


def _normalise(value: str) -> str:
    return value.strip().lower().translate(_UNACCENTED)


def family_for_soil_class(name: str | None) -> str | None:
    """The clay-activity family named by [name], or null.

    Null is an answer, not a failure: an order the system does not resolve and a
    class name nothing recognises both mean the substance layer answers
    generically rather than guessing.
    """
    if not name:
        return None
    normalised = _normalise(name)

    order = next(
        (key for key in _ORDER_DEFAULTS if normalised.startswith(key)), None
    )
    if order is None:
        return None

    # The qualifier outranks the order's default: it is the measurement, while
    # the default is an inference from the order. Matched as a whole token —
    # as a substring it would be found inside words and mislabel the unit.
    if re.search(r"\bta\b", normalised):
        return TA
    if re.search(r"\btb\b", normalised):
        return TB

    return _ORDER_DEFAULTS[order]
