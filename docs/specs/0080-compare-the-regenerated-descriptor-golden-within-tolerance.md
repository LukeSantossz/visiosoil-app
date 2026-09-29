# SPEC: fix(ml): compare the regenerated descriptor golden within tolerance, not byte for byte

## Problem

`test_golden_generation_is_deterministic` requires a regeneration of SPEC 0077's
descriptor golden to equal the committed file byte for byte, but numpy 1.26
computes `log10` and `power` with different last digits on a CPU with AVX-512,
so the test fails on those CI runners with no source change. Two runs on PR #258
failed this way. The band edges came out as `7.976318593271211` and
`12.649110640673513`, and the committed values are `7.97631859327121` and
`12.649110640673515`. The same numpy on Linux reproduces the CI values on an
AVX-512 CPU, and it reproduces the committed ones once
`NPY_DISABLE_CPU_FEATURES` turns the AVX-512 kernels off. SPEC 0077's claim
that "a rerun with no source change writes a byte-identical file" therefore
holds only on one machine.

## Scope

- Includes:
  - `ml/tests/test_descriptor_golden.py`:
    - `test_golden_generation_is_deterministic` keeps its byte-for-byte check
      between two generations in one process.
    - It compares the generation with the committed file field by field. Every
      floating-point number must be within SPEC 0030's tolerance,
      `1e-9·|expected| + 1e-12`. Everything else must be equal exactly: keys,
      lengths, strings (names, base64 pixels, band maps), integers and types.
    - The comparison is a helper in the same file.
  - The docstring of `ml/scripts/generate_descriptor_golden.py`, which makes the
    same byte-identity claim.
- Does NOT include:
  - Regenerating or editing `test/fixtures/descriptors/golden.json`.
  - Any change to `src.descriptors`, `patch_descriptors.dart`, or the Dart
    golden tests. The Dart tests already compare within the tolerance.
  - The contract golden of SPEC 0079, which is never compared byte for byte.
  - Rounding the golden's numbers so that a byte comparison would pass. A value
    near a rounding boundary would still flip on another CPU.
  - Pinning numpy's CPU dispatch in CI. That would hide the drift instead of
    tolerating it, and a developer's machine could still differ.
  - Editing SPEC 0077's text. This spec narrows its byte-identity sentence.

## Acceptance Criteria

- `golden_generation_is_deterministic`: two generations in one process are
  identical JSON, and the generation matches the committed golden within the
  tolerance.
- `golden_comparison_tolerates_last_digit_drift`: a golden whose floats differ
  from the generation by a few units in the last place matches it.
- `golden_comparison_catches_a_real_change`: the comparison reports a mismatch
  in each of these cases:
  - a float moved beyond the tolerance;
  - a changed string, such as a pixel plane, a band map or a feature name;
  - a changed integer;
  - an integer where a float was;
  - a list of another length;
  - a missing or extra key.
