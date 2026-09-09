# SPEC: fix(ml): store image paths in the fold manifest relative to the dataset root

## Problem

`create_folds` writes `str(manifest.root / row.image)` into `splits.json` and
nothing re-roots it on load, so the fold manifest is valid on exactly one
machine and one checkout location — and it also publishes the developer's
directory layout to a public repository.

## Design Decisions

**The paths are relativised at serialisation and re-rooted at load, and nothing
between the two changes.** `create_folds` receives the same absolute paths it
receives today and groups over them exactly as today; only the moment of writing
the file is different. `load_folds` rebuilds each absolute path with the same
`root / relative` construction `manifest.class_images` uses, so `fold_split`,
`verify_images`, `photograph_scale` and every featuriser receive precisely what
they receive now.

That ordering is the whole safety argument. The group key is
`f"{class}::{sample_id}"` and `sample_ids` is a mapping **keyed by absolute
path** (`dataset.py:830`, `manifest.py:619`), so relativising before grouping
would change which key each photograph is looked up under. Relativising after
the partition is drawn cannot move a fold, because by then there is nothing left
to decide.

Both functions take the root as a **required keyword argument**. An optional one
would give `load_folds` two return shapes — absolute paths when a root was
passed, relative ones when it was not — and the relative shape would silently
resolve against the process's working directory, which is `ml/` for every entry
point in this repository and would therefore appear to work from the one place
anybody runs it.

### Three places hold a path, not one

The manifest carries an absolute path in `groups[*].images`, in the **keys** of
`refused`, and inside the refusal **messages**, which are built as
`f"{path}: {reason}"` by `_canonical_region` and reach the file through
`drop_refused_photographs` (`dataset.py:1196`). A change that relativised only
the first two would still write the developer's home directory eleven times into
`v1`'s manifest, which is half of what this issue is about. The message is
relativised by substituting the one path string that is known to be in it — the
entry's own key — rather than by parsing the message, so the transformation
needs no assumption about the message's shape.

Paths are written POSIX-separated. A manifest written on Windows and read on
Linux is the exact move this specification exists for, and `\` is a legal
filename character on Linux, so a backslash-separated relative path does not
resolve there — it becomes one long filename. `PurePath.as_posix()` on the way
out and `Path(root) / stored` on the way in round-trips on both platforms.

### The schema version is bumped and the old one is refused, not migrated

`FOLD_SCHEMA_VERSION` goes from 2 to 3. A version-2 file is refused by name with
the regeneration command, exactly as a version-1 file already is.

Migrating it was considered and is impossible rather than merely undesirable:
the file does not record the root its paths were written under, so a migration
would have to guess where the dataset root ends inside
`C:\Users\...\ml\data\datasets\v1\images\Arenosa\100262,1 (1).JPEG`. A wrong
guess yields a path that resolves to nothing on the reading machine, which is
the failure this change exists to remove, arriving through the code that was
supposed to fix it.

### The manifest becomes tracked, because that is what the change buys

`ml/data/splits/splits.json` was tracked on 2026-09-05 and untracked the same
day: the partition genuinely is not reproducible — `StratifiedGroupKFold` is a
greedy heuristic that assigns differently across scikit-learn releases, which is
why the file records `library_versions` — so a record of it should travel, and
the file could not survive the move it was tracked for. Portable paths are the
mechanism that was missing, so the reversal lands here rather than in a follow-up
that would leave this change with no observable benefit.

`test_dataset_gitignore.py` already holds the withdrawn assertion and its reason
in `WITHDRAWN_PATHS`, written to be inverted back. Inverting it is what keeps the
reversal asserted rather than merely performed.

A tracked manifest can disagree with the dataset version a reader holds. That is
not a new risk and it is already closed: `load_folds_for_config` refuses a
manifest whose `manifest_digest` does not match the dataset's own, so a stale
tracked file fails loudly instead of scoring the wrong photographs.

## Alternatives Considered

- **Re-root at each consumer** — `_entries_of`, `_images_by_class`,
  `photograph_patch_counts` — instead of in `load_folds`. Rejected: it spreads
  the root through every reader, and a reader that forgot it would receive a
  relative path that resolves against the working directory, which is `ml/` for
  every entry point here. It would work in development and fail nowhere that
  anybody looks.
- **Store paths relative to the repository root.** Rejected: `datasets_dir` is
  configurable, and `validate_dataset.py --root` deliberately partitions a
  version that lives outside it, so a repository-relative path is not resolvable
  from the configuration a reader holds.
- **Record the writing machine's dataset root in the manifest and re-root by
  string substitution.** Rejected twice over: it re-publishes the directory
  layout the leak note objects to, and it makes the file's correctness depend on
  a value no reader can verify.
- **Keep absolute paths and ship the re-rooting tool the SPEC 0057 run used.**
  Rejected: that tool is untracked operational scaffolding, it has to be re-run
  correctly by hand every time the partition moves, and the run that used it
  needed a second independent redraw to prove it had not corrupted anything.
  Making the file portable removes the step rather than automating it.
- **Relativise inside `manifest.class_images`, so no absolute path is ever
  built.** Rejected: `sample_ids_by_image`, `photograph_scale` and
  `drop_refused_photographs` are all keyed by the absolute path, so this would
  be a rewrite of the manifest's whole path contract to fix its serialisation,
  and every one of those keys would have to move in step or fail silently.

## Scope

- Includes:
  - `ml/src/dataset.py`: `FOLD_SCHEMA_VERSION` 2 → 3; `create_folds` and
    `load_folds` each gain a required keyword-only `dataset_root`;
    `create_folds` relativises `groups[*].images`, the keys of `refused` and the
    path inside each refusal message; `load_folds` re-roots the first two;
    `create_folds_for_config` passes `manifest.root` and `load_folds_for_config`
    passes the configured `dataset_root(datasets_dir, dataset_version)`; the
    version-2 refusal message.
  - `ml/src/population_probe.py`: `probe_partition` passes `manifest.root`.
  - `ml/tests/`: the new criteria below, and the existing `create_folds` /
    `load_folds` call sites updated to the new signatures.
  - `.gitignore`: `ml/data/splits/splits.json` stops being ignored.
  - `ml/tests/test_dataset_gitignore.py`: `WITHDRAWN_PATHS` and its two
    assertions inverted — the manifest must now be tracked and not ignored.
  - `ml/data/splits/splits.json`: regenerated at schema 3 and committed.
- Does NOT include:
  - Any change to which group lands in which fold. This change is
    serialisation, and the criteria assert the partition does not move.
  - Any change to `manifest.csv`, to `manifest.class_images`, or to the
    absolute-path keying of `sample_ids_by_image`, `photograph_scale` and
    `drop_refused_photographs`.
  - Re-rooting the path inside a stored refusal **message** on load. The message
    is a human-readable record of why a photograph left; the key is what code
    reads, and re-rooting prose would claim a precision it does not have.
  - The `texture_class` spanning-group guard (#229). It is a separate refusal in
    `create_folds_for_config` and is its own issue.
  - Tracking anything else under `ml/data/`. ADR 0019 keeps a dataset version
    unversioned and this does not touch it: `ml/data/splits/` is not inside a
    version directory.
  - Running an arm, or regenerating any result under `ml/models/`.

## Acceptance Criteria

- `the_fold_manifest_holds_no_absolute_path` — every path a written manifest
  carries, in `groups[*].images`, in the keys of `refused` and inside each
  refusal message, fails `os.path.isabs` and contains no drive letter.
- `stored_paths_are_posix_separated` — no stored path contains a backslash, so a
  manifest written on Windows names files that exist on Linux.
- `load_folds_re_roots_against_the_reading_root` — a manifest written under one
  root and read under a second yields `groups[*].images` and `refused` keys that
  are absolute under the second and resolve to files there.
- `re_rooted_paths_match_the_manifest_construction` — the absolute path
  `load_folds` returns for a row is string-identical to the one
  `manifest.class_images` builds for that same row, so the scale lookup keyed by
  path still hits.
- `the_partition_is_invariant_to_the_dataset_root` — the same dataset written
  under two different roots produces byte-identical `folds`, `groups`
  (paths aside) and `counts` blocks, so relativising cannot move a group.
- `a_path_outside_the_dataset_root_is_refused_by_name` — `create_folds` given an
  image that is not under `dataset_root` raises, naming the path and the root,
  rather than writing a `..`-prefixed path or crashing in `relative_to`.
- `a_version_two_fold_manifest_is_refused_by_name` — a manifest recording
  `schema_version: 2` is refused naming that version and the regeneration
  command, and is not re-rooted.
- `refused_photographs_survive_the_round_trip` — a refused photograph's entry is
  written relative and read back absolute, and its message still names the
  photograph.
- `the_fold_manifest_is_tracked` — `git check-ignore` no longer ignores
  `ml/data/splits/splits.json`, and `git ls-files` lists it.

## Reproducibility

```sh
cd ml
.venv/Scripts/python.exe -m pytest tests/ -q          # Windows
.venv/bin/python -m pytest tests/ -q                  # Linux

