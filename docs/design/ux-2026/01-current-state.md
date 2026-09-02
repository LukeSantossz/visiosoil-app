# Current State — Stack, Inventory, Screen-by-Screen Audit

## 1. Stack

| Concern | Implementation |
| --- | --- |
| Framework | Flutter 3.44.1 / Dart 3.12.1, pinned to CI |
| State | `flutter_riverpod` 3.3.1, no codegen. 22 providers across 11 files |
| Navigation | `go_router` 17.1, seven routes plus `errorBuilder` |
| Persistence | Drift 2.20 + SQLite, schema v4, repository pattern |
| Inference | `tflite_flutter` 0.12 in a spawned `Isolate` |
| Camera | `image_picker` 1.2 — delegates to the OS camera application |
| Location | `geolocator` 14 + `geocoding` 4 |
| Connectivity | `connectivity_plus` 6.1 |
| Auth | `google_sign_in` 6.2 behind `AuthService`, tokens in `flutter_secure_storage` |
| Theme | Hand-rolled token layer under `lib/core/theme/`, Material 3 |
| Fonts | Manrope 700/800 (display), Inter 400/500/600 (body), bundled |
| Icons | Flutter built-in `Icons.*` (Material Icons) |
| Tests | 62 test files |

There is no animation library, no gesture library beyond the SDK, no haptics
usage, no chart library, and no accessibility package. Every one of those is a
deliberate observation, not an omission from this table.

## 2. Token layer

| File | Contents |
| --- | --- |
| `app_colors.dart` | Full Material 3 `ColorScheme` (light only), warning trio, four named shadow colours, five soil-scale colours |
| `app_typography.dart` | Three headlines, three titles (Manrope); three body, three label (Inter) |
| `app_spacing.dart` | `4 / 8 / 12 / 16 / 24 / 32 / 48` |
| `app_radius.dart` | `8 / 12 / 16 / 24 / 999`, plus prebuilt `BorderRadius` |
| `app_motion.dart` | Durations `90 / 140 / 220 / 380 / 640`, three curves |
| `soil_texture_colors.dart` | Class name → colour map |
| `app_theme.dart` | `AppTheme.light` only |

`AppMotion` exists and is referenced in exactly three places: the onboarding
page transition, the splash entrance, and the history thumbnail crossfade.
Everything else in the app changes state without any transition at all.

`AppTheme.light` is the only theme. `main.dart` passes no `darkTheme` and no
`themeMode`.

## 3. Screen inventory

| Route | Screen | File | Lines | State |
| --- | --- | --- | --- | --- |
| `/splash` | `SplashScreen` | `features/splash/` | 182 | Stateful, animation controller |
| `/onboarding` | `OnboardingScreen` | `features/onboarding/` | 237 | Stateful, `PageView`, three steps |
| `/` | `MainScreen` | `features/main/` | 51 | Consumer, `IndexedStack` over two tabs |
| (tab 0) | `HomeScreen` | `features/home/` | 55 | Consumer, four child widgets |
| (tab 1) | `HistoryScreen` | `features/history/` | 177 | Stateful, selection mode, debounce |
| `/capture` | `CaptureScreen` | `features/capture/` | 370 | Stateful, `CaptureUiState`, four injected seams |
| `/details` | `DetailsScreen` | `features/details/` | 262 | Consumer, `CustomScrollView` |
| `/preview` | `ImagePreviewScreen` | `features/preview/` | 364 | Consumer, `InteractiveViewer` |
| `/settings` | `SettingsScreen` | `features/settings/` | 274 | Consumer, `ListView` |
| (fallback) | `RouteErrorView` | `core/widgets/` | — | Rendered by `errorBuilder` |

## 4. Component inventory

### Shared (`lib/core/widgets/`)

| Component | Used by | Notes |
| --- | --- | --- |
| `VisioButton` | capture, details, history empty, tips | Three variants. Loading state replaces content with a spinner |
| `VisioAppBar` | **capture only** | History, details, settings and preview each build a raw `AppBar` |
| `EmptyState` | history, tips | Icon, title, description, optional action |
| `ErrorState` | history, details, tips | Icon, message, optional retry |
| `LoadingIndicator` | capture chip, details, tips | Wraps `CircularProgressIndicator` |
| `PermissionDeniedView` | camera denial | Icon, title, description, settings or retry |
| `RouteErrorView` | router fallback | — |
| `confirmDestructiveAction` | details, history, settings | Shared confirmation dialog |
| `VisioSoilLogo` | splash | The only widget in the app carrying `Semantics` |

### Feature-local, not shared

| Widget | Where | Duplication |
| --- | --- | --- |
| `_ConfidenceBadge` | `details/widgets/classification_header.dart` | Near-duplicate of `_ConfidenceChip` on home |
| `_ConfidenceChip` | `home/widgets/last_analysis_section.dart` | Near-duplicate of the above |
| `_ConfidenceBanner` | `classification_header.dart` | Private; the design system publishes this as a component |
| `_InfoRow` | `details/widgets/info_section.dart` | Duplicated in preview |
| `_InfoRow` | `preview/image_preview_screen.dart` | Duplicate of the above |
| `_CircleIconButton` | `preview/` | The design system publishes `IconButton`; this is bespoke |
| `_CaptureButton` | `home/widgets/hero_capture_card.dart` | Reimplements a button outside `VisioButton` because no variant renders white-on-primary |
| `_InfoChip` | `capture/widgets/capture_image_preview.dart` | Overlay chip, no shared equivalent |
| `_StatCard` | `home/widgets/stats_grid.dart` | The design system publishes `StatCard` |
| `_FilterChip` | `history/widgets/history_filter_bar.dart` | The design system publishes `Chip` |
| `_ThumbnailCard` | `history/widgets/history_grid.dart` | — |
| `_SettingsTile`, `_SectionHeader` | `settings/` | — |
| `_TipCard`, `_CitationChip`, `_SourcesList`, `_SourceTile`, `_DisclaimerBanner` | `details/management_tips_section.dart` | — |

