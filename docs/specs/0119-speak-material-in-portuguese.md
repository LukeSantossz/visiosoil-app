# SPEC: fix(l10n): give Flutter's built-in widgets their pt-BR strings

## Problem

The app's own copy is pt-BR, but it registers no `flutter_localizations`, so every string Flutter's built-in widgets supply on their own reads in English.

On `main` today, `MaterialApp.router` in `lib/main.dart` sets no `localizationsDelegates`, `supportedLocales` or `locale`. Flutter then falls back to `DefaultMaterialLocalizations`, which is US English. SPEC 0118 found this through details' back tooltip, which read "Back". The same fallback reaches:

- **The history search field's text-selection toolbar:** "Cut", "Copy", "Paste" and "Select all".
- **The screen-reader label of a dialog's barrier**, "Dismiss", on the two `showDialog` confirmations.
- **Any default tooltip or semantic label** a Material widget supplies itself, such as a `BackButton`'s.

SPEC 0118 worked around the back tooltip with the literal "Voltar" and left registering the localizations as out of scope. This spec registers them.

## Design Decision

**Register Flutter's global localizations and fix the app's locale to pt-BR.** `MaterialApp.router` gets three arguments:

| Argument | Value |
| --- | --- |
| `localizationsDelegates` | `GlobalMaterialLocalizations.delegates`, which covers Material, Cupertino and Widgets |
| `supportedLocales` | `[Locale('pt', 'BR')]` |
| `locale` | `Locale('pt', 'BR')` |

**`flutter_localizations` is added from the SDK** in `pubspec.yaml` (`sdk: flutter`). It ships with Flutter 3.44.1, so no pub package is downloaded, and `pubspec.lock` records it pinned to the SDK.

**The locale is fixed, not read from the device.** Every string the app writes itself is pt-BR, and `AppStrings` has no other language. If the locale followed the device, a phone set to English would get English Material strings beside pt-BR app copy, which is the mixed screen this spec exists to end.

**SPEC 0118's literal "Voltar" tooltips stay.** Material's pt string for the back button is also "Voltar", so the two agree, and changing them is not needed to fix the defect.

## Alternatives Considered

- **Follow the device locale, with pt-BR listed first.** Rejected: the app has no English copy, so it would mix languages on any phone not set to Portuguese. Adding English copy is a translation project, not this fix.
- **Override only the strings seen so far, with a custom `MaterialLocalizations`.** Rejected: it would have to be found and extended string by string, and the next widget the app adopts would bring its English default back. The SDK already ships the full pt set.
- **Keep replacing defaults with literals at each call site, as SPEC 0118 did.** Rejected: the toolbar and the barrier label have no call site in the app to put a literal on.

## Scope

- Includes:
  - `pubspec.yaml` and `pubspec.lock`: `flutter_localizations` from the SDK.
  - `lib/main.dart`: the three `MaterialApp.router` arguments.
  - `test/app_locale_test.dart`: the tests below.
- Does NOT include:
  - iOS `Info.plist` localization keys (`CFBundleLocalizations`, `CFBundleDevelopmentRegion`). They govern strings iOS draws itself, such as the permission dialogs, not the Flutter-drawn widgets this spec fixes.
  - Android resource locales.
  - Changing any app copy, `AppStrings`, or SPEC 0118's literal tooltips.
  - Date and number formatting through `intl`. The app formats them by hand in `Formatters`.
  - Any second language.

## Acceptance Criteria

- `material_strings_are_portuguese`: inside the app, `MaterialLocalizations` gives "Voltar" for the back button tooltip, "Colar" for paste, and "Dispensar" for a modal barrier.
- `cupertino_strings_are_portuguese`: inside the app, `CupertinoLocalizations` gives "Colar" for paste, so the iOS text-selection toolbar matches.
- `locale_ignores_the_device`: with the device locale set to `en_US`, the app's locale is still `pt_BR`.
- The existing tests pass unchanged.

## Reproducibility

`flutter test test/app_locale_test.dart`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Pumping `VisioSoilApp` now loads the pt localizations. They are synchronous `SynchronousFuture` delegates, so no existing test needs an extra pump. "The existing tests pass unchanged" checks this.
- The pt strings come from Flutter's own translation, whose pt set is Brazilian Portuguese. This spec does not review their wording.
- A tester or developer whose phone is set to another language will still see pt-BR. That is intended.
