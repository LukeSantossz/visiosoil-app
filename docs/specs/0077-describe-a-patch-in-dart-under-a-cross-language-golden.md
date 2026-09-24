# SPEC: feat(descriptors): describe a patch in dart under a cross-language golden

## Problem

ADR 0024 ships the descriptor path as Dart arithmetic. Nothing in the app
computes a descriptor, and the ADR's third decision, a golden that the Dart
implementation must reproduce, does not exist yet. That golden tests the one
assumption that would reopen the runtime decision: that Dart can reproduce
numpy's 26 features closely enough that no prediction moves.

## Design Decision

**A pure-Dart port of `ml/src/descriptors.py`, one function with no Flutter
import, held to a golden that Python generates and both languages assert.** This
is item 1 of the map's post-gate order ("A6 Dart (1)"). It needs neither the
scale reader nor a released model.

**What is ported, number for number.** `describePatch(pixels, height, width)`
takes the single grey plane as `uint8` values in row-major order. It returns a
`Float64List` of 26 values, in the order of Python's `feature_names()`:

- `first_order`: mean, population standard deviation, skewness and excess
  kurtosis, with `[mean, 0, 0, 0]` when the deviation is zero.
- `spectral`: power in 8 radial bands whose edges are log-spaced from 2 cycles
  per patch to the Nyquist radius, normalised by the banded total, with zeros
  when the total is zero. A radius in `[edge_i, edge_{i+1})` goes to band `i`,
  the Nyquist radius itself goes to the top band, and anything past it is
  dropped. This is `searchsorted(side="right")` plus Python's closing rule.
- `lbp`: P = 8, R = 1, neighbours anticlockwise from east. A neighbour scores
  one when it is **at least** the centre. The rotation-invariant uniform mapping
  gives 10 bins, over interior pixels, as fractions.
- `glcm`: 16 levels by integer division by 16, symmetric counts over the offsets
  `(0,1) (-1,1) (-1,0) (-1,-1)`, and contrast, homogeneity, energy (the angular
  second moment, not its root) and correlation, averaged over the four offsets.
  Correlation is 1 when the marginal variance is zero.

The constants are Dart `const`s named after their Python counterparts. The
feature names are published as a list, and the golden asserts that list against
Python's.

