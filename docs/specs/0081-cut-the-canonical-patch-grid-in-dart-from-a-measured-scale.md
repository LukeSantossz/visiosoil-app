# SPEC: feat(descriptors): cut the canonical patch grid in dart from a measured scale

## Problem

Dart cannot yet turn a photograph into the patches the descriptor path scores.
Nothing resamples to the canonical scale, converts to grey, lays out the grid or
cuts it. So ADR 0024's classifier has its features (SPEC 0077) and its contract
(SPEC 0079) but no input, and training (SPEC 0053) and inference still disagree
about what a patch is. This is the first half of A6 Dart (2) in the
implementation map. The second half, the A4-sheet reader that measures the scale
on the device, is a later spec.

## Design Decision

**Given a measured scale and a located region, Dart cuts the same patches Python
cuts, byte for byte.** `ml/src/dataset.py`'s `_photograph_patches` is the
reference. After decoding and orienting the photograph, it does five things:

1. It moves the region's centre and diameter into canonical pixels.
2. It resamples the RGB photograph to the canonical millimetres per pixel with
   Pillow's `BILINEAR` filter.
3. It converts to grey with the BT.601 luma, rounded half to even.
4. It lays out the grid from the region's centre.
5. It refuses a grid that leaves the frame, and cuts.

`lib/core/services/descriptors/patch_grid.dart` ports each step exactly, not
approximately. Exact is possible because nothing in this chain calls a libm
function: it is IEEE arithmetic and integers, which is the property SPEC 0080
found missing in `np.geomspace`.

**The resample is Pillow's `BILINEAR`, ported.** The Developer promoted this
decision at the Spec Gate as
[ADR 0025](../adr/0025-the-dart-resample-reproduces-pillows-bilinear-byte-for-byte.md).
Pillow 10.4's
`libImaging/Resample.c` works like this:

- It widens the triangle filter's support by the reduction factor, so a
  downsample averages its whole footprint. That is the low-pass #180 asks for.
- It computes each output pixel's coefficients in `double`, using only `+`, `−`,
  `×`, `÷` and `ceil`.
- It converts them to 22-bit fixed point, rounding away from zero.
- It runs a horizontal pass and then a vertical pass, each accumulating in
  integers and clipping to `uint8`.

The Dart port reproduces the same operations in the same order.

This reverses the alternative SPEC 0037 rejected, a shared cross-language
kernel. It was rejected when a network read the pixels through a resize whose
skew nothing had measured. Under ADR 0024 the pixels feed the spectral bands,
LBP and GLCM directly. E0's ablation found that LBP alone carries 15.6 points,
and the descriptors are held to Python at `1e-9`. A different kernel at the
input would give that precision back at the step where the signal starts.

**Every rounding is Python's.** Python's `round` and numpy's `rint` round half
to even, and Dart's `round` rounds half away from zero. The difference is not
theoretical: **13,178 RGB triples give a BT.601 luma of exactly .5 in float64**.
One is `(0, 0, 250)`, whose luma is 28.5; `rint` makes it 28 and Dart's `round`
makes it 29. Four places round:

- the resampled frame's size;
- the luma;
- a patch's top-left corner;
- the frame check, which uses the same corner.

Dart uses one half-to-even helper for all four. The grid's step count is
Python's float floor division `limit // stride`, which is not always
`floor(limit / stride)` (`1 // 0.1` is 9 while `1 / 0.1` is 10.0). Dart
reproduces CPython's definition rather than relying on the stride happening to
make the two agree.

**The one step Dart does not reproduce bit for bit is `math.hypot`.** A patch
centre is kept when its distance from the region's centre is at most
`limit + 1e-9`. CPython's `hypot` is correctly rounded in almost every case;
Dart has no `hypot`, and `sqrt(dy² + dx²)` can differ in the last place. So the
two languages can disagree only for a region whose limit sits within about one
ulp of a patch centre's distance, around `1e-13` px. The golden refuses a
geometry case with a centre within `1e-6` px of its limit, as SPEC 0077 does for
band edges, and the risk is recorded below.

