# SPEC: docs(ml): adopt the descriptor path and compute it in dart against a contract of numbers

## Problem

The E0 gate's pre-registered rule selected the descriptor path on 2026-09-18, but
no record adopts it, and the records the release path is built from still
describe the method that failed. ADR 0008 makes TFLite the only inference
runtime, SPEC 0035's contract is a network's input size and normalisation, and
the implementation map still lists "run the gate" as the next item and schedules
a backbone sweep and a quantization ladder. So the next spec on the release path
has no decided design to implement.

## Design Decision

**ADR 0024 adopts the descriptor path as the v1 classifier and decides where it
runs.** Three decisions, one record, because none of them means anything without
the other two:

1. **The descriptor path ships.** It is the arm SPEC 0054 built: 26 classical
   descriptors per patch, in four groups — first-order, spectral, local binary
   patterns and co-occurrence — computed over the scale-normalised greyscale
   patches of ADR 0018. They are standardised and fed to a multinomial logistic
   regression, and each photograph's patch distributions are averaged. This is
   not a preference re-read from the numbers. It is what SPEC 0044's rule returns
   when conditions 2, 3 and 4 of the encoder's adoption do not hold, and
   `docs/ml/e0-verdict.md` records each condition by name. The ADR restates them
   with their outcomes, so the adoption can be audited without the verdict open
   beside it.

2. **It runs as Dart arithmetic, and the contract carries numbers rather than a
   model.** The descriptors are reimplemented in Dart. The fitted standardiser
   (a mean and a scale per feature) and the logistic regression (a coefficient
   matrix and an intercept per class) are written into `spec.json`, together
   with every fixed point a descriptor depends on. No interpreter runs on this
   path. Chosen by the Developer on 2026-09-22.

3. **A cross-language golden is the parity gate.** Committed patch fixtures carry
   the features and the class distribution the Python reference computes, and
   the Dart implementation must reproduce them within a tolerance that its own
   spec fixes. This replaces the TFLite post-conversion parity check that ADR
   0008 and #29 describe. The second implementation is a cost ADR 0008 names —
   *every additional runtime adds … a parity check … paid in perpetuity* — and
   this is where that cost is paid, not waived. SPEC 0030 set the precedent,
   putting one set of image-quality criteria in both languages under one golden.

**ADR 0008 is amended in place, not superseded.** Its rejections of Core ML,
ONNX Runtime, ExecuTorch and a cloud endpoint all stand. What changes is its
scope: TFLite remains the runtime for any neural model the project ships, and
the v1 classifier is not a neural model. The amendment follows the precedent of
ADR 0009's dated `### Amended` sections.

**SPEC 0035 gains a revision note, as it did on 2026-08-25.** Its contract
fields for a network — input size, normalisation, the TFLite asset — do not
describe the adopted path. Its failure taxonomy (ADR 0015) and its rule that
labels come from the contract both stand. The schema is re-specified by the spec
that implements it, not here.

**The living records are brought up to the decision:** the README index, the
implementation map and the handoff. In the map:

- the end-state's Inference row;
- §6, which still says the gate is next;
- A4, whose contract becomes numbers;
- A6's Dart half, which computes descriptors instead of batching through an
  interpreter;
- A7, which stops being an adoption condition and becomes an engineering
  measurement;
- B3, whose export becomes a fit written as numbers;
- C1 and C3, whose network sweeps and quantization ladder have nothing to act on
  in v1;
- C2, which is unchanged: a logistic model still needs calibrating.

## Alternatives Considered

- **Express the descriptors as a TensorFlow graph and export it to TFLite.**
  Rejected by the Developer on 2026-09-22. It keeps ADR 0008 unamended, but only
  by re-expressing the local binary patterns, the co-occurrence matrix and a 2-D
  FFT as graph operations, and then proving *that* against numpy — which is the
  same parity gate with a harder implementation under it. It buys nothing for a
  model that is 26 inputs times four outputs. The app would still have to read
  the scale and cut the patches in Dart first.
- **Ship the frozen encoder instead.** It scores 6.5 points above the
  descriptors, runs natively in TFLite, and leaves ADR 0008 as it is. Rejected
  because the pre-registered rule refuses it: condition 2 failed (p = 0.3018,
  +0.0649 against a minimum detectable effect of 0.1336). Choosing it anyway
  would be reading a difference smaller than the measurement's resolution as a
  result, after the numbers were seen — the one thing pre-registration exists to
  prevent.
- **Keep the incumbent CNN.** Rejected: it failed both clauses of its own
  control contrast.
- **Run the scikit-learn model through ONNX Runtime Mobile.** Rejected for ADR
  0008's own reason. It is a second runtime with its own conversion and version
  pins, and it still leaves the descriptors themselves to be computed in Dart.
- **Ship the local binary patterns alone, since the ablation says they carry the
  arm.** Rejected: a 10-feature arm is a fifth arm nobody ran. The verdict says in
  words that individually removable is not jointly removable.
