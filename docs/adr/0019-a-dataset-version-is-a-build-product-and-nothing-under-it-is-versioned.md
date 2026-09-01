# A dataset version is a build product: nothing under it is versioned, the manifest included

Nothing inside `ml/data/datasets/<version>/` enters git. The rule that excepted
`manifest.csv` and `admission-rejected.csv` from the ignore-all pattern is
removed, the manifest already committed is untracked, and a dataset version is
reproduced from the delivered archive by `python scripts/ingest_archive.py`
rather than restored from history.

This **reverses the rule recorded in
[SPEC 0033](../specs/0033-dataset-protocol-manifest-and-splits.md)** and stated
in both `.gitignore` files, which made the manifest the versioned record of a
version. SPEC 0033 keeps every other decision it took; only the storage rule
moves.

## Status

Accepted 2026-09-01, at the Developer's direction, while
[SPEC 0040](../specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md)
was in review.

## Context

SPEC 0033 designed the dataset protocol before any image existed. A collector
would author a manifest by hand, admission would rewrite it, and the file would
be the only durable trace of what a version contained — so committing it was the
difference between a version that could be described later and one that could
not. Every image was ignored; the two bookkeeping files were excepted.

Two things changed on 2026-09-01.

**A version stopped being hand-authored.** SPEC 0040's ingestion reads the
archive and writes the whole version, with sorted file order and nothing
sampled, so two runs over one archive produce byte-identical manifests. Nothing
about a version is now a human judgement that would be lost if the file were
deleted: it is a function of the archive and of the code that reads it, both of
which are recoverable — the code from git, the archive from the laboratory.

**A version stopped being small.** `v1` is 1.3 GB, and although only 28 KB of it
was ever committed, the directory now lives inside a synchronised folder on the
Developer's machine. The tracked file was not the cost; the exception was the
part that needed a reason it no longer had.

## Considered Options

- **Keep committing `manifest.csv` (the status quo).** It is 28 KB, and it is
  what let CI assert the archive's inventory — 221 photographs of 105 sample
  groups, the per-class table, the split of derived against declared identities
  — on a runner that holds no images. Rejected by the Developer. The technical
  case for it is real and is the price recorded below.
- **Commit a reduced inventory instead — counts and digests, not rows.** It
  would keep the CI assertion at a fraction of the size. Rejected as the worst
  of both: a second artifact describing the version, derived from the manifest
  by nothing that checks it, which is a summary that can disagree with what it
  summarises and give no sign.
- **Keep the manifest and move the version outside the synchronised folder.** It
  addresses the size without touching the storage rule, and it is still worth
  doing for the 1.3 GB. It does not answer whether a reproducible artifact
  belongs in history, which is the question this record settles.
- **Ignore everything (chosen).** A version is derived, deterministic, and
  rebuildable by one command. Nothing derived is a record.

## Consequences

- **CI can no longer assert the archive's inventory.** Three tests in
  `ml/tests/test_ingest.py` are marked to skip when the version's manifest is
  absent, and it is now absent everywhere except a machine that has run the
  ingestion. The counts in SPEC 0040 and in ADR 0016's amendment become claims a
  reader trusts rather than assertions a runner re-checks, and a change in the
  archive would be silent until someone re-ingests. **This is the price and it
  is not small**; it is recorded here rather than discovered when a number drifts.
- **"Reproducible" is conditional on holding the archive, which git does not
  hold.** A clone of this repository cannot rebuild `v1`. The chain of custody
  for the dataset now runs through the laboratory's copy and the Developer's
  disk, and nothing in version control would reveal its loss. That is a real
  weakening of the guarantee SPEC 0033 wanted, and the honest statement of this
  decision is that the reproducibility argument holds for the *transformation*
  and not for the *input*.
- The digest a split records still proves it belongs to the manifest it was
  generated from, because that mechanism never depended on the file being
  committed. What is gone is the ability to fetch that manifest from history and
  check the claim on another machine.
- `.gitattributes` no longer pins any dataset-version file to LF; ingestion
  still writes LF explicitly, and there is no longer a checkout that could
  rewrite it.
- A test asserts the reversal against the index, not only against the ignore
  rules: an ignore pattern says nothing about a file already in history, and
  `git ls-files` under the datasets directory must stay empty.
- If the inventory assertions are wanted back, the cheapest route is the one
  rejected above, and this record is what would have to be revisited.
