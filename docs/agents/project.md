<!-- This repository's own instruction sections. `paths.agents_overlay` in
     .framework.toml names it, and `mf agents sync` appends the sections below
     to each generated vendor file, after the framework's and for the same
     roles. Edit this file, never CLAUDE.md or AGENTS.md.

     The framework's instructions come from `.standards/docs/agents/instructions.md`,
     which this repository vendors and does not own. Everything VisioSoil has to
     say beyond them belongs here. -->

<!-- mf:role shared -->
## This project

**VisioSoil** — Cross-platform Flutter mobile app for geolocated soil texture analysis. Agronomists photograph soil samples, record GPS coordinates, and get on-device AI classification using TensorFlow Lite (4 soil texture classes; the delivered archive holds five, and ADR 0016 keeps Siltosa out of the first model).

**Stack:** Flutter 3.x / Dart 3.12+ / Riverpod / GoRouter / Drift+SQLite / TFLite. Two Python 3.12 side-builds produce assets the app reads and ship nothing at run time: `ml/` trains and exports the classifier, and `corpus/` builds the reviewed corpus the management-tips feature composes from.

**Toolchain:** Flutter 3.44.1 / Dart 3.12.1, pinned to match CI (`.github/workflows/ci.yml`). Using another 3.x local SDK rewrites `pubspec.lock` on `flutter pub get`.

If `.standards/` is empty — a fresh clone, CI, a remote agent session — run
`git submodule update --init` first. The submodule declares `branch = main`, so
a deliberate bump is `git submodule update --remote --merge .standards`
followed by committing the new gitlink; nothing moves the pin on its own.

## Where this project departs from the standards

The precedence order in `.standards/docs/standards/code_conventions.md` puts an
established project pattern above a framework default, so these are refinements
of the sections above rather than exceptions to them.

- **User-facing UI strings are pt-BR product copy and are exempt** from the
  all-output-in-English rule. Identifiers, comments, commit, PR and issue text,
  and documentation are not.
- **This project declines the Token Economy context-file compression opt-in.**
  The opt-in is a choice the adopter makes, not a framework default, and a
  repository that declines it is fully conformant — so the instruction files
  stay in full prose. The choice is also forced today: compression depends on a
  `caveman-compress` capability the installed Caveman does not provide, and
  hand-rolling a substitute is what `token_economy.md` §1 warns against, since
  nothing would prove the rewrite preserved standards activation.

<!-- mf:role author -->
## Working here

- CRUX explainers (`.standards/docs/standards/crux_method.md`) are an optional
  review aid here: the `explain-change` skill may render a transient HTML
  walkthrough of a change to feed R1 and human review. It is never a review
  layer and never blocks a ship, but its absence is recorded rather than
  silent — if the skill did not run, the reviewer reads the diff directly and
  the PR says the CRUX aid was absent, mirroring the R2 fallback record.
- **R2 runs twice, after the pull request is opened and before it is merged**,
  and not on push. Both rounds are `mf review --role r2`, which reaches
  Antigravity pinned to a GPT model; a Claude model there would meet the
  cross-provider rule by name while being the Author's own vendor. Two rounds
  rather than one because the second reads the change after the first round's
  findings have been answered, and rather than more because a third round on an
  unchanged diff repeats the second. Push with `SKIP_R2_REVIEW=1` — the hook
  prints that R2 did not run, which is true of the push and not of the pull
  request, so the PR records both rounds and the model that answered.
- Specs are numbered durably under `docs/specs/NNNN-<slug>.md`; a number is
  never reused, and `test/standards/durable_numbering_test.dart` replays each
  number's history in commit order to enforce it. Contiguity is checked on
  `main` only, because a gap on a feature branch is normally a number a
  concurrent pull request reserved.

## Commands

```bash
# Install dependencies
flutter pub get

# Generate Drift database adapters (required after DB schema/table changes)
dart run build_runner build --delete-conflicting-outputs

# Static analysis (linting)
flutter analyze

# Run all tests
flutter test

# Run a single test file
flutter test test/soil_record_test.dart

# Build release APK
flutter build apk --release

# Run on connected device/emulator
flutter run

# Corpus build tests (Python 3.12, in corpus/ — no model and no network needed)
python -m pytest corpus/tests -q
```

## Architecture

### Layer Overview