**One luma definition.** The BT.601 coefficients move out of
`image_quality_analyzer.dart`'s private constants into one shared declaration,
and both the analyzer and the grid read it. This is SPEC 0037's criterion that
the model path and the quality-analyzer path call the same definition. The
analyzer's behaviour does not change.

**The refusals are named, never a fallback.** Each mirrors a `PatchRefusal` in
`ml/src/patches.py`:

- `tooCoarse`: the photograph is coarser than the canonical, so reaching the
  canonical would upsample;
- `regionTooSmall`: the region carries fewer than `min_patches`;
- `outsideFrame`: the grid does not fit in the frame.

They are this module's own enum. Turning them into ADR 0015 causes belongs to
the wiring, which amends ADR 0015's table when it does.

**Inputs and outputs.**

- **In:**
  - an RGB frame as an interleaved `Uint8List` with its width and height,
    already decoded and oriented;
  - the measured millimetres per pixel;
  - the region's centre and diameter, in that frame's pixels;
  - the four geometry values the contract carries: `canonical_mm_per_px`,
    `patch_px`, `patch_stride_fraction` and `min_patches`.
- **Out:** the refusal, or the patches as grey `Uint8List` planes of
  `patch_px × patch_px`, in Python's order (offsets sorted), which
  `describePatch` takes as they are.

Python's three replicated channels are not reproduced. They exist for a
network's input tensor, which the descriptor path does not have, and
`describe_patch` reduces them to one plane before it reads anything.

**The golden.** `ml/scripts/generate_patch_golden.py` writes
`test/fixtures/patches/golden.json` from `src.patches` itself. It holds four
kinds of case:

- **resample:** small RGB frames from fixed seeds, resampled at several ratios,
  with the resampled bytes. One ratio leaves the frame unchanged, one makes an
  output side round half-way, and one reduces by more than half;
- **luma:** a sample of the triples that land exactly on .5, with the values
  numpy rounds them to;
- **geometry:** ADR 0018's table at the real configuration, 160 px at the
  canonical scale, where discs of 70, 80 and 90 mm carry 9, 21 and 25 patches.
  Also the floor boundary: the largest diameter refused and the smallest
  accepted. Each case has its count, stride, inset and offsets, or its refusal;
- **pipeline:** whole photographs cut at a 16 px patch, so every patch byte fits
  in the file. Each case is a frame, a measured scale and a region, with either
  the patches in order or the refusal. Every refusal appears at least once.

The Python tests assert that `src.patches` reproduces the golden, and they
compare a regeneration with the committed file by SPEC 0080's rule.

## Alternatives Considered

- **The `image` package's `Interpolation.average`**, which #180 proposed.
  Rejected. It is one line and a box filter, while training used a triangle
  filter, so every descriptor would read a different low-pass than the one the
  model was fitted on, by an amount nobody has measured.