- **Write the ADR and leave the other records for the specs that change the
  code.** Rejected: SPEC 0062 exists because records that go on pointing at a
  decision already taken are how the next reader starts the wrong item. The map
  would keep saying "run the gate".

## Scope

- Includes:
  - `docs/adr/0024-*.md` (new) — the three decisions above, the four adoption
    conditions with their outcomes, the rejected options, the consequences for
    each map item, and what would reopen the runtime decision.
  - `docs/adr/0008-*.md` — an `### Amended 2026-09-22` section that narrows its
    scope and links ADR 0024.
  - `docs/specs/0035-*.md` — a revision note under its title, beside the existing
    2026-08-25 one, that names ADR 0024 and says which of its parts stand.
  - `README.md` — the Engineering Decisions row for ADR 0024, which
    `test/standards/readme_adr_index_test.dart` requires.
  - `docs/architecture/ml-implementation-map.md` and
    `docs/architecture/ml-handoff.md` — the items listed under Design Decision,
    and their `Last updated` headers.
  - `ml/tests/test_adoption_records.py` (new) — the criteria below.
- Does NOT include:
  - Any change to `ml/src/`, `ml/config.yaml` or `lib/`. The descriptors in Dart,
    the contract schema, the release fit, the golden fixture and the wiring are
    each a spec of their own, on this decision.
  - Removing the CNN arm, the encoder arm, `tflite_flutter` or
    `inference_service.dart`'s interpreter path. What ships changes here; what
    the repository contains changes when the wiring spec lands.
  - Running the latency measurement (#215) or the calibration (C2).
  - Editing `docs/ml/e0-verdict.md`, a run verdict, or any approved spec other
    than SPEC 0035's revision note.
  - `docs/agents/project.md`, the source of `CLAUDE.md`. It describes the code as
    it stands, and the code does not change here.

## Acceptance Criteria

Each is a test in `ml/tests/test_adoption_records.py`. None reads the dataset or
imports TensorFlow.

- `adr_0024_adopts_the_descriptor_path`: `docs/adr/` holds one record numbered
  0024, it states that the descriptor path ships, and it links both SPEC 0044
  and `docs/ml/e0-verdict.md`.
- `adr_0024_records_each_adoption_condition`: it names all four conditions,
  each beside its recorded outcome.
- `adr_0024_decides_the_runtime`: it states that the descriptors are computed in
  Dart and that `spec.json` carries the standardiser and the logistic
  coefficients.
- `adr_0024_names_the_rejected_options`: it names the TFLite-graph export, the
  frozen encoder, the incumbent CNN and a second runtime.
- `adr_0008_carries_its_amendment`: ADR 0008 has an `Amended 2026-09-22` section
  that links ADR 0024.
- `spec_0035_points_to_adr_0024`: SPEC 0035's opening revision notes name ADR
  0024.
- `readme_indexes_adr_0024`: the README Engineering Decisions section links it.
- `no_living_record_calls_the_gate_next`: neither the map nor the handoff names
  running the E0 gate as the next item, and both link the verdict.
- `no_living_record_waits_on_the_adoption`: no block of an architecture document
  that names the adoption describes it as pending.

## Reproducibility

```sh
cd ml && .venv/Scripts/python.exe -m pytest tests/test_adoption_records.py -q
flutter test test/standards/
mf check
```

The figures ADR 0024 quotes are read from `docs/ml/e0-verdict.md`, which records
the commands and versions that produced them.

## Risks and Assumptions

- **Assumption:** Dart can reproduce the numpy descriptors within a tolerance
  that does not change a prediction. The FFT and the order of floating-point
  sums differ between the two implementations. If the golden cannot be met, the
  runtime decision reopens, and the TFLite-graph alternative is the one it
  reopens onto, which is why ADR 0024 records it rather than just discarding it.
- **Risk:** the adopted path depends on scale more than the CNN did. A spectral
  band is a physical wavelength only at the canonical millimetres per pixel, so a
  mis-scaled photograph moves features rather than merely blurring them. ADR
  0017's refusal when no scale reference is found is a precondition, not an
  option, and the A4-sheet reader it requires does not exist in the app.
- **Risk:** the E0 figure is an average over per-fold fits, and the released
  model is one fit. The verdict's own limits travel with it: dry sieved bench
  material, one archive, and no per-class claim. Nothing here licenses a field
  accuracy.
- **Assumption:** a linear model over 26 features is small enough that computing
  it costs nothing next to the patches. The cost that could matter is a 160 by
  160 FFT over up to 25 patches per photograph in Dart, which is why A7 stays as
  a measurement rather than being dropped.
- **What would invalidate this spec:** the golden proving unattainable, or the
  Dart descriptors proving too slow on the reference device. Either returns the
  runtime question to ADR 0024 without reopening the adoption.