```
UI (Screens) → Riverpod Providers → Repository (abstract) → Drift DB / TFLite
```

- **State management:** `flutter_riverpod` — `Provider` for singletons, `StreamProvider` for reactive lists, `FutureProvider.family` for record-by-id lookups
- **Navigation:** `go_router` with 7 routes plus an `errorBuilder` rendering `RouteErrorView`. `/details` and `/preview` pass record id via `state.extra` (not URL params)
- **Persistence:** Drift + SQLite with schema versioning (currently v5). Repository pattern abstracts Drift from UI
- **AI inference:** TFLite model runs in a separate Dart `Isolate` via `InferenceService` to avoid blocking UI. Model bytes loaded from assets since `rootBundle` is unavailable in isolates
- **Auth:** Google sign-in behind an `AuthService` interface, with the session persisted through `SecureCredentialStore`
- **Research agent:** answers on the device. `researchServiceProvider` binds `CorpusResearchService`, which composes a `ManagementTipsResult` out of a reviewed corpus the app holds — no network, no proxy, no model at run time (ADR 0022, narrowed by ADR 0023). `ProxyResearchService` is kept as the transport for fetching corpus *releases*, and has no caller yet

### Key Architectural Decisions

- **Repository pattern:** `SoilRecordRepository` (abstract) → `DriftSoilRecordRepository`. UI only imports the interface via providers, never Drift types directly
- **Reactive data:** `watchAll()` stream from Drift feeds `StreamProvider`, so history/home auto-update on DB changes
- **Testing DB:** `AppDatabase.forTesting(NativeDatabase.memory())` enables in-memory SQLite for repository tests
- **Schema migrations:** Handled in `AppDatabase.migration` with cumulative version checks (`if (from < 2)`, `if (from < 3)`, `if (from < 4)`). The v5 step is the exception — `if (from >= 4 && from < 5)` — because the v4 step's `createTable` builds `management_tips` from today's definition, so a pre-v4 database already arrives with the v5 column
- **Soft deletes:** Deletes write a tombstone (`deleted` flag) and enqueue a sync operation instead of removing the row; all reads exclude tombstoned rows

### Code Organization

```
lib/
├── main.dart                          # Entry: ProviderScope + MaterialApp.router
├── core/
│   ├── theme/                         # AppTheme.light, AppColors, AppTypography, AppSpacing,
│   │                                  #   AppRadius, SoilTextureColors
│   ├── routes/app_router.dart         # GoRouter config (7 routes + errorBuilder)
│   ├── constants/app_strings.dart     # Centralized pt-BR UI strings
│   ├── widgets/                       # 7 reusable: VisioAppBar, VisioButton, EmptyState,
│   │                                  #   ErrorState, LoadingIndicator, PermissionDeniedView,
│   │                                  #   RouteErrorView
│   ├── utils/                         # LocationService (GPS+geocoding), Formatters
│   ├── services/                      # inference_service.dart (TFLite, isolate-based),
│   │   │                              #   image_storage_service.dart (EXIF strip boundary),
│   │   │                              #   share_service.dart + share_content_builder.dart,
│   │   │                              #   connectivity_service.dart, permission_service.dart,
│   │   │                              #   sync_engine.dart
│   │   ├── auth/                      # AuthService, GoogleAuthService, GoogleSignInGateway,
│   │   │                              #   SecureCredentialStore, KeyValueSecureStorage
│   │   ├── region/                    # SiteResolver, GridSiteResolver + PackedGrid (VSG1),
│   │   │                              #   CorpusGridAssets, AssetGridSiteResolver
│   │   └── research/                  # ResearchService, CorpusResearchService (the binding
│   │                                  #   wired today), CorpusComposer, CorpusStore +
│   │                                  #   AbsentCorpusStore + AssetCorpusStore,
│   │                                  #   ManagementTipsController,
│   │                                  #   ProxyResearchService + HttpTransport (no caller yet)
│   ├── database/                      # Drift DB class + tables/ + generated code + mapper
│   ├── data/
│   │   ├── repositories/              # Abstract interfaces + Drift implementations
│   │   │                              #   (soil records, management tips)
│   │   └── sync/                      # RemoteSyncBackend contract, SyncLocalStore, SyncOperation
│   └── features/                      # Screens: splash, onboarding, main, home, capture,
│                                      #          history, details, preview, settings
├── models/                            # SoilRecord, HomeStats, ConfidenceLevel,
│                                      #   ManagementTipsResult + TipsCoverage,
│                                      #   SiteKey, ClayActivity, Biome, LandUse
└── providers/                         # 15 files declaring 27 providers (database, repository,
                                       #   inference, image, auth, connectivity, share, research,
                                       #   corpus store, site resolver, management tips, image
                                       #   storage, plus the history filter/search and
                                       #   derived-stats providers)
```