**The spectrum is a separable direct DFT, not an FFT.** A 160 px side is
`2^5 × 5`, so a radix-2 FFT does not apply. The DFT runs over rows and then over
columns, reading one precomputed cosine and sine table of length `side`. That is
`2 × side³` multiply-adds: about 8.2 million for a 160 px patch, and about 200
million for the 25 patches of a full dish. It is the smallest implementation
whose error is easy to argue about. Each coefficient is a plain sum of `side`
products, with the twiddle read from a table indexed by `(k·n) mod side`, so the
error grows as `side · ε` and never compounds through stages. Speed is A7's
measurement (#215), made on a device. If A7 finds this too slow, a mixed-radix
FFT can replace the DFT behind the same function. The golden then re-proves the
replacement, and nothing else changes.

**The golden.** `ml/scripts/generate_descriptor_golden.py` writes
`test/fixtures/descriptors/golden.json`. It carries:

- the feature names;
- the eight band edges for each fixture shape;
- the fixtures themselves, each a name, a height and width, and its pixels as
  base64 of the raw `uint8` plane (no image codec stands between the two
  languages);
- the features `describe_patch` returns for each fixture.

The fixtures are generated from fixed seeds, so a rerun with no source change
writes a byte-identical file. They are chosen so that every branch of every group
is exercised:

| Fixture | Why |
|---|---|
| `pink_noise_160` | A texture whose power falls as 1/f, as a natural image's does. Every band carries energy. |
| `white_noise_160` | Energy spread evenly, and most LBP codes non-uniform. |
| `coarse_grains_160` | Blobs several pixels wide: low bands dominate, many GLCM pairs are equal. |
| `ramp_160` | A smooth gradient. Its LBP codes are almost all uniform. |
| `checkerboard_160` | Energy at a single frequency, and maximal GLCM contrast. |
| `flat_160` | One grey level: zero deviation, zero banded energy, correlation 1. |
| `ties_160` | Two grey levels in large runs, so LBP ties (`>=`) decide most codes. |
| `rectangle_37x53` | Not square and not 160, so no square-only shortcut can pass. |
| `smallest_banded_5x5` | The smallest side with a band: Nyquist 2.5 > 2. |

**The tolerance is SPEC 0030's:** `|dart − python| ≤ 1e-9·|python| + 1e-12`
for every feature. That is far inside any tolerance that could change a
prediction, because the standardiser divides by scales of order one and above.
So passing it shows the runtime decision stands, without needing a model to
measure it against. The band edges are held to the same tolerance. The generator
also refuses to write a fixture in which any radius falls within `1e-9` of an
interior edge. At such a radius, the last bit of a logarithm would pick the band,
and the two languages could disagree for no reason worth testing.

**Refusals mirror Python's.** An `ArgumentError` names the cause:

- a pixel buffer whose length is not `height × width`;
- a side below 3;
- a side whose Nyquist radius does not exceed 2 cycles per patch, which is a
  4 px side or less, so the spectral group has no band.

The colour-channel check in Python is not ported. The Dart function takes one
plane, and choosing that plane is the caller's job in A6 Dart (2).

## Alternatives Considered

- **A mixed-radix or Bluestein FFT now.** Rejected for this spec. It is faster,
  but it puts a stage structure between the definition and the answer before
  anything shows the direct form is too slow. A7 decides that, and the golden is
  what would make the swap safe.
- **A Dart FFT package from pub.** Rejected. The one that fits (`fftea`) handles
  any size, but it adds a dependency whose conventions (normalisation, sign of
  the exponent, output layout) the port would have to match on trust. The
  quantity used is only power per band, which a direct DFT computes in a few
  lines.
- **PNG fixtures, as SPEC 0030 used.** Rejected. A decoder would sit between the
  two languages. Raw bytes in base64 are the plane itself, and a 160 px plane is
  about 34 kB of JSON.
- **Real archive patches as fixtures.** Rejected. The archive belongs to the
  laboratory and is not in the repository. Synthetic fixtures chosen per branch
  exercise every path, and the tolerance makes the argument without real
  photographs.
- **Carrying the class distribution in this golden too**, which ADR 0024 names
  alongside the features. Deferred, not rejected. The standardiser and the
  regression are numbers A4 defines and B3 fits, and neither exists yet. Their
  part of the golden lands with them.

## Scope

- Includes:
  - `lib/core/services/descriptors/patch_descriptors.dart`: `describePatch`,
    `descriptorFeatureNames`, the fixed-point constants and the band edges, with
    no Flutter import.
  - `ml/scripts/generate_descriptor_golden.py` and
    `test/fixtures/descriptors/golden.json`.
  - `test/services/patch_descriptors_test.dart`, and
    `ml/tests/test_descriptor_golden.py`, which asserts that Python still
    reproduces the committed golden, so drift on either side fails the other
    side's suite.
- Does NOT include:
  - The scale reader, the resample to canonical, the patch grid, or choosing the
    grey plane from a photograph. Those are A6 Dart (2).
  - The standardiser, the regression, the averaging over patches, or any
    `spec.json` field. Those are A4 and B3.
  - Wiring into `InferenceService`, running in an isolate, or any UI.
  - Any change to `ml/src/descriptors.py`. The golden is written against the
    reference as it stands. If the port finds a defect in it, the defect is
    reported and not fixed here.
  - A performance budget or benchmark. That is A7's measurement.

## Acceptance Criteria

- `dart_descriptors_match_the_golden`: for every fixture, each of the 26 Dart
  features is within the tolerance of the golden's.
- `dart_feature_names_match_python`: `descriptorFeatureNames` equals the
  golden's list, in order.
- `dart_band_edges_match_python`: for each fixture shape, the Dart band edges
  are within the tolerance of the golden's.
- `python_reproduces_the_golden`: `describe_patch` over each committed fixture
  equals the golden's features within the tolerance, and the feature names and
  edges equal the golden's.
- `golden_generation_is_deterministic`: generating the golden twice gives
  identical JSON.
- `no_fixture_radius_sits_on_a_band_edge`: no frequency radius of any fixture
  shape is within `1e-9` of an interior band edge.
- `golden_exercises_every_degenerate_branch`: the golden holds a fixture with
  zero deviation, one with zero banded energy, one with zero GLCM variance, and
  a non-square one.
- `a_patch_with_no_band_is_refused`: a 4×4 patch raises an `ArgumentError`
  naming the spectral band, and a 5×5 patch is described.
- `a_patch_below_the_minimum_side_is_refused`: a 2-pixel side raises an
  `ArgumentError`.
- `a_buffer_of_the_wrong_length_is_refused`: a buffer whose length is not
  `height × width` raises an `ArgumentError`.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe scripts/generate_descriptor_golden.py
cd ml && .venv/Scripts/python.exe -m pytest tests/test_descriptor_golden.py -q
flutter test test/services/patch_descriptors_test.dart
flutter analyze
mf check
```

Python 3.12 with the pinned stack in `ml/requirements.txt`, and numpy's
`pocketfft`. Flutter 3.44.1 and Dart 3.12.1, as pinned in CI.

## Risks and Assumptions

- **Assumption:** the direct DFT's error, of order `side · ε` relative to a
  coefficient, stays inside `1e-9` relative after the banded normalisation. At a
  160 px side that is about `4e-14`, four orders of magnitude inside the bound.
- **Risk:** the direct DFT is slow on a device, at about 200 million
  multiply-adds per dish. That is not this spec's gate. It is recorded for A7,
  and the FFT alternative above is how it would be met.
- **Risk:** a band edge that numpy's `geomspace` computes differently in its last
  bit from Dart's `pow`. It is caught twice: by the edge criterion, and by the
  generator's refusal to place a radius near an edge.
- **What would invalidate this spec:** a fixture on which the two languages
  disagree beyond the tolerance for a reason that cannot be removed. That is the
  finding ADR 0024 names as reopening the runtime, and it would be reported as
  such rather than absorbed into a wider tolerance.
