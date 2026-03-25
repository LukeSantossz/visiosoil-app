![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)
![Status](https://img.shields.io/badge/status-in%20development-yellow)

# VisioSoil — Soil Analysis Mobile App

> Cross-platform mobile app for geolocated soil texture analysis, built with Flutter.

## Overview

VisioSoil lets agronomists and field professionals photograph soil samples, record GPS coordinates, and review captured data — with on-device AI classification planned for a future phase. The app is the production-mobile evolution of academic research presented at ConBAP, which benchmarked the SqueezeNet architecture against manual feature extraction methods (FFT, Gabor, LBP) for soil texture classification.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (Android + iOS) |
| Language | Dart |
| State management | Riverpod |
| Navigation | GoRouter |
| Typography | google_fonts |
| Image loading | cached_network_image |
| Camera / Gallery | image_picker *(planned — Phase 1)* |
| GPS | geolocator *(planned — Phase 1)* |
| Reverse geocoding | geocoding *(planned — Phase 1)* |
| Local persistence | Hive *(planned — Phase 1)* |
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
```

### Running

```bash
# Run on a connected emulator or device
flutter run
```

## Project Structure

```
lib/
├── main.dart                     # App entry point (ProviderScope + MaterialApp.router)
├── core/
│   ├── theme/
│   │   └── app_theme.dart        # ThemeData, AppColors
│   ├── routes/
│   │   └── app_router.dart       # GoRouter configuration
│   ├── widgets/
│   │   ├── visio_app_bar.dart    # Shared AppBar
│   │   └── custom_bottom_nav.dart
│   ├── models/
│   │   └── soil_record.dart      # SoilRecord, GpsCoordinates, SoilComposition, BiologicalIndicators
│   └── features/
│       ├── home/
│       │   └── home_page.dart    # Dashboard screen
│       ├── capture/
│       │   └── capture_screen.dart  # Camera + GPS capture screen
│       ├── history/
│       │   └── history_screen.dart  # Archive list with filters
│       ├── details/
│       │   └── details_screen.dart  # Individual record detail view
│       └── main/
│           └── main_screen.dart  # Tab host with BottomNavigationBar
└── providers/
    └── soil_providers.dart       # Riverpod providers (records, capture state, filters)
```

## Current Status

**Status: In development — Phase 1 (mobile foundation)**

| Feature | Status |
|---------|--------|
| Custom theme (`AppTheme`, `AppColors`) | Done ✅ |
| `SoilRecord` data model | Done ✅ |
| Riverpod state management | Done ✅ |
| GoRouter navigation (3 tabs + details) | Done ✅ |
| `BottomNavigationBar` (Home / Capture / History) | Done ✅ |
| Home screen — field health dashboard + AI insight + map + recent list | Done ✅ |
| Capture screen — viewfinder UI + GPS display + composition panel + capture button | Done ✅ |
| History screen — archive list with filter chips and search bar | Done ✅ |
| Details screen — individual record view | Done ✅ |
| Real camera integration (`image_picker`) | Pending ⏳ |
| Real GPS integration (`geolocator` + `geocoding`) | Pending ⏳ |
| Local persistence (`Hive`) | Pending ⏳ |
| Android + iOS permission handling | Pending ⏳ |
| On-device soil classification (TensorFlow Lite) | Pending ⏳ *(Phase 2)* |

## Known Issues

- **GPS**: coordinates shown in the Capture screen are hardcoded mock values — real `geolocator` integration is not yet connected.
- **Camera**: the viewfinder uses a static placeholder image — real `image_picker` integration is pending.
- **Persistence**: the capture button saves records to in-memory Riverpod state only; data does not survive app restarts (`Hive` integration pending).
- **Records**: all soil records on the Home and History screens are mock data seeded in the provider's initial state.