### Database Schema (v5)

Three tables, declared in `@DriftDatabase(tables: [SoilRecords, SyncQueue, ManagementTips])`.

`soil_records`: `id` (PK auto), `uuid` (unique index), `remote_id?`, `sync_status` (default `pending`), `image_path`, `latitude?`, `longitude?`, `address?`, `timestamp`, `updated_at`, `deleted` (default `false`), `texture_class?`, `confidence_score?`

`sync_queue`: outbox of pending sync operations, drained by `SyncEngine`.

`management_tips`: read-through cache for the research agent — `record_uuid`, `payload_json`, `retrieved_at`, `corpus_version?`. The version is nullable because a row cached before v5 has no known one, and a fabricated default would claim a currency it never had; `CachedManagementTips.isStaleAgainst` compares it by exact string inequality.

Migrations: v1→v2 adds the classification columns; v2→v3 adds the sync metadata, creates `sync_queue`, backfills uuid/`updated_at` per row, normalizes legacy timestamps to UTC and enqueues an `upsert` per legacy record; v3→v4 creates `management_tips`; v4→v5 adds `corpus_version` to it, guarded by `from >= 4 && from < 5` for the reason under Key Architectural Decisions.

## Conventions

- **Language:** Commit messages, code comments, and variable names in English.
- **Commits:** `type(scope): subject` — no body, no co-authored-by. Imperative mood, lowercase. Format: `git commit -m "type(scope): subject"` — nothing else.
- **Branches:** `type/short-description`
- **Naming:** VAR Method suffixes — `Service`, `Repository`, `Provider`, `Handler`, `Manager`, etc.
- **Linting:** `flutter_lints` via `analysis_options.yaml`
- **PR Labels:** Always include type label (`feat`, `fix`, etc.) and complexity label (`patch`, `minor`, `major`)

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on push/PR to `main` or `dev`, seven jobs:
1. **analyze** — `flutter analyze`
2. **test** — `flutter test` (installs `libsqlite3-dev` on Ubuntu for Drift; checks out with `fetch-depth: 0`, which the durable-numbering guard needs)
3. **ml-tests** — `python -m pytest tests/` in `ml/` on Python 3.12, with `permissions: contents: read`
4. **corpus-tests** — `python -m pytest tests/` in `corpus/` on Python 3.12, mirroring `ml-tests`: same least-privilege token, actions pinned to commit SHAs, and no model or network because the chain is driven by a scripted client and the fetcher by an injected transport
5. **build** — `flutter build apk --release` (needs analyze + test + ml-tests + corpus-tests), then verifies R8 kept the auth classes in the release DEX
6. **build-ios** — `flutter build ios --release --no-codesign` on macOS (needs analyze + test)
7. **smoke** — boots the minified release APK on an emulator (needs build)

## Current Limitations

- No TFLite model artifact is tracked in the repo — `assets/models/` holds only `.gitkeep`, and `.gitignore` ignores both `assets/models/*.tflite` and `assets/models/spec.json`. `InferenceService` expects `assets/models/soil_classifier.tflite`; classification stays unavailable until the training pipeline exports that artifact into `assets/models/`
- Camera-only capture by design — gallery source will not be added
- Sync foundation is implemented (uuid, `updated_at`, tombstones, `sync_queue` outbox, `SyncEngine`, `RemoteSyncBackend` contract) but **no concrete backend exists and `SyncEngine` is not wired into the provider graph** — data is still device-local
- Management tips compose on the device and answer offline, but **no reviewed corpus artifact exists yet**. `assets/corpus/` holds only `.gitkeep` and a README, and `corpus.json` plus both `.bin` grids are git-ignored the way the `.tflite` is. Until the corpus build releases one, every key composes to `insufficient_evidence` and the surface reads that as absent coverage — which is a normal state, not an error
- The corpus **refresh** half is not built: there is no release endpoint, so a device can only ever read the bundled snapshot. That is where being offline means "cannot refresh", and it is also where the connectivity gate removed from `ManagementTipsController` belongs
- `drift_flutter` pinned to `>=0.2.0 <0.2.4` — do not bump without verifying compatibility