- **`copyResize` with linear interpolation**, what `InferenceService` uses
  today. Rejected: it reads four source pixels per output pixel, so the
  downsample aliases (#180).
- **A simpler kernel both languages share, such as area averaging, adopted on
  the Python side too.** Rejected. It changes the training input, and the E0
  verdict and every fold artefact were computed on Pillow's `BILINEAR`.
- **A pipeline golden at the real 160 px.** Rejected. One photograph would be 25
  patches of 25.6 KB. The code has no branch that depends on the patch size, and
  the real configuration's geometry is asserted by the geometry cases.
- **Three identical channels, as Python returns them.** Rejected for the reason
  above.
- **Porting CPython's `hypot` to Dart.** Rejected. It is disproportionate for a
  `1e-13` px boundary that the golden already keeps its cases away from.
- **The dispersion metric here.** Deferred to the wiring by the Developer on
  2026-09-29. It has no Python reference, no consumer and no calibrated
  threshold.
- **The A4-sheet reader first.** Deferred by the Developer on 2026-09-29. No
  photograph with an A4 sheet exists, so it could only be tested on synthetic
  images, and the grid is deterministic and has a reference today.

## Scope

- Includes:
  - `lib/core/services/descriptors/patch_grid.dart`:
    - `PatchRefusal`;
    - the Pillow `BILINEAR` resample;
    - the grey plane;
    - the geometry;
    - the frame check;
    - the cut;
    - `canonicalPatches`, which composes them as `_photograph_patches` does,
      including `_canonical_region`'s move of the region into canonical pixels.
  - A shared BT.601 declaration under `lib/core/services/image_quality/`, and
    the analyzer reading it.
  - `ml/scripts/generate_patch_golden.py`, `test/fixtures/patches/golden.json`,
    `ml/tests/test_patch_golden.py` and `test/services/patch_grid_test.dart`.
  - `docs/architecture/ml-implementation-map.md`: A6 Dart (2) split in two, and
    the dispersion metric moved to the wiring.
- Does NOT include:
  - The A4-sheet reader, the homography, or locating the soil on the paper.
    That is the next spec.
  - Decoding the file, or its EXIF orientation. That is the wiring.
  - The dispersion metric. That is the wiring.
  - Calling this from `InferenceService`, replacing the TFLite path, or mapping
    the refusals into `ClassificationFailureCause`. That is the wiring.
  - Any change to `src.patches`, `src.dataset`, `patch_descriptors.dart` or
    `descriptor_contract.dart`.
  - The difference between Dart's JPEG decoder and Pillow's. It is a risk,
    below.
  - The cost on a device. That is A7.

## Acceptance Criteria

Dart:

- `dart_resample_matches_pillow`: every golden resample case, byte for byte.
- `dart_luma_matches_python`: every golden luma case, including those on .5.
- `dart_geometry_matches_python`: every golden geometry case, meaning the same
  count, stride, inset and offsets, or the same refusal.
- `dart_patches_match_python`: every golden pipeline case, meaning the same
  patches byte for byte and in the same order, or the same refusal.
- `a_photograph_coarser_than_the_canonical_is_refused`: it is never upsampled,
  and a photograph already at the canonical scale is cut without being
  resampled.
- `floor_division_is_pythons`: `1 // 0.1` is 9, and a case where the two
  definitions agree still agrees.
- `one_luma_definition_in_lib`: the BT.601 coefficients are declared in exactly
  one file under `lib/`.

Python:

- `python_reproduces_the_patch_golden`: `src.patches` reproduces every case.
- `patch_golden_generation_is_deterministic`: two generations are identical,
  and one matches the committed file by SPEC 0080's rule.
- `no_geometry_case_sits_on_the_hypot_boundary`: no patch centre in any
  geometry or pipeline case is within `1e-6` px of its limit.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe scripts/generate_patch_golden.py
cd ml && .venv/Scripts/python.exe -m pytest tests/test_patch_golden.py -q
flutter test test/services/patch_grid_test.dart
flutter analyze && flutter test && mf check
```

Python 3.12 with Pillow 10.4.0 and numpy 1.26.4 locally, within the ranges in
`ml/requirements.txt`. Flutter 3.44.1 and Dart 3.12.1.

## Risks and Assumptions

- **Assumption:** Pillow's `BILINEAR` resample is the same across the pinned
  range, `pillow>=10.0.0,<11.0.0`. The Python test regenerates the golden with
  the installed Pillow on every run, so a version that changed it would fail
  rather than drift.
- **Risk: the JPEG decoders differ.** Dart's `image` package and Pillow's
  libjpeg decode the same file to pixels that can differ by a small amount. That
  is the next skew in line after this spec closes the resample. It is
  unmeasured, and it can be measured over the archive's JPEGs without a new
  capture.
- **Risk: the `hypot` boundary.** A region whose limit sits within about one ulp
  of a patch centre's distance can carry one patch more or fewer in Dart than in
  Python. The chance is about `1e-13` px over a continuous diameter, and the
  golden keeps its cases away from it.
- **Risk: cost.** Two passes over a full-resolution photograph on a phone's CPU
  have not been measured. A7 measures it, and nothing here decides it.
- **What would invalidate this spec:** the sheet reader finding that
  rectification must produce the canonical scale directly. A perspective warp is
  itself a resample, so it would then have to be reconciled with this one. This
  spec assumes, as the dish photographs satisfy, that the frame it receives has
  one uniform scale.
