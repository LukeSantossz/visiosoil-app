<!-- This repository's own instruction sections. `paths.agents_overlay` in
     .framework.toml names it, and `mf agents sync` appends the sections below
     to each generated vendor file, after the framework's and for the same
     roles. Edit this file, never CLAUDE.md or AGENTS.md.

     The framework's instructions come from `.standards/docs/agents/instructions.md`,
     which this repository vendors and does not own. Everything VisioSoil has to
     say beyond them belongs here. -->

<!-- mf:role shared -->
## This project

**VisioSoil** — Cross-platform Flutter mobile app for geolocated soil texture analysis. Agronomists photograph soil samples, record GPS coordinates, and get on-device classification by classical texture descriptors computed in Dart from a released contract of numbers (ADR 0024; 4 soil texture classes; the delivered archive holds five, and ADR 0016 keeps Siltosa out of the first model).

**Stack:** Flutter 3.x / Dart 3.12+ / Riverpod / GoRouter / Drift+SQLite, and no ML runtime: the classifier is Dart arithmetic over `assets/models/spec.json`. Two Python 3.12 side-builds produce assets the app reads and ship nothing at run time: `ml/` trains and exports the classifier, and `corpus/` builds the reviewed corpus the management-tips feature composes from.

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
- **The thesis article's material under `docs/tcc/` is in pt-BR and is exempt**
  from the same rule (SPEC 0145). The exemption is the directory and nothing
  else: a spec, ADR, commit, pull request or issue about the article stays in
  English. Do not translate it. The article itself lives in its authors' Drive,
  and its direction is theirs: the material checks the draft's claims against
  the code and does not rewrite it around the code.
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

## Writing the thesis article (TCC)

The Developer and a co-author are writing an undergraduate thesis article about
this app, in pt-BR, on their institution's template. The article is theirs. This
repository supplies the facts about the app and keeps the working material under
`docs/tcc/` (SPEC 0145); `docs/tcc/guia-de-redacao.md` is the procedure, and
everything below applies to any session that writes, reviews or answers a
question about the article.

- **Check the sources before anything else, every session.** The draft changes
  daily and the app faster, so nothing about the article comes from memory, from
  an earlier session or from a copy in this repository. The check has four steps:
  1. List the authors' Drive folder named in the guide's inventory, and compare
     each file's modified time with the last entry in `docs/tcc/conferencias.md`.
  2. Read the working copy (the "TCC" tab of the Google Doc the guide names by
     title), its other tabs, of which "Dicas - Eloiza" holds the advisors'
     writing rules, and its open comment threads. When an export in the folder
     differs from the tab, say which is newer and ask before editing either.
  3. Check every statement the article makes about the app against `main` as it
     stands that day, not against the commit a survey under `docs/tcc/`
     describes.
  4. Append the check to `docs/tcc/conferencias.md`: the date, the files and the
     commit read, and each divergence with the source that shows it.
- **Report a divergence; do not resolve it.** The direction is the authors'. The
  article is an overview of how the app was built, not a treatise on the model.
  It keeps the management-recommendations feature as they wrote it, and it
  describes the current model only. Edits go where the authors ask, and none
  replaces their text without their instruction.
- **Never write the Google Doc's identifier or link into the repository.** The
  repository is public and the document's sharing is the authors' to manage. Find
  it in Drive by its title.
