# SPEC: refactor(ml): remove the tflite export that nothing ships

## Problem

`ml/src/export.py` still converts a Keras checkpoint to TFLite for an app that,
since SPEC 0083, has no interpreter to run it on, and the release it once stood
for is now `ml/src/release.py` (SPEC 0082), so the export and the documents
built around it describe a path that nothing ships.

## Scope

- Includes:
  - `ml/src/export.py` and `ml/tests/test_tflite_inference.py`, deleted.
  - `ml/src/model_paths.py` loses `find_model_checkpoint` and
    `LEGACY_CHECKPOINT_FILENAME`, because the export was their only reader.
    `CHECKPOINT_FILENAME` stays for `train.py`. SPEC 0047's three resolver
    tests leave with the resolver, and its no-TensorFlow test stays. Its
    one-source test is renamed after the criterion below, since no reader is
    left.
  - `ml/src/config.py` loses `_VALID_QUANTIZATIONS` and the check that reads
    `export.quantization`, and `ml/config.yaml` loses that key. The test
    fixtures that carry it drop it. `export.output_dir` stays, because every
    module reads it as the models root.
  - The `ml/Makefile` `export` target and its comment.
  - `ml/scripts/train_and_export.sh`, deleted. Without its export step it
    repeats `make train evaluate`, and its name would promise a step it no
    longer has.
  - Comments that cite the export, in `config.py`, `arms/encoder.py` and
    `tests/test_config.py`, reworded to say what still holds.
  - Documents:
    - `ml/README.md`: the export, full-pipeline, deploy, tests, Flutter
      integration and artifact sections. The deploy section becomes the
      release path, `src.release` and then `deploy_to_app.sh`.
    - The root README's `ml/` line.
    - `docs/agents/project.md`'s debt entry, with `CLAUDE.md` regenerated.
    - The implementation map: B3's closing sentence and the wiring's second
      half. The map records that the dispersion metric moves to C2.
  - After merge, #180 is closed with the reason given under Does NOT include.
- Does NOT include:
  - The CNN arm, the shuffled control, `model.py`, `train.py` and
    `preprocess.py`. They are E0's incumbent and control arms, and the control
    *is* the CNN trained on permuted labels (`train.py`, `build_model`).
    Deleting them removes the gate's control, and the recorded verdict could no
    longer be reproduced from the code. That takes its own ADR.
  - `preprocess.py`'s resize without antialiasing, #180's Python half. It is
    the control's resampler, so changing it changes numbers E0 recorded. The
    path the app ships already filters its downsample (SPEC 0081, ADR 0025).
  - TensorFlow in `ml/requirements.txt`. The CNN arms and the encoder arm need
    it.
  - The dispersion metric. It has no Python reference, no consumer and no
    calibrated threshold. C2 is where a threshold is set.
  - ADR 0008 and the dated documents that cite `export.py` by line, such as
    `docs/architecture/soil-classification.md`. They record what was there.
    ADR 0008's 2026-09-22 amendment already narrows it to neural models, and a
    future neural model rebuilds its conversion under that record.
  - The rest of `ml/README.md`, including its Architecture section, which
    describes the CNN arm that stays.
  - Renaming `export.output_dir`.

## Acceptance Criteria

- `the_training_package_has_no_tflite_export`: `ml/src/export.py` does not
  exist. No module under `ml/src/` or `ml/scripts/` uses `tf.lite` or names
  `src.export`, and `ml/Makefile` has no `export` target.
- `the_shipped_config_declares_no_quantization`: `load_config()` over
  `ml/config.yaml` returns an `export` block whose only key is `output_dir`.
- `the_checkpoint_filename_is_declared_once`: `train.py` saves through
  `CHECKPOINT_FILENAME` and repeats neither checkpoint filename as a literal,
  and `src.model_paths` defines no `find_model_checkpoint`.
