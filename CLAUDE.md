# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Standards

Before any development work in this repository, read `.standards/docs/standards/INDEX.md` and the documents it lists. Treat them as binding. If `.standards/` is empty (fresh clone, CI, remote agent session), run `git submodule update --init` first.

- Specify before building: produce a `SPEC.md` per `.standards/docs/standards/spec_method.md` and pass the Spec Gate before writing code for any non-trivial change.
- Follow `.standards/docs/standards/code_conventions.md`, including its precedence order, which is authoritative for resolving any conflict between rules. The project-specific conventions in this file are the project's established pattern (precedence rule 4) and outrank framework defaults.
- Write tests before implementation (red-green-refactor), per the Testing section of `code_conventions.md`.
- Follow `.standards/docs/standards/ai_guidelines.md` for self-review and the Review Composition hierarchy. R1 is the internal subagent review; no second-provider reviewer is configured, so R1 plus human PR review stand in for R2 — note this in each PR. CodeRabbit reviews opened PRs and counts as R3.
- Follow `.standards/docs/standards/github.md` for Conventional Commits, branch naming, and the PR/Issue/README templates. No co-author or AI-attribution lines in commits.
- Token economy per `.standards/token_economy.md` (the file lives at the submodule root, not under `docs/standards/`): terse mode is allowed in conversation but never in `SPEC.md`, PR, issue, or commit artifacts. This file is not kept in caveman-compress form because Caveman is not configured.
- All output in English: identifiers, comments, commit/PR/issue text, documentation. User-facing UI strings are pt-BR product copy and are exempt.

## Project

**VisioSoil** — Cross-platform Flutter mobile app for geolocated soil texture analysis. Agronomists photograph soil samples, record GPS coordinates, and get on-device AI classification using TensorFlow Lite (5 soil texture classes).

**Stack:** Flutter 3.x / Dart 3.10.4+ / Riverpod / GoRouter / Drift+SQLite / TFLite

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
```

## Architecture

### Layer Overview

```
UI (Screens) → Riverpod Providers → Repository (abstract) → Drift DB / TFLite
```

- **State management:** `flutter_riverpod` — `Provider` for singletons, `StreamProvider` for reactive lists, `FutureProvider.family` for record-by-id lookups
- **Navigation:** `go_router` with 11 routes. `/details` and `/preview` pass record id via `state.extra` (not URL params)
- **Persistence:** Drift + SQLite with schema versioning (currently v2). Repository pattern abstracts Drift from UI
- **AI inference:** TFLite model runs in a separate Dart `Isolate` via `InferenceService` to avoid blocking UI. Model bytes loaded from assets since `rootBundle` is unavailable in isolates

### Key Architectural Decisions

- **Repository pattern:** `SoilRecordRepository` (abstract) → `DriftSoilRecordRepository`. UI only imports the interface via providers, never Drift types directly
- **Reactive data:** `watchAll()` stream from Drift feeds `StreamProvider`, so history/home auto-update on DB changes
- **Testing DB:** `AppDatabase.forTesting(NativeDatabase.memory())` enables in-memory SQLite for repository tests
- **Schema migrations:** Handled in `AppDatabase.migration` with version checks (`if (from < 2)`)

### Code Organization

```
lib/
├── main.dart                          # Entry: ProviderScope + MaterialApp.router
├── core/
│   ├── theme/                         # AppTheme.light, AppColors, AppTypography, AppSpacing
│   ├── routes/app_router.dart         # GoRouter config (11 routes)
│   ├── widgets/                       # Reusable: VisioAppBar, VisioButton, EmptyState
│   ├── utils/                         # LocationService (GPS+geocoding), Formatters
│   ├── services/inference_service.dart # TFLite classification (isolate-based)
│   ├── database/                      # Drift DB class + tables + generated code
│   ├── data/repositories/             # Abstract interface + Drift implementation
│   └── features/                      # Screens: splash, onboarding, main, home, capture,
│                                      #          history, details, preview, result, settings
├── models/                            # Domain models: SoilRecord, CaptureContext, HomeStats
└── providers/                         # Riverpod providers (database, repository, inference, image)
```

### Database Schema (v2)

`soil_records` table: `id` (PK auto), `image_path`, `latitude?`, `longitude?`, `address?`, `timestamp`, `texture_class?`, `confidence_score?`

## Conventions

- **Language:** Commit messages, code comments, and variable names in English.
- **Commits:** `type(scope): subject` — no body, no co-authored-by. Imperative mood, lowercase. Format: `git commit -m "type(scope): subject"` — nothing else.
- **Branches:** `type/short-description`
- **Naming:** VAR Method suffixes — `Service`, `Repository`, `Provider`, `Handler`, `Manager`, etc.
- **Linting:** `flutter_lints` via `analysis_options.yaml`
- **PR Labels:** Always include type label (`feat`, `fix`, etc.) and complexity label (`patch`, `minor`, `major`)

## CI Pipeline

GitHub Actions (`.github/workflows/ci.yml`) runs on push/PR to `main` or `dev`:
1. **analyze** — `flutter analyze`
2. **test** — `flutter test` (installs `libsqlite3-dev` on Ubuntu for Drift)
3. **build** — `flutter build apk --release` (depends on analyze + test passing)

## Current Limitations

- TFLite model file (`assets/models/soil_classifier.tflite`) is a placeholder — production model not yet trained
- Camera-only capture by design — gallery source will not be added
- No remote sync yet (repository interface prepared for it)
- `drift_flutter` pinned to `>=0.2.0 <0.2.4` — do not bump without verifying compatibility

## Known Technical Debt

- `/capture/setup` wizard is orphaned: no screen navigates to it, the `/capture` route ignores `state.extra`, and `soil_records` (v2) has no columns for crop/season/depth — either persist `CaptureContext` (schema v3) or remove the wizard
- `/processing` and `/result` routes are registered but have no callers in the UI — integrate or remove
- Labels and preprocessing are hardcoded in `InferenceService` — `spec.json` is not read at runtime
- Address sentinel mismatch: capture saves `'Localizacao nao disponivel'` (unaccented) but `SoilRecord.hasValidAddress` checks accented variants — align the strings
