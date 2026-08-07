# TensorFlow Lite remains the on-device inference runtime: no second runtime is introduced without a measured problem it solves

VisioSoil keeps TensorFlow Lite as the only on-device inference runtime for the
soil texture classifier. The model is trained in Keras (`ml/src/model.py`),
converted by `tf.lite.TFLiteConverter` (`ml/src/export.py:52`), bundled as an
app asset, and executed through `tflite_flutter` (`pubspec.yaml:49`) inside a
spawned isolate (`lib/core/services/inference_service.dart:157-186`). Core ML,
ONNX Runtime Mobile, and ExecuTorch are not adopted.

## Status

Accepted. Recorded during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §12.3 and §15). No model artifact
exists yet, so this decision governs the pipeline being built rather than one in
production.

### Decided

- **One runtime, chosen by the training stack** — the pipeline is TensorFlow/
  Keras end to end. TFLite is the conversion target that requires no
  intermediate representation and no second toolchain.
- **One runtime, covering both platforms** — `tflite_flutter` runs on Android
  and iOS from a single Dart call site, so the app needs no per-platform
  inference branch. The project has an iOS build job (SPEC 0019) and would
  otherwise need to maintain two conversion paths and two parity checks.
- **The cost of a second runtime is paid in perpetuity** — every additional
  runtime adds a conversion step, a parity check, a set of version pins, and a
  class of platform-specific conversion failures. That cost is justified by a
  measured deficiency, and none has been measured because nothing has been
  measured.

## Considered Options

- **Core ML (iOS) alongside TFLite (Android)** — rejected: buys access to the
  Neural Engine at the price of two conversion pipelines, two quantization
  ladders, and two post-conversion parity gates, for a model whose latency
  budget is not yet known to be a problem. Reconsider only if Phase 5 latency
  measurement shows iOS CPU inference misses the budget.
- **ONNX Runtime Mobile** — rejected: its advantage is framework neutrality,
  which is worth paying for when the training stack is heterogeneous or likely
  to change. Here it is a single Keras pipeline, so neutrality buys nothing and
  costs a Keras→ONNX conversion whose operator coverage is one more thing that
  can silently break.
- **ExecuTorch** — rejected: PyTorch's on-device runtime. Adopting it implies
  porting the whole training pipeline to PyTorch, which is a far larger decision
  than the runtime choice it would be nominally serving.
- **A cloud inference endpoint** — rejected outright: the product requirement is
  offline classification in the field, and sending soil photographs to a server
  would also reverse the privacy posture established by ADR 0005 (EXIF stripped
  at the storage boundary) and ADR 0007 (location shared only on explicit
  opt-in).
- **TFLite only (chosen)**.

## Consequences

- Quantization is explored within the TFLite ladder — none, float16, dynamic
  range, full integer, and quantization-aware training if needed — rather than
  by switching runtime. `ml/config.yaml` already exposes `export.quantization`
  with `none`, `dynamic_range`, and `float16`; full integer quantization needs a
  representative dataset and is not yet expressible in the config.
- The post-conversion parity gate is a TFLite concern and stays in `export.py`.
  It must be strengthened: `_verify_tflite` currently compares Keras and TFLite
  on `np.random.rand` (`export.py:92`) against a hardcoded 0.01 threshold
  (`export.py:112`). Random noise is not soil, and the check must run on the
  real test set, measuring accuracy and calibration rather than a max absolute
  difference. Tracked by #29.
- Backbone choice is constrained to architectures that convert cleanly to
  TFLite. MobileNetV2, MobileNetV3, and EfficientNet-Lite0 all qualify;
  EfficientNet-Lite exists specifically because the non-Lite variants use
  operators that convert poorly.
- The decision is revisitable per platform without being revisitable per model:
  if iOS latency proves unacceptable, adding Core ML for iOS only is a bounded
  change, because the model, the labels, and the `spec.json` contract are
  runtime-independent.
