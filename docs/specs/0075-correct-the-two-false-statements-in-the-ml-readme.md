# SPEC: docs(ml): correct the two false statements in the ml readme

## Problem

`ml/README.md` says that the dataset manifest is committed, and names
`keras==3.14.0` as a key pin. Both are false. ADR 0019 commits nothing under
`ml/data/datasets/`, the manifest included — `git ls-files ml/data/datasets/`
prints nothing. And `ml/requirements.txt` pins `keras==3.15.1`, which SPEC 0060
moved it to.

A reader setting up a machine therefore installs the wrong Keras and expects a
manifest the checkout does not carry. `test_requirements.py` then skips rather
than fails, which hides the first mistake.

## Scope

- Includes:
  - `ml/README.md`, two sentences:
    - line 36 states that nothing under `ml/data/datasets/` is committed, and
      that the class counts beside it are a measurement no CI run can re-check;
    - line 125 names the Keras version `requirements.txt` pins.
  - `ml/tests/test_requirements.py`: the two criteria below, reusing its
    `parse_pins`. Both read files only, so neither skips when the installed stack
    diverges.
- Does NOT include:
  - Any other sentence of `ml/README.md`. Issue #238 checked the other versions
    it names — `tensorflow==2.21.0`, `tf-keras==2.21.0` and the scikit-learn
    range `>=1.3.0,<1.6.0` — and all match.
  - `ml/requirements.txt`, or any pin.
  - The verdicts that record Keras 3.14.0 as the stack their arms ran under.
    `docs/ml/e0-verdict.md` and `docs/ml/transported-population-sensitivity.md`
    are right about history, and are not pins.

## Acceptance Criteria

- `the_readme_claims_no_dataset_file_is_committed`: no sentence of
  `ml/README.md` says that the manifest, or anything else under the dataset
  directory, is committed, unless the same sentence negates it.
- `every_version_the_readme_names_is_the_pinned_one`:
  - every `name==version` and `name>=low,<high` specifier `ml/README.md` names
    equals the specifier `ml/requirements.txt` gives that distribution;
  - a bare range with no name must appear in `requirements.txt` verbatim.