## Known Technical Debt

- Labels and preprocessing are hardcoded in `InferenceService` — `spec.json` is generated by `ml/src/export.py` into `models/<version>/`, not into `assets/models/`, and is not read at runtime. `assets/models/spec.json` is git-ignored; ADR 0012 decided it becomes tracked, and SPEC 0035 is the gate-approved specification that reads the contract and removes the ignore entry. Not implemented yet (#79)
- `InferenceService.classify` returns `null` for the six distinct causes ADR 0011 enumerates — a missing model asset, an isolate spawn failure, a timeout, a decode failure, a class-count mismatch, and an inference error — so the caller cannot tell a feature that was never available from a run that failed. ADR 0011 accepted this with an explicit price: **no result surface may offer retry on `notAnalysed` until SPEC 0035 lands**. ADR 0015 records the taxonomy that replaces it
- The model's class list is four (ADR 0016, SPEC 0046) and the archive's vocabulary is five; `src.manifest.ARCHIVE_CLASSES` is what a manifest row may say and `cfg["classes"]` is what the model emits. `SoilTextureLabels.ordered` is asserted against `ml/config.yaml` by `test/standards/class_list_test.dart` (SPEC 0048), so the two languages can no longer drift. What remains is that several Python test modules still carry their own five-entry literal of the *archive* vocabulary, tied to `ARCHIVE_CLASSES` only in `test_manifest.py`
- `ClassificationVerdict` (ADR 0011) and `ImageQualityAnalyzer` (SPEC 0030) are implemented and tested with zero production callers, each waiting on a wiring spec — the UI/UX terminal's roadmap items 2 and 6 respectively. Both are deliberate, and both are recorded in their specs' Scope
- The corpus build carries **six modules that shipped ahead of their own Spec Gate** — `corpus/src/keys.py`, `clay_activity.py`, `grids.py`, `build_grids.py`, `embrapa_units.py` and `search.py`. SPEC 0071's Scope excludes them explicitly, and no other spec covers them. `mf check spec` passes anyway, so **the gate detects a missing specification but not code that outruns one**. Three of them — `keys.py`, `embrapa_units.py` and `search.py` — also have no production caller until the full corpus build lands
- `TipsCoverage` reports `substanceIsGeneric: true` and `clayActivity: null` even when the composition reached a **family-specific** substance cell through `clayActivityDefaultByBiome`. The assumed family reaches no output field, so the reader cannot tell a generic answer from one inferred from biome — the proxy the 2026-09-11 agronomic review found lossy and ADR 0022 re-keyed away from. Pinned by `golden.json`'s `generic_substance_from_the_biome_default` case; fixing it is a contract change and is tracked as #246

<!-- mf:role reviewer -->
## Reviewing here

The stack, the layering and the schema are in `## This project` above and in
`README.md`. What a reviewer needs beyond them:

- **pt-BR UI strings are product copy**, not a convention violation. Everything
  else this repository writes is English.
- **`InferenceService.classify` returns `null` for six distinct causes**, which
  ADR 0011 accepted at an explicit price: no result surface may offer retry on
  `notAnalysed` until SPEC 0035 lands. A change that adds one contradicts an
  accepted decision, whatever it looks like locally.
- **`drift_flutter` is pinned `>=0.2.0 <0.2.4`.** A bump without a compatibility
  check is a finding.
- **The model emits four classes and the archive holds five**, and they are
  different lists on purpose (SPEC 0046). `test/standards/class_list_test.dart`
  asserts the Dart list against `ml/config.yaml`, so a change touching labels in
  one language and not the other now fails rather than compiling quietly.
- **`ClassificationVerdict` and `ImageQualityAnalyzer` have no production
  callers** by design, each waiting on a wiring spec. Dead-code findings against
  them are answered by their specs' Scope.
- The toolchain is pinned to Flutter 3.44.1 / Dart 3.12.1 to match CI. A local
  3.x SDK that differs rewrites `pubspec.lock` on `flutter pub get`, so a
  lockfile change nobody asked for is that, not a dependency decision.
