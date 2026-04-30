# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**VisioSoil** — Cross-platform Flutter mobile app for geolocated soil texture analysis. Agronomists photograph soil samples, record GPS coordinates, and get on-device AI classification using TensorFlow Lite (12 USDA texture classes).

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
- **Navigation:** `go_router` with 5 routes. `/details` and `/preview` pass record id via `state.extra` (not URL params)
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
│   ├── routes/app_router.dart         # GoRouter config (5 routes)
│   ├── widgets/                       # Reusable: VisioAppBar, VisioButton, VisioCard, EmptyState
│   ├── utils/                         # LocationService (GPS+geocoding), Formatters
│   ├── services/inference_service.dart # TFLite classification (isolate-based)
│   ├── database/                      # Drift DB class + tables + generated code
│   ├── data/repositories/             # Abstract interface + Drift implementation
│   └── features/                      # Screens: home, capture, history, details, preview, main
├── models/soil_record.dart            # Domain model (plain Dart, copyWith, computed getters)
└── providers/                         # Riverpod providers (database, repository, inference, image)
```

### Database Schema (v2)

`soil_records` table: `id` (PK auto), `image_path`, `latitude?`, `longitude?`, `address?`, `timestamp`, `texture_class?`, `confidence_score?`

## Governance

This project uses a mandatory governance system defined in `.claude/`. Before modifying code, read `.claude/CLAUDE.md` for the full operating rules. Key points:

- Every code change requires a task registered in `.claude/tasks.md` before implementation
- The agent must declare an operation mode (Development / Review / Tutor) per session
- Codebase reconnaissance (`.claude/rules/02-reconhecimento.md`) is required before implementation
- Post-implementation assessment is mandatory (`.claude/rules/04-avaliacao-pos.md`)
- Project registry (`.claude/registry.md`) must be updated after each completed task
- Full workflow: CRURA — Change → Review → Upload → Review Again → Auto-Review

## Conventions

- **Language:** Commit messages, code comments, and variable names in English. Governance docs (`.claude/`) are in Portuguese.
- **Commits:** `type(scope): subject` — no body, no co-authored-by. Imperative mood, lowercase. Format: `git commit -m "type(scope): subject"` — nothing else.
- **Branches:** `type/TASK-NNN-description`
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
- Gallery image source disabled (camera-only); code preserved behind `TODO(v2)`
- No remote sync yet (repository interface prepared for it)
- `drift_flutter` pinned to `>=0.2.0 <0.2.4` — do not bump without verifying compatibility
- `pubspec.yaml` version (`1.0.0+1`) is out of sync with the logical version (`v1.1.0` per git tags) — to be aligned on next release
