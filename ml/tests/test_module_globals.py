"""Every global a function loads is bound in the module that defines it.

Written because `train_fold` called `withhold_from_training` without importing
it, and nothing caught it: every test that exercises withholding goes through
`arms.probe.probe_fold`, which does import it, and the CNN path that does not
needs TensorFlow and the real archive. The defect would have surfaced as a
`NameError` some minutes into a thirteen-hour arm.

A `NameError` from a missing import is invisible to the interpreter until the
line runs, so the only cheap way to find one is to read the bytecode. Every
`LOAD_GLOBAL` a function emits names something that must exist in its module's
namespace at call time; anything that is neither there nor a builtin is a line
that will raise when reached.

Cheaper than a linter dependency and narrower than one: it makes no style claim
and reports exactly the defect that cost this suite a blocking bug.
"""

import builtins
import dis
import importlib
import types
from pathlib import Path

import pytest

from tests.support import requires_tensorflow

SRC = Path(__file__).resolve().parents[1] / "src"


def _module_names():
    """Every importable module under `src/`, as a dotted name."""
    for path in sorted(SRC.rglob("*.py")):
        if path.name == "__init__.py":
            continue
        relative = path.relative_to(SRC.parent).with_suffix("")
        yield ".".join(relative.parts)


def _code_objects(code: types.CodeType):
    """``code`` and every function nested inside it, however deeply."""
    yield code
    for constant in code.co_consts:
        if isinstance(constant, types.CodeType):
            yield from _code_objects(constant)


def _functions_defined_in(module):
    """Functions and methods whose source is this module's own file.

    Filtered on `co_filename` and not on `__module__`. The two differ for
    everything a decorator or a metaclass synthesises: a `@dataclass`'s
    `__repr__`, an `Enum` subclass's `__new__` and a `Protocol`'s `__init__` all
    claim the module that declared the class while their bytecode comes from the
    standard library — and they load globals bound in *their* module, not in
    this one. Checking those would report the standard library as broken.
    """
    source = module.__file__

    for value in vars(module).values():
        if isinstance(value, types.FunctionType):
            if value.__code__.co_filename == source:
                yield value
        elif isinstance(value, type) and value.__module__ == module.__name__:
            for attribute in vars(value).values():
                if (
                    isinstance(attribute, types.FunctionType)
                    and attribute.__code__.co_filename == source
                ):
                    yield attribute


@requires_tensorflow
@pytest.mark.parametrize("name", sorted(_module_names()))
def test_no_function_loads_an_unbound_global(name):
    """A missing import is a `NameError` waiting for the line to be reached."""
    module = importlib.import_module(name)
    namespace = vars(module)

    unbound = []
    for function in _functions_defined_in(module):
        for code in _code_objects(function.__code__):
            for instruction in dis.get_instructions(code):
                if instruction.opname != "LOAD_GLOBAL":
                    continue
                loaded = instruction.argval
                if loaded in namespace or hasattr(builtins, loaded):
                    continue
                unbound.append(f"{code.co_qualname} loads {loaded!r}")

    assert unbound == [], (
        f"{name} has {len(unbound)} unbound global load(s), each a NameError "
        f"when its line is reached:\n  - " + "\n  - ".join(sorted(set(unbound)))
    )