- **State only what a source records.** Every reference is checked against its
  source and every number against the record or command the guide names. A claim
  that cannot be confirmed is flagged as such, never filled with a plausible
  value. The prose rules (the template's formatting, the advisors' rules, and no
  AI-assistant vocabulary or dashes in running text) are in the guide.

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
UI (Screens) → Riverpod Providers → Repository (abstract) → Drift DB / descriptor path
```

- **State management:** `flutter_riverpod` — `Provider` for singletons, `StreamProvider` for reactive lists, `FutureProvider.family` for record-by-id lookups
- **Navigation:** `go_router` with 7 routes plus an `errorBuilder` rendering `RouteErrorView`. `/details` and `/preview` pass record id via `state.extra` (not URL params)
- **Persistence:** Drift + SQLite with schema versioning (currently v7). Repository pattern abstracts Drift from UI
- **AI inference:** `InferenceService` parses the released contract once (`assets/models/spec.json`), then runs each photograph through the descriptor path in a separate Dart `Isolate`: decode, bake the EXIF orientation, measure, cut the canonical patch grid, describe each patch, and score with the contract. The contract is copied into the isolate because `rootBundle` is unavailable there. The measurement is an injected `PhotographMeasurer` (SPEC 0083), and the default is `a4SheetMeasurer`: it finds the A4 sheet, rectifies it, and measures the round soil patch on it (SPEC 0091, SPEC 0092)
- **Auth:** Google sign-in behind an `AuthService` interface, with the session persisted through `SecureCredentialStore`
- **Research agent:** answers on the device. `researchServiceProvider` binds `CorpusResearchService`, which composes a `ManagementTipsResult` out of a reviewed corpus the app holds — no network, no proxy, no model at run time (ADR 0022, narrowed by ADR 0023). `ProxyResearchService` is kept as the transport for fetching corpus *releases*, and has no caller yet

### Key Architectural Decisions

- **Repository pattern:** `SoilRecordRepository` (abstract) → `DriftSoilRecordRepository`. UI only imports the interface via providers, never Drift types directly
- **Reactive data:** `watchAll()` stream from Drift feeds `StreamProvider`, so history/home auto-update on DB changes
- **Testing DB:** `AppDatabase.forTesting(NativeDatabase.memory())` enables in-memory SQLite for repository tests
- **Schema migrations:** Handled in `AppDatabase.migration` with cumulative version checks (`if (from < 2)`, `if (from < 3)`, `if (from < 4)`). The v5 step is the exception — `if (from >= 4 && from < 5)` — because the v4 step's `createTable` builds `management_tips` from today's definition, so a pre-v4 database already arrives with the v5 column. The v6 step changes no table's shape: it erases the content of tombstones written before SPEC 0093
- **Soft deletes:** Deletes write a tombstone (`deleted` flag) and enqueue a sync operation instead of removing the row; all reads exclude tombstoned rows. A tombstone keeps only what sync reads — uuid, `remote_id`, `updated_at` and the flag — and the record's content and cached tips are erased (SPEC 0093)

### Code Organization

```
lib/
├── main.dart                          # Entry: ProviderScope + MaterialApp.router
├── core/
│   ├── theme/                         # AppTheme.light + .dark, AppPalette (the colour roles
│   │                                  #   widgets read, light and dark), AppColors (light
│   │                                  #   values; read only here), AppTypography, AppSpacing,
│   │                                  #   AppRadius, SoilTextureColors
│   ├── routes/app_router.dart         # GoRouter config (7 routes + errorBuilder)
│   ├── constants/app_strings.dart     # Centralized pt-BR UI strings
│   ├── widgets/                       # 7 reusable: VisioAppBar, VisioButton, EmptyState,
│   │                                  #   ErrorState, LoadingIndicator, PermissionDeniedView,
│   │                                  #   RouteErrorView
│   ├── utils/                         # LocationService (GPS+geocoding), Formatters
│   ├── services/                      # inference_service.dart (descriptor path, isolate-based),
│   │   │                              #   image_storage_service.dart (EXIF strip boundary),
│   │   │                              #   share_service.dart + share_content_builder.dart,
│   │   │                              #   connectivity_service.dart, permission_service.dart,
│   │   │                              #   sync_engine.dart, lost_capture_service.dart (a photo
│   │   │                              #   Android lost to a restart, read on arriving home),
│   │   │                              #   appearance_store.dart (theme choice + the channel
│   │   │                              #   Android's launch night mode reads),
│   │   │                              #   error_report_store.dart (local report of uncaught
│   │   │                              #   errors, shared from Settings; SPEC 0110)
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
└── providers/                         # 18 files declaring 34 providers (database, repository,
                                       #   inference, image, auth, connectivity, share, research,
                                       #   corpus store, site resolver, management tips, image
                                       #   storage, lost capture, appearance, error report, plus the history
                                       #   filter/search and derived-stats providers)