# Regenerating the committed manifest, which needs the ingested archive:
.venv/Scripts/python.exe scripts/validate_dataset.py --version v1 --splits-dir data/splits
```

No randomness is introduced. The partition is drawn from `data.seed` (42) under
scikit-learn 1.5.2 and numpy 1.26.4, which the manifest records and
`load_folds` warns on; the criteria above compare two writes of the same data
rather than pinning an assignment, so they do not break when that pin moves.
Python 3.12 with `ml/requirements.txt`.

## Risks and Assumptions

- Assumption: every image a fold manifest references lives under the dataset
  root. It is true of `manifest.class_images`, which builds each path as
  `manifest.root / row.image`, and it is the only shape `create_folds` is given
  in this repository. What would invalidate it: a manifest whose `image` column
  held an absolute path or an upward-traversing one — which
  `a_path_outside_the_dataset_root_is_refused_by_name` turns into a named
  refusal rather than a silent `..` path.
- Assumption: `str(Path(root) / stored)` reproduces `str(manifest.root /
  row.image)` exactly, so the path-keyed lookups in `photograph_scale` and
  `sample_ids_by_image` keep hitting. Both go through `Path.__truediv__` and
  `str`, and `re_rooted_paths_match_the_manifest_construction` asserts it rather
  than assuming it.
- Risk, accepted: the committed `splits.json` is a build product in version
  control. It is committed because the partition is not reproducible across
  scikit-learn releases and the file records which release drew it; a reader
  whose dataset disagrees is refused by `load_folds_for_config`'s digest check,
  and a reader whose scikit-learn disagrees is warned by
  `_warn_on_a_library_mismatch`.
- Risk, accepted: this invalidates every existing `splits.json` on every
  machine, including the one the SPEC 0057 arms were drawn under. Nothing
  measured moves — those arms' results are already written and are not re-run —
  but a fold recomputed after this change must be recomputed from the
  regenerated manifest, and `crossval.fold_reuse_state` compares the recorded
  `manifest_digest` rather than the fold manifest, so an arm resumed across the
  change is not silently mixed.
- What would invalidate this spec: a decision that the fold manifest should not
  be tracked after all. The path change stands on its own — the leak and the
  portability are reasons enough — and the tracking half would simply be
  dropped.
