# SPEC: docs: reorganize the docs folder

## Problem

`docs/` has grown by accretion, and its top level no longer says what each part is for:

- Two guides for the people who take the photographs, `capture-protocol.md` and its pt-BR copy (SPEC 0164), sit loose at the top level beside six directories.
- `architecture/` and `ml/` both hold studies and verdicts, under names that do not say so. `architecture/` also holds two documents that no longer describe the project:
  - `ml-handoff.md` calls itself the "short, current state" and was last updated on 2026-09-22.
  - `soil-classification.md` is the 2026-07-30 study that `ml-handoff.md` itself records as drifted: 44 of 95 verified claims are not true as written (#189).
- Three trees are kept only as references that nothing reads today:
  - `reverse-engineering/` (SPEC 0112, 25 files) documents a third-party app;
  - `design/ux-2026/` (15 files) holds the UX studies that redesign v11 replaced, and `design/spec/` is the design of record;
  - `design/prototipo-v11/` is the v11 HTML prototype and its video. After SPEC 0252 it reads its images from `design/spec/`.
- No document says where anything is.

The Developer asked on 2026-11-03 to delete those three trees and the two stale architecture documents, and to regroup what remains.

## Design Decision

The new layout:

```
docs/
├── README.md          new: what each directory holds, and where moved files went
├── adr/               unchanged (paths.adr)
├── specs/             unchanged (paths.specs)
├── agents/            unchanged (paths.agents_overlay)
├── guides/            capture-protocol.md, capture-protocol.pt-BR.md
├── studies/
│   ├── architecture/  corpus-assets, ml-implementation-map, research-agent,
│   │                  research-agent-implementation-map
│   └── ml/            the eleven run verdicts and studies, unchanged in content
└── design/            README.md and spec/
```

`adr/`, `specs/` and `agents/` stay where they are because `.framework.toml` names them and `mf` reads them there. `architecture/` and `ml/` move together under `studies/`, so the relative links between them (`../ml/…` from `architecture/`, `../architecture/…` from `ml/`) keep resolving unchanged.

References are handled by what kind of document holds them:

- **Living documents and code** are updated to the new paths: the README, `ml/README.md`, `corpus/README.md`, the agents overlay, the ADRs, the moved documents themselves, comments under `lib/`, `ml/` and `corpus/`, the tests, and `.framework.toml`.
- **A living reference to a deleted document** becomes a GitHub permalink to the document at `10f490937fc4787423e1b90889303a8a597be479`, the last `main` that holds every one of them. The citation keeps its section number and still leads to the exact text it cited. This applies to 9 ADRs, 3 `lib/` comments, 1 `ml/src/` comment and the kept studies.
- **Specs are not edited.** `ml/tests/test_records.py` names `docs/specs/` a durable archive whose text stays as approved, and 50 specs mention a path this change moves or deletes. `docs/README.md` carries an old-path → new-path table, so a reader of an old spec can find a moved file, and git history keeps every deleted one.

Two guards make the layout hold:

- `test/standards/docs_layout_test.dart`, test `docs_top_level_is_the_declared_layout`: the entries directly under `docs/` are exactly `README.md`, `adr`, `agents`, `design`, `guides`, `specs` and `studies`.
- `test/standards/docs_links_resolve_test.dart`, test `every_relative_doc_link_resolves`: every relative Markdown link in `README.md`, `ml/README.md`, `corpus/README.md` and every `.md` under `docs/` except `docs/specs/` resolves to an existing file. There are 346 such links on `main` today, and none is broken, so the guard starts green on `main` and catches any link the move breaks.

The ML record guards follow the move:

- `ARCHITECTURE_DIR` becomes `docs/studies/architecture`.
- The durable-archive exclusion matches `specs` and `studies/ml` by relative path rather than by first path segment.
- The two tests that read `ml-handoff.md` beside `ml-implementation-map.md` (`test_the_records_agree_on_what_blocks_the_gate`, `test_no_living_record_calls_the_gate_next`) read the map alone. Each test checks the map exactly as before; only the deleted document leaves the pair.
- `.framework.toml`'s `exempt_paths` entry `docs/ml/*` becomes `docs/studies/ml/*`, and its comment changes with it.

## Alternatives Considered

- **Edit the 50 specs to the new paths.** Rejected. Specs are the durable archive, and a mechanical rewrite of approved text is what that rule exists to prevent. The old-path table serves the same reader.
- **Delete the stale documents but keep the layout.** Rejected, because the Developer asked for the regroup.
- **Move `adr/` and `specs/` under a `records/` directory.** Rejected. It means changing `paths.specs` and `paths.adr` and every `mf` check that reads them, for a name the framework already defines.
- **Keep `soil-classification.md` because ADRs cite it.** Rejected. A permalink keeps the citation exact, and keeping a study the project records as 46% wrong invites readers to trust it.

## Scope

- Includes:
  - deleting `docs/reverse-engineering/`, `docs/design/ux-2026/`, `docs/design/prototipo-v11/`, `docs/architecture/ml-handoff.md` and `docs/architecture/soil-classification.md`;
  - moving `docs/capture-protocol*.md` to `docs/guides/`, `docs/architecture/` to `docs/studies/architecture/` and `docs/ml/` to `docs/studies/ml/`, with `git mv` so history follows;
  - the new `docs/README.md`, and `docs/design/README.md` rewritten without the prototype;
  - updating references in living documents, code comments, tests and `.framework.toml` as described above, then `mf agents sync`;
  - the two new standards tests, and the ML record-guard changes above.
- Does NOT include:
  - editing any file under `docs/specs/`;
  - changing the content of a moved document, beyond its paths and links;
  - changing any ADR's decision or status;
  - `paths.*` in `.framework.toml`;
  - any code or UI behaviour.

## Acceptance Criteria

- `docs_top_level_is_the_declared_layout` fails on `main` and passes after the change.
- `every_relative_doc_link_resolves` passes both before and after the change.
- Outside `docs/specs/`, no tracked file mentions `docs/architecture/`, `docs/ml/`, `docs/capture-protocol`, `reverse-engineering`, `ux-2026`, `prototipo-v11`, `ml-handoff` or `soil-classification` except as a permalink at `10f4909` or in `docs/README.md`'s old-path table.
- `flutter analyze` reports no issues, and `flutter test` shows no failures beyond the four this machine has on `main`.
- `python -m pytest` in `ml/` shows no failures beyond `test_pipeline_golden_generation_is_deterministic`, the known float drift, and `corpus/` passes.
- `mf check` passes.

## Reproducibility

Flutter 3.44.1 / Dart 3.12.1 in CI; checked locally on Flutter 3.47.7, `ml/.venv` (Python 3.12) and a scratch corpus venv. Run `flutter test test/standards`, `flutter test`, `flutter analyze`, `python -m pytest` in `ml/` and in `corpus/`, and `mf check`.

## Risks and Assumptions

- **Stacked on SPEC 0252.** This branch starts from `chore/remove-dead-code-and-stale-docs` (PR #480), which already edits `docs/design/`. The pull request targets that branch until #480 merges.
- **Permalinks depend on GitHub.** A permalink at a commit stays valid as long as the repository and that commit exist. The same text also stays reachable with `git show 10f4909:<path>`.
- **The Spec Gate exemption moves.** A run verdict must now land under `docs/studies/ml/` to be exempt. No spec names a `docs/ml/` verdict that is not yet written. One approved before this change that did would need the new path when its verdict landed.
