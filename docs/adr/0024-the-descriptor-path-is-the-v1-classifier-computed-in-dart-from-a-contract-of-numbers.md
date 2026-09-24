# ADR 0024: The descriptor path is the v1 classifier, computed in Dart from a contract of numbers

## Status

Accepted 2026-09-22, promoted from
[SPEC 0073](../specs/0073-adopt-the-descriptor-path-and-compute-it-in-dart.md) at the
Spec Gate. Amends [ADR 0008](0008-tflite-remains-the-mobile-inference-runtime.md).

## Decision

Three decisions, taken together because none of them means anything without the
other two.

**1. The descriptor path ships as the v1 classifier.** It is the arm
[SPEC 0054](../specs/0054-the-two-e0-arms-that-do-not-exist-yet.md) built. Each
scale-normalised greyscale patch of
[ADR 0018](0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)
is described by 26 classical features in four groups: 4 first-order moments, 8
log-spaced spectral bands, 10 rotation-invariant uniform local-binary-pattern
bins and 4 co-occurrence statistics. The features are standardised and passed to
a multinomial logistic regression, and a photograph's patch distributions are
averaged into one. That is what
[SPEC 0044](../specs/0044-four-arm-e0-feasibility-gate.md)'s pre-registered rule
returns: the frozen encoder ships only if all four conditions below hold, three
of them do not, and so the descriptor path ships. The numbers are
[`docs/ml/e0-verdict.md`](../ml/e0-verdict.md)'s.

**2. It runs as Dart arithmetic, and the contract carries numbers rather than a
model.** The descriptors are reimplemented in Dart. The fitted standardiser — a
mean and a scale for each of the 26 features — and the logistic regression's
coefficients and intercepts are written into `spec.json`, together with every
fixed point a descriptor depends on. No interpreter runs on this path. The
runtime was chosen by the Developer on 2026-09-22.

**3. A cross-language golden is the parity gate.** Committed patch fixtures carry
the features and the class distribution the Python reference computes, and the
Dart implementation must reproduce them within a tolerance its own spec fixes.
This replaces, for this path, the TFLite post-conversion parity check that ADR
0008 and #29 describe.

## The four adoption conditions

Copied from the verdict with its outcomes, so that this adoption can be audited
without the verdict open beside it. Each is recorded separately because each
fails for a different reason.

| # | Condition | Outcome | Evidence |
|---|---|---|---|
| 1 | **Executed** — the encoder arm ran over all 5 repeats and 5 folds on the shared fold manifest | **yes** | 25 fold directories, 125 trainings, `not_executed` empty |
| 2 | **Won the secondary contrast** — significant after Holm, favouring the encoder, at or above its minimum detectable effect | **no** | +0.0649 group accuracy, p = 0.3018, against a minimum detectable effect of 0.1336 |
| 3 | **Fast enough** — passes the latency gate on the reference device | **not run** | #215 has not run, and an unmeasured condition is not a satisfied one |
| 4 | **Amendments accepted** — SPEC 0037's input size, ADR 0018's rationale, ADR 0012's artifact size | **not sought** | Not put to the Developer: condition 2 already settled the rule |

The arm itself cleared its control on both clauses: group accuracy 0.6883
against the shuffled control's 0.2727, **+0.4156**, Holm p = 6.61e-06, above a
minimum detectable effect of 0.2629. The ablation attributes the signal to one
group: removing the local binary patterns costs 15.6 points (0.6883 to 0.5325),
significant and above that contrast's minimum detectable effect. The groups are
texture statistics, not brightness, which is the failure mode SPEC 0044 named in
advance and which did not occur.

## Why the runtime is Dart

The model is small enough to write out in full. The standardiser is 26 means and
26 scales, and the regression is a 4 by 26 coefficient matrix plus 4 intercepts:
160 numbers, and one matrix product per patch. What costs anything is the
features — a histogram, four co-occurrence matrices of 16 levels and one 2-D FFT
over a 160 by 160 patch, up to 25 patches per photograph.

TFLite would put an interpreter, a model asset and an isolate around a dot
product. And it would not remove the Dart work either way: the scale has to be
read from the A4 sheet
([ADR 0017](0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)),
the photograph resampled to the canonical scale and the patch grid cut before
anything could be handed to an interpreter. That half of A6 is Dart whatever
runs afterwards.

The second implementation is a cost [ADR 0008](0008-tflite-remains-the-mobile-inference-runtime.md)
names. It warns that *every additional runtime adds … a parity check … paid in
perpetuity*. Here that cost is paid, not waived, and the golden of decision 3 is
where it is paid. [SPEC 0030](../specs/0030-soil-image-acceptance-criteria.md)
set the precedent: one set of image-quality criteria, in both languages, under
one golden.

