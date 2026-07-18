# SPEC: docs: sync CLAUDE.md and README with the implemented state

## Problem

`CLAUDE.md` and `README.md` describe a smaller, older application than the one in `lib/`, so every agent and contributor who trusts them starts from false facts — the most load-bearing being a database schema documented as v2 when it is v4, and a sync layer documented as absent when its foundation is implemented.

## Scope

- Includes: correcting in `CLAUDE.md` and `README.md` the schema version and migration list, the `soil_records` column list, the code-organization trees, the Tech Stack table, the Project Status lists, and the Known Issues section; indexing in the README's Engineering Decisions the five ADRs present under `docs/adr/` but never linked (`0001`, `0002`, `0004`, `0005`, `0006`).
- Does NOT include: any change to code, tests or behavior; rewriting the ADRs or specs themselves; the `.standards` submodule bump, which is a separate change tracked on its own issue; documenting features that do not exist yet.

## Acceptance Criteria

Each criterion is verified by reading the cited source, not by an automated test — this change has no runtime surface.

- `schema_version_matches_app_database` — both files state schema v4 and list the v2, v3 and v4 migration steps, matching `app_database.dart:24-46`.
- `documented_tables_match_the_drift_annotation` — `SoilRecords`, `SyncQueue` and `ManagementTips` are all listed, matching `app_database.dart:16`.
- `soil_records_columns_match_the_table_definition` — all 13 columns and the unique uuid index are listed, matching `soil_records_table.dart:13-32`.
- `code_organization_lists_every_real_directory` — `constants/`, `data/sync/`, `services/auth/`, `services/research/` and the real widget, model and provider counts appear, matching `lib/`.
- `tech_stack_lists_the_real_dependencies` — auth, secure storage, connectivity and http appear, matching `pubspec.yaml:56-64`.
- `readme_indexes_every_adr` — the Engineering Decisions table links all seven files in `docs/adr/`.
- `model_artifact_claim_is_accurate` — neither file claims a placeholder `.tflite` ships, since `assets/models/` holds only `.gitkeep` and the artifact is git-ignored.
- `sync_claim_is_accurate` — both files state that the sync foundation exists but has no backend and is not wired into the provider graph, rather than that sync is absent.
- `no_documented_claim_is_unverified` — every statement added is traceable to a cited file.