Twenty-one feature-local widgets against nine shared ones. Five of the local
ones have a published design-system counterpart.

## 5. Screen-by-screen audit

### Splash

Logo fades and scales in over 640 ms. After a fixed 1200 ms delay it requests
camera permission, then location permission, then reads the onboarding flag and
routes.

- Permissions are requested cold, before the user has seen a single screen of
  product. Nothing explains why either is wanted.
- Location is optional to the product but is requested with the same weight as
  camera.
- The status line cycles through "Solicitando permissões...", "Permissão de
  câmera...", "Permissão de localização...", "Iniciando..." — narration of the
  system's internals, not of the user's goal.
- A permanent denial here is unrecoverable inside the app.

### Onboarding

Three steps in a `PageView`: framing, lighting, angle. Progress bar, skip,
next. Marks a flag and leaves.

- Shown on first launch, which is the moment the user has the least intent to
  photograph anything. The content is capture technique delivered before there
  is any capture in view.
- Afterwards it is reachable only from Settings → "Como capturar bem".
- The step content diverges from the design system's `CaptureGuideScreen`,
  which specifies four steps including surface cleaning and adds an "Evite"
  section.
- The illustration is a coloured circle with a Material icon in it, on all
  three steps.

### Home

Greeting row with a settings avatar, green hero capture card, three-up stats,
last-analysis section. A single inline error card replaces stats plus
last-analysis when the records stream fails.

- Aligned to the design system mockup by spec 0029; the closest thing to a
  finished screen in the app.
- `_RecordRow` is a `GestureDetector`: no ink response, no semantics, no
  minimum target size.
- The greeting is the static label "Agrônomo" — deliberate, per spec 0029.
- `SizedBox(height: 100)` as bottom-nav padding is a hard-coded magic number.
- The confidence chip renders "44% · Baixa" — a bare percentage carrying no
  context about what it means for a four-class problem, where chance is 25 %.

### Capture

Before a photo exists: a grey placeholder reading "Selecione uma imagem" and a
single "Câmera" button. After: the photo with two overlay chips (location,
classification) and Save / Discard.

- The placeholder copy promises image selection in an application that is
  camera-only by design. This is the clearest copy defect in the app.
- The screen is a waiting room. The user tapped "Nova análise" on home to reach
  a screen whose only function is another button that opens the camera.
- Feedback for a fifteen-second inference is a 14 px spinner inside a chip.
- `isBusy` is `isLocating || isClassifying || isSaving`. Save is therefore
  disabled for up to twenty seconds waiting on reverse geocoding, even though
  location is optional and the classification may already be done.
- The classification failure chip reads "Classificação falhou · tocar para
  repetir". With no model artifact in the repository, `classify()` can only
  return null, so the retry it offers can never succeed.
- Chip text is white `labelSmall` over an arbitrary photograph with a
  black-at-55% pill behind it. Contrast is plausible but unverified.

### Details

Sliver hero image, classification header, info section, management tips,
share and delete.

- The confidence banner appears only for low and moderate. High confidence gets
  no statement of limits at all.
- Low confidence uses `errorContainer` — red for a model limitation.
- `ConfidenceLevel.fromScore(null)` returns `low`, so an unclassified record and
  a badly classified one collapse into the same visual state.
- Share opens a location-disclosure dialog, which is correct and well done.
- Delete sits directly below Share in the same stretched column, sixteen pixels
  apart.

### Preview

Full-screen black, `InteractiveViewer`, back and info circle buttons, bottom
info panel with a drag handle.

- The drag handle implies a draggable sheet. The panel does not move.
- Reached from history; its info button pushes `/details`, which shows the same
  timestamp and location plus the classification. Two screens, one entity.
- Both circle icon buttons are unlabelled.

### History

Search field, texture filter chips, two-column grid of thumbnails, long-press
selection mode with bulk delete.

- Cards show only the timestamp. Texture class and confidence, the two things a
  user would scan for, are absent from the grid.
- Selection mode is discoverable only by long press, with no affordance.
- Results are capped at 150 with no indication that a cap was applied.
- Thumbnails carry no semantic label.

### Settings

Account, version, help, delete-all.

- Auth failures surface as a one-off snackbar; well guarded.
- "Apagar todos os dados" is a red list tile in the same visual family as every
  other tile.

## 6. Cross-cutting observations

**Error presentation appears in five distinct forms:** `ErrorState`,
`HomeDataError`, `_DetailsErrorView`, `_PreviewErrorView`, and
`_RecordNotFoundView`. Two of them are black-canvas variants that exist only
because the preview has a black background.

**Loading appears in four forms:** `LoadingIndicator`, and raw
`CircularProgressIndicator` in the preview loader, the settings version tile,
and the settings account tile.

**Accessibility instrumentation is two widgets.** A repository-wide search for
`Semantics`, `semanticLabel`, `MergeSemantics`, `excludeSemantics` and
`tooltip:` returns `visio_soil_logo.dart` and, since spec 0029, the home
settings avatar in `home_greeting.dart`. Nothing else.

**`MediaQuery` is consulted once**, for device pixel ratio in the details hero.
Text scale and animation preferences are never read.

**`HapticFeedback` is never called.**

**`SoilTextureColors.all` documents itself as "model output order" and orders
Siltosa before Media**, contradicting `InferenceService._textureLabels`. The
getter has no consumers, so it is a latent trap rather than a live defect.
