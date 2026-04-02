![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Status](https://img.shields.io/badge/status-v1.0.0-green)

# VisioSoil — Soil Analysis Mobile App

> Cross-platform mobile app for geolocated soil texture analysis, built with Flutter.

## Overview

VisioSoil lets agronomists and field professionals photograph soil samples, record GPS coordinates, and review captured data — with on-device AI classification planned for a future phase. The app is the production-mobile evolution of academic research presented at ConBAP, which benchmarked the SqueezeNet architecture against manual feature extraction methods (FFT, Gabor, LBP) for soil texture classification.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Android + iOS) |
| Language | Dart 3.10+ |
| State management | Riverpod 3.3.1 |
| Navigation | GoRouter 17.1.0 |
| Camera / Gallery | image_picker 1.2.1 |
| GPS | geolocator 14.0.2 |
| Reverse geocoding | geocoding 4.0.0 |
| Local persistence | Hive 2.2.3 + hive_flutter 1.1.0 |
| AI classification | TensorFlow Lite *(planned — Phase 2)* |

## Getting Started

### Prerequisites

- Flutter SDK 3.x
- Android Studio with an Android emulator, or a connected device
- Xcode (for iOS builds)

### Installation

```bash
# Clone the repository
git clone https://github.com/com.visiosoil/visiosoil-app.git
cd visiosoil-app

# Install dependencies
flutter pub get

# Generate Hive adapters (if needed)
flutter pub run build_runner build
```

### Running

```bash
# Run on a connected emulator or device
flutter run
```

## Project Structure

```
lib/
├── main.dart                        # App entry point (ProviderScope + MaterialApp.router)
├── models/
│   └── soil_record.dart             # SoilRecord model with Hive adapter
├── providers/
│   └── image_provider.dart          # Riverpod provider for captured image state
└── core/
    ├── constants/
    │   └── storage_keys.dart        # Hive box names and storage constants
    ├── theme/
    │   ├── app_theme.dart           # ThemeData configuration
    │   ├── app_colors.dart          # Material Design 3 color palette
    │   ├── app_spacing.dart         # Spacing constants
    │   └── app_typography.dart      # Typography scale
    ├── routes/
    │   └── app_router.dart          # GoRouter configuration
    ├── utils/
    │   ├── location_service.dart    # GPS capture and reverse geocoding
    │   └── formatters.dart          # Date/time and coordinate formatters
    ├── widgets/
    │   ├── visio_app_bar.dart       # Shared AppBar
    │   ├── visio_button.dart        # Primary/secondary button variants
    │   ├── visio_card.dart          # Card wrapper component
    │   ├── loading_indicator.dart   # Styled loading spinner
    │   └── empty_state.dart         # Empty state placeholder
    └── features/
        ├── home/
        │   └── home_page.dart       # Dashboard with last capture card
        ├── capture/
        │   └── capture_screen.dart  # Camera + GPS capture with location options
        ├── history/
        │   └── history_screen.dart  # Grid archive with multi-select delete
        ├── preview/
        │   └── image_preview_screen.dart  # Full image viewer with info panel
        ├── details/
        │   └── details.dart         # Record detail view with delete
        └── main/
            └── main_screen.dart     # Tab host with NavigationBar (MD3)
```

## Features

### Capture Flow
- **Camera capture**: Takes photo and automatically records GPS location
- **Gallery import**: Select existing photos with manual or GPS-based location
- **Location options**: Toggle between current GPS or manual address entry

### History & Management
- **Grid view**: Thumbnails with timestamp overlay
- **Multi-select**: Long press to enter selection mode
- **Bulk delete**: Delete multiple records at once
- **Preview**: Full-screen image viewer with zoom/pan

### Data Persistence
- **Hive storage**: Local database for soil records
- **SoilRecord model**: Image path, coordinates, address, timestamp

## Current Status

**Status: v1.0.0 — Phase 1 complete**

### Done (v1.0.0)

- [x] Material Design 3 theme system (`AppTheme`, `AppColors`, `AppSpacing`)
- [x] Riverpod state management
- [x] GoRouter navigation (5 routes)
- [x] `NavigationBar` (MD3) with Home / History tabs
- [x] Home screen with last capture card
- [x] Capture screen with camera and gallery options
- [x] Location handling (auto GPS for camera, manual option for gallery)
- [x] History screen with grid layout
- [x] Multi-select deletion mode
- [x] Image preview screen with info panel
- [x] Details screen with record information
- [x] Real camera integration (`image_picker`)
- [x] Real GPS integration (`geolocator` + `geocoding`)
- [x] Local persistence (`Hive`)
- [x] `SoilRecord` data model with computed properties
- [x] Clean Code refactoring (DRY, SRP, centralized formatters)

### Pending (Phase 2)

- [ ] On-device soil classification (TensorFlow Lite)
- [ ] Classification results display
- [ ] Export/share functionality
- [ ] History filters and search
- [ ] Dark mode support

## Architecture

The app follows Clean Code principles:

- **Centralized constants**: `StorageKeys` for Hive box names
- **Centralized formatters**: `Formatters` class for date/time and coordinates
- **Model enrichment**: `SoilRecord` with computed getters (`hasCoordinates`, `formattedTimestamp`, etc.)
- **Small, focused widgets**: Each widget does one thing well
- **Consistent naming**: Intention-revealing names throughout

## License

This project is proprietary software developed for VisioSoil.
