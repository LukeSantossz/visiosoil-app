# SPEC: perf(ml): decode each image once per fit instead of once per epoch

## Problem

`build_dataset` re-reads and re-decodes every photograph from disk on every epoch, which measures at **5.47 s per epoch** for one fold's 179 training images and does not fall on repeat — about 9 hours of redundant decoding per experimental arm at k = 5, R = 5.

## Design Decision

A `cache()` is inserted **after the decode map and before the augmentation map**, and `shuffle` moves from before the decode map to after the cache:

```
from_tensor_slices -> map(_parse_image) -> cache() -> shuffle -> map(augment) -> batch -> prefetch
```

Each of the three positions is forced, not chosen:

- **After decode**, because decoding is the deterministic, expensive, repeated work. It is a pure function of the path, so caching it changes no value.
- **Before augmentation**, because augmentation must draw differently every epoch. Caching after it would freeze one set of augmented images for the whole fit and silently turn the augmentation off while leaving it configured.
- **Shuffle after the cache**, because `cache()` records the order of what passes through it. With shuffle upstream, the first epoch's shuffled order would be the order every later epoch replayed — the shuffle would happen once and then never again, which is worse than not shuffling, since it would look correct in the configuration and in the first epoch's logs.

**This changes results, and that is why it happens now.** Moving `shuffle` downstream of the decode map changes which photographs land in which batch for a given seed. Reproducibility is untouched — the run is still seeded, `enable_op_determinism` is still on, and two runs of one config still agree — but a number produced before this change is not comparable to one produced after. **No trained result exists in this repository**, so today the cost is zero; after E0 it would invalidate every arm. The Developer took this decision on 2026-09-02 on exactly that reasoning.

The cache is in memory, which is bounded here by a closed dataset: the largest training side is 179 photographs at 224 x 224 x 3 float32, about **108 MB**. ADR 0016 closed the archive at 221 photographs, so this cannot grow without a decision that would revisit it.

## Alternatives Considered

- **Leave it and accept the cost.** Rejected by the Developer once measured. It is about 9 hours per arm and two of E0's four arms carry CNN cost, so roughly 18 hours of the gate's wall clock is spent decoding images that never change.
- **Cache to a file instead of memory.** Rejected. `cache(filename)` survives the process and would help across fits, but it writes a multi-gigabyte artifact per fold into a tree that is already git-ignored and hard to reason about, and the 108 MB in-memory footprint is small enough that the added failure mode — a stale cache file silently feeding an old dataset version into a new run — costs more than it saves.
- **Cache after augmentation.** Rejected, and it is the tempting mistake: it caches strictly more work. It would freeze the augmentation to a single draw for the whole fit, so the model would see 179 fixed images rather than a fresh draw each epoch, and nothing in the config, the logs or the metrics would say so.
- **Keep `shuffle` upstream and cache anyway.** Rejected for the same class of reason: the cache would replay the first epoch's order forever. Shuffling would appear configured and be inert after epoch one.
- **Reduce the image size or the epoch budget instead.** Rejected. Both change the training recipe SPEC 0032 fixed and would need that record amended; this changes no recipe parameter, only when a decode happens.
- **Decode once into a `.npy` array outside `tf.data`.** Rejected. It replaces a framework mechanism with a hand-rolled one, loses `AUTOTUNE` parallelism, and puts the dataset's memory layout under this repository's maintenance rather than TensorFlow's.

## Scope

- Includes:
  - `ml/src/dataset.py` — `build_dataset`: insert `cache()`, move `shuffle` after it.
  - `ml/tests/` — one test per criterion below.
- Does NOT include:
  - Any training recipe parameter: image size, batch size, epochs, unfreeze point, learning rates and the augmentation set are all untouched.
  - `enable_op_determinism` or any seeding behaviour.
  - A file-backed cache.
  - The training environment or how an arm is run, which is its own change.
  - Regenerating the fold manifest. It is drawn by `create_folds`, which this does not touch.

## Acceptance Criteria

- decode_happens_once_per_fit: a dataset built from entries whose decode is instrumented decodes each entry exactly once across two full epochs.
- augmentation_still_draws_each_epoch: two epochs of an augmented dataset over the same entries yield different pixels, so the cache did not freeze the augmentation.
- shuffle_order_differs_between_epochs: two epochs of a shuffled dataset yield different orders, so the cache did not freeze the shuffle.
- unshuffled_order_matches_the_entries: without shuffling, the dataset yields entries in the order given, so the cache did not reorder anything.
- labels_stay_with_their_images: after caching and shuffling, every image is still paired with the label its entry declared.
- the_pipeline_yields_the_same_multiset: over one epoch, the set of images produced is the same before and after this change, so the reordering moved batches and lost nothing.

## Reproducibility

```sh
cd ml
.venv/Scripts/python -m pytest tests/test_dataset.py -q
```

The measurement that motivated this, over fold 0 of repeat 0 of dataset version `v1`, on the pinned stack (`tensorflow==2.21.0`, Python 3.12.13):

| | per epoch |
|---|---|
| decode + resize | 5.47 s |
| decode + resize + augment | 6.72 s |
| augment alone (derived) | 1.25 s |
| decode + resize, cached, second epoch | 0.00 s |

179 training photographs, 6 batches at `batch_size: 32`. Extrapolated at 50 epochs: **5.6 min of input per fit before, 1.1 min after**. Five fits per fold and 25 folds per arm put the saving near 9 hours per arm; the wall-clock cost of a whole fold is measured separately and is not claimed here.

## Risks and Assumptions

- **Assumption: 108 MB is affordable on every machine that trains.** It is the largest training side at the configured image size. A machine that cannot hold it cannot hold the model's activations either.
- **Assumption: no stored result depends on the current batch composition.** Verified rather than assumed: `ml/models/` is git-ignored, no fold artifact is committed, and no training has ever completed in this repository.
- **Risk: the dataset grows and the cache stops fitting.** ADR 0016 closed the archive, so this needs a decision that would reopen it — and that decision is where the cache should be revisited, which is why the footprint is stated here rather than left to be rediscovered.
- **Risk: a future edit moves `shuffle` back above the cache.** The two criteria `shuffle_order_differs_between_epochs` and `augmentation_still_draws_each_epoch` are what fail if it does; both were written because the failure is silent in the configuration and in the first epoch.
- **What would invalidate this spec:** moving the decode off the training host — a pre-materialised patch tensor written by the A6 pipeline, for instance — which would make this cache redundant rather than wrong.