## Considered Options

- **Express the descriptors as a TensorFlow graph and export it to TFLite.**
  Rejected on 2026-09-22. It keeps ADR 0008 unamended, but only by re-expressing
  the local binary patterns, the co-occurrence matrices and a 2-D FFT as graph
  operations and then proving them against numpy — the same parity gate over a
  harder implementation, for a model of 160 numbers. **It is the option the
  runtime reopens onto** if the golden proves unattainable, which is why it is
  recorded here rather than just discarded.
- **Ship the frozen encoder.** It scores 6.5 points higher, runs natively in
  TFLite and leaves ADR 0008 untouched. Rejected because the pre-registered rule
  refuses it on condition 2. Choosing it anyway would read a difference smaller
  than the measurement's resolution as a result, after the numbers were seen,
  which is the thing pre-registration exists to prevent.
- **Keep the incumbent CNN.** Rejected: it failed both clauses of its control
  contrast — +0.1688, Holm p = 0.0596, below its minimum detectable effect of
  0.2434.
- **Run the scikit-learn pipeline through ONNX Runtime Mobile.** Rejected for
  ADR 0008's own reason: a second runtime with its own conversion and version
  pins, and the descriptors would still be computed in Dart before it.
- **Ship the local binary patterns alone.** Rejected: a 10-feature arm is an arm
  nobody ran, and the verdict says in words that individually removable is not
  jointly removable.
- **Dart arithmetic over a contract of numbers (chosen).**

## Consequences

- **ADR 0008 is amended, not superseded.** TFLite remains the runtime for any
  neural model the project ships, and its rejections of Core ML, ONNX Runtime,
  ExecuTorch and a cloud endpoint all stand. The v1 classifier is simply not a
  neural model.
- **The contract becomes numbers.**
  [SPEC 0035](../specs/0035-spec-json-runtime-contract.md)'s network fields —
  input size, normalisation, the model asset — do not describe this path. The
  spec that implements the contract re-specifies it. It carries:
  - the class list, the canonical millimetres per pixel and the patch geometry;
  - the descriptor fixed points: 16 co-occurrence levels over four offsets,
    eight neighbours at radius 1 mapped rotation-invariant uniform, and eight
    log-spaced bands starting at two cycles per patch;
  - the feature order, the standardiser and the regression;
  - the aggregation rule, the dispersion threshold and, after calibration, the
    band constants.

  SPEC 0035's failure taxonomy
  ([ADR 0015](0015-classification-reports-a-named-failure-cause.md)) and its
  rule that labels come from the contract both stand.
- **A6's Dart half is the critical path to a release.** It needs the A4-sheet
  scale reader, the resample to canonical with a low-passed downsample (#180's
  Dart half), the patch grid, and the descriptors under the golden. This path
  depends on scale more than the CNN did. A spectral band is a physical
  wavelength only at the canonical scale, so ADR 0017's refusal when no reference
  is found is a precondition. Nothing in the app reads a scale today.
- **A7 (#215) stops being an adoption condition.** The encoder lost condition 2
  whatever the latency. It remains an engineering measurement: what the Dart
  descriptors cost per photograph on a device, dominated by the FFT.
- **B3's export becomes a fit written as numbers.** The adopted pipeline is refit
  over the whole splittable pool and population `B`, with `C` selected by the
  same nested procedure. The standardiser and the regression are written into
  `spec.json`, and the golden replaces the TFLite parity gate of #29.
- **C1's network sweeps and C3's quantization ladder have nothing to act on in
  v1.** No network is trained. E13's region-of-interest comparison was already
  superseded by ADR 0018's patches, and C1's site-held-out reporting survives. A
  model of 160 numbers has nothing to quantize.
- **C2 is unchanged.** A logistic regression's probabilities still need
  temperature scaling and calibrated bands, and with no quantization step #187's
  ordering concern no longer arises.
- **Nothing is removed yet.** `tflite_flutter`, the interpreter path in
  `inference_service.dart`, and the CNN and encoder arms stay until the wiring
  spec lands. This record changes what ships, not what the repository contains.
- **What the adoption does not license** is what the verdict does not license: a
  field accuracy, any per-class claim, or anything about photographs from another
  capture protocol. The archive is dry, sieved bench material from one operator.

## What would reopen it

- **The golden proving unattainable**, or the Dart descriptors proving too slow
  on the reference device. Either reopens the runtime, onto the TFLite-graph
  option above, and leaves the adoption standing.
- **A later gate that resolves the secondary contrast.** Only a pre-registered
  rerun on a later dataset version, reading `encoder_probe` against `descriptors`
  under SPEC 0044's rule, reopens which method ships. The point estimate here
  does not.