```

### Database Schema (v7)

Three tables, declared in `@DriftDatabase(tables: [SoilRecords, SyncQueue, ManagementTips])`.

`soil_records`: `id` (PK auto), `uuid` (unique index), `remote_id?`, `sync_status` (default `pending`), `image_path`, `latitude?`, `longitude?`, `address?`, `timestamp`, `updated_at`, `deleted` (default `false`), `texture_class?`, `confidence_score?`, `class_distribution?`, `model_version?`, `dataset_version?`. The last three are what scored the photograph (SPEC 0097): every class's probability as a JSON array in the contract's class order, and the contract's versions. They are null when not known, which is the case for a record saved before v7 or without a classification

`sync_queue`: outbox of pending sync operations, drained by `SyncEngine`.

`management_tips`: read-through cache for the research agent — `record_uuid`, `payload_json`, `retrieved_at`, `corpus_version?`. The version is nullable because a row cached before v5 has no known one, and a fabricated default would claim a currency it never had; `CachedManagementTips.isStaleAgainst` compares it by exact string inequality.

Migrations: v1→v2 adds the classification columns; v2→v3 adds the sync metadata, creates `sync_queue`, backfills uuid/`updated_at` per row, normalizes legacy timestamps to UTC and enqueues an `upsert` per legacy record; v3→v4 creates `management_tips`; v4→v5 adds `corpus_version` to it, guarded by `from >= 4 && from < 5` for the reason under Key Architectural Decisions; v5→v6 erases every tombstone's content and drops its cached tips, as a delete now does; v6→v7 adds the three classification-provenance columns, NULL on every existing row, tombstones included.

## Conventions

- **Language:** Commit messages, code comments, and variable names in English.
- **Commits:** `type(scope): subject` — no body, no co-authored-by. Imperative mood, lowercase. Format: `git commit -m "type(scope): subject"` — nothing else.
- **Branches:** `type/short-description`
- **Naming:** VAR Method suffixes — `Service`, `Repository`, `Provider`, `Handler`, `Manager`, etc.
- **Linting:** `flutter_lints` via `analysis_options.yaml`
- **PR Labels:** Always include type label (`feat`, `fix`, etc.) and complexity label (`patch`, `minor`, `major`)

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on push/PR to `main` or `dev`, eight jobs:
1. **analyze** — `flutter analyze`
2. **test** — `flutter test` (installs `libsqlite3-dev` on Ubuntu for Drift; checks out with `fetch-depth: 0`, which the durable-numbering guard needs)
3. **ml-tests** — `python -m pytest tests/` in `ml/` on Python 3.12, with `permissions: contents: read`
4. **corpus-tests** — `python -m pytest tests/` in `corpus/` on Python 3.12, mirroring `ml-tests`: same least-privilege token, actions pinned to commit SHAs, and no model or network because the chain is driven by a scripted client and the fetcher by an injected transport
5. **build** — `flutter build apk --release` (needs analyze + test + ml-tests + corpus-tests), then verifies R8 kept the auth classes in the release DEX, proves an unflagged release app bundle refuses the debug key (SPEC 0111), builds the bundle with the named opt-out and prints its signer (SPEC 0102)
6. **build-ios** — `flutter build ios --release --no-codesign` on macOS (needs analyze + test)
7. **smoke** — boots the minified release APK on an emulator at API 34, 35 and 36, one leg each (needs build)
8. **gates** — the standards gates the hooks run, so a clone that never wired `core.hooksPath` still meets them (SPEC 0085). It installs `mf` at the `framework_version` `.framework.lock` pins, from the release asset with its checksum verified, and fails if the binary reports another version. It runs `mf check` on a pull request, after restoring the head and base refs that `actions/checkout` leaves detached, and `mf check docs records agents design` on any other event

## Current Limitations

- The released classifier is `assets/models/spec.json`, which is tracked: the descriptor contract `1.0.0`, fitted on `v1` by `ml/src/release.py` and promoted by `ml/scripts/deploy_to_app.sh` (SPEC 0082, ADR 0012). `InferenceService` reads it and runs the descriptor path (SPEC 0083), with the scale read from the A4 sheet (SPEC 0092). **The sheet reader is graded on synthetic scenes**, drawn by `ml/scripts/generate_sheet_fixtures.py`, **and on one session of real photographs** (SPEC 0140, `docs/ml/sheet-reader-real-photographs.md`). It reads 24 of those 31 and refuses the rest by name, but every one it reads stops at `soilRegionTooSmall` because the soil patch is smaller than the grid needs, so no real photograph has been classified yet. Photographs taken fully to ADR 0017's protocol must validate it before the Play release (ADR 0026). A photograph without a readable sheet is refused by name, and a scale is never guessed (ADR 0017)
- Camera-only capture by design — gallery source will not be added
- Sync foundation is implemented (uuid, `updated_at`, tombstones, `sync_queue` outbox, `SyncEngine`, `RemoteSyncBackend` contract) but **no concrete backend exists and `SyncEngine` is not wired into the provider graph** — data is still device-local
- Management tips compose on the device and answer offline, but **no reviewed corpus artifact exists yet**. `assets/corpus/` holds only `.gitkeep` and a README, and `corpus.json` plus both `.bin` grids are git-ignored the way the `.tflite` is. Until the corpus build releases one, every key composes to `insufficient_evidence` and the surface reads that as absent coverage — which is a normal state, not an error
- The corpus **refresh** half is not built: there is no release endpoint, so a device can only ever read the bundled snapshot. That is where being offline means "cannot refresh", and it is also where the connectivity gate removed from `ManagementTipsController` belongs
- `drift_flutter` pinned to `>=0.2.0 <0.2.4` — do not bump without verifying compatibility

## Known Technical Debt

- The CNN training path under `ml/` (`model.py`, `train.py`, `preprocess.py`) stays as E0's incumbent and control arms: the shuffled control *is* the CNN trained on permuted labels, so removing it would leave the recorded verdict unreproducible, and that takes its own ADR. SPEC 0084 removed only the TFLite export. `preprocess.py` still resizes without antialiasing, and changing it would change numbers E0 recorded
- `InferenceService.classify` reports a `ClassificationReport` — an outcome and, on failure, one of ADR 0015's fourteen named causes, as amended by SPEC 0083 and SPEC 0092 — since SPEC 0078. `initialize` produces the three contract causes, the sheet reader produces `sheetNotFound` and `sheetCropped`, and `rejectedOod` has no producer at all. The capture preview names the cause in its chip and offers a retry only for `timeout`, `isolateFailure` and `computationError` (SPEC 0105). A saved record keeps no cause, and the named processing phases and fuller retake flow remain the UI/UX terminal's roadmap items
- The model's class list is four (ADR 0016, SPEC 0046) and the archive's vocabulary is five; `src.manifest.ARCHIVE_CLASSES` is what a manifest row may say and `cfg["classes"]` is what the model emits. The shipped contract's classes are asserted against `ml/config.yaml` by `test/standards/class_list_test.dart` (SPEC 0048, SPEC 0083), so the two languages can no longer drift. What remains is that several Python test modules still carry their own five-entry literal of the *archive* vocabulary, tied to `ARCHIVE_CLASSES` only in `test_manifest.py`
- `ClassificationVerdict` (ADR 0011) and `ImageQualityAnalyzer` (SPEC 0030) are implemented and tested with zero production callers, each waiting on a wiring spec — the UI/UX terminal's roadmap items 2 and 6 respectively. Both are deliberate, and both are recorded in their specs' Scope
- The corpus build carries **six modules that shipped ahead of their own Spec Gate** — `corpus/src/keys.py`, `clay_activity.py`, `grids.py`, `build_grids.py`, `embrapa_units.py` and `search.py`. SPEC 0071's Scope excludes them explicitly, and no other spec covers them. `mf check spec` passes anyway, so **the gate detects a missing specification but not code that outruns one**. Three of them — `keys.py`, `embrapa_units.py` and `search.py` — also have no production caller until the full corpus build lands

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
