![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-yellow)
[![CI](https://img.shields.io/github/actions/workflow/status/LukeSantossz/visiosoil-app/ci.yml?branch=dev&logo=github&label=CI)](https://github.com/LukeSantossz/visiosoil-app/actions)

# VisioSoil — Soil Analysis Mobile App

> Cross-platform mobile app for geolocated soil texture analysis, built with Flutter.

## Overview

VisioSoil lets agronomists and field professionals photograph soil samples, record GPS coordinates, and review captured data — with on-device AI classification planned for a future phase. The app is the production-mobile evolution of academic research for soil texture classification.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Android + iOS) |
| Language | Dart |
| State management | Riverpod |
| Navigation | GoRouter |
| Typography | google_fonts |
| Image loading | cached_network_image |
| Camera / Gallery | image_picker *(camera-only por ora)* |
| GPS | geolocator |
| Reverse geocoding | geocoding |
| Local persistence | Drift + SQLite (`sqlite3_flutter_libs`) |
| AI classification | TensorFlow Lite (on-device inference) |

## Getting Started

### Prerequisites

- Flutter SDK 3.x
- Android Studio with an Android emulator, or a connected device
- Xcode (for iOS builds)

### Installation

```bash
# Clone the repository
git clone https://github.com/LukeSantossz/visiosoil-app.git
cd visiosoil-app

# Install dependencies
flutter pub get

# Generate Drift adapters (required after changes to DB tables / models)
dart run build_runner build --delete-conflicting-outputs
```

### Running

```bash
# Run on a connected emulator or device
flutter run

# Static analysis
flutter analyze

# Run tests (unit + repository)
flutter test
```

## Project Structure

```
lib/
├── main.dart                     # App entry point (ProviderScope + MaterialApp.router)
├── core/
│   ├── theme/                    # AppTheme, AppColors, AppTypography, AppSpacing
│   ├── routes/
│   │   └── app_router.dart       # GoRouter — routes use int id (not list index)
│   ├── widgets/                  # VisioAppBar, VisioButton, VisioCard, EmptyState
│   ├── utils/                    # LocationService, formatters
│   ├── services/
│   │   └── inference_service.dart        # TFLite soil texture classification
│   ├── database/
│   │   ├── app_database.dart             # Drift DB class (schemaVersion = 1)
│   │   ├── app_database.g.dart           # generated
│   │   └── tables/
│   │       └── soil_records_table.dart   # @DataClassName('SoilRecordRow')
│   ├── data/
│   │   └── repositories/
│   │       ├── soil_record_repository.dart         # abstract interface
│   │       └── drift_soil_record_repository.dart   # Drift implementation
│   └── features/
│       ├── home/home_page.dart          # Home with latest capture card
│       ├── capture/capture_screen.dart  # Camera + GPS + save (repository.create)
│       ├── history/history_screen.dart  # Grid + multi-select deleteByIds
│       ├── details/details.dart         # FutureProvider getById + deleteById
│       ├── preview/image_preview_screen.dart  # Zoomable viewer (by id)
│       └── main/main_screen.dart        # Tab host
├── models/
│   └── soil_record.dart          # Plain Dart class (id, copyWith, getters)
└── providers/
    ├── image_provider.dart                      # Selected image state
    ├── database_provider.dart                   # AppDatabase singleton
    ├── inference_provider.dart                  # InferenceService singleton
    └── soil_record_repository_provider.dart     # Repository + stream/future providers

assets/
└── models/                       # TFLite model files (soil_classifier.tflite)

## Features

### Capture Flow
- **Camera capture**: Takes photo and automatically records GPS location
- **On-device classification**: TensorFlow Lite model classifies soil texture (5 classes)
- **Confidence score**: Displays classification confidence percentage

### History & Management
- **Grid view**: Thumbnails with timestamp overlay
- **Multi-select**: Long press to enter selection mode
- **Bulk delete**: Delete multiple records at once
- **Preview**: Full-screen image viewer with zoom/pan

### Data Persistence
- **Drift + SQLite storage**: Local database for soil records (schema v2)
- **SoilRecord model**: Image path, coordinates, address, timestamp, texture class, confidence score

## Current Status

**Status: v1.1.0 — TFLite classification integrated**

### Done (v1.1.0)

- [x] Custom Material 3 theme (`AppTheme`, `AppColors`, `AppTypography`, `AppSpacing`)
- [x] Riverpod state management (stream + future providers)
- [x] GoRouter navigation (5 routes — `/details` and `/preview` take a record `id`)
- [x] `BottomNavigationBar` (Home / History)
- [x] Home screen with "last capture" card
- [x] Capture screen (camera-only, `image_picker`)
- [x] Image preview after capture
- [x] History screen with grid, multi-select and batch delete
- [x] Details screen with delete action and classification display
- [x] Image preview (zoomable) screen
- [x] Android + iOS permission handling
- [x] `ImageNotifier` provider for image state
- [x] Real GPS integration (`geolocator` + `geocoding`, via `LocationService`)
- [x] Persistence on **Drift + SQLite** via a `SoilRecordRepository` interface (schema v2)
- [x] `SoilRecord` domain model with `textureClass` and `confidenceScore`
- [x] Repository tests with `NativeDatabase.memory()`
- [x] CI pipeline (analyze + test + APK build)
- [x] ADR 0001 documenting Drift adoption
- [x] **TensorFlow Lite on-device soil texture classification** (12 USDA classes)
- [x] `InferenceService` isolated from UI, runs in isolate (non-blocking)
- [x] Classification result displayed on capture and details screens

### Pending (Phase 2)

- [ ] Train and bundle production TFLite model (currently expects `assets/models/soil_classifier.tflite`)
- [ ] Re-enable gallery source (currently camera-only; kept in code behind `TODO(v2)`)
- [ ] Remote sync (the repository interface already leaves room for a `sync_status` column)
