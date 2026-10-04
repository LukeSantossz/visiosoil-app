# SPEC: fix(a11y): give the settings avatar a 48 dp target, and hold every screen to the guidelines

## Problem

The accessibility criteria ask that every screen pass Flutter's four accessibility guidelines (`docs/design/ux-2026/12-accessibility.md` §4 and §5):
- `tap_targets_meet_guideline`: `androidTapTargetGuideline`, 48 dp, and `iOSTapTargetGuideline`, 44 dp;
- `no_unlabelled_icon_button`: `labeledTapTargetGuideline`;
- `text_contrast_meets_guideline`: `textContrastGuideline`.

SPEC 0118 applied two of them to the surfaces it changed: the history grid, the home's record row and the preview. No test holds a whole screen to all four, so a later change can bring back a small or unlabelled target unnoticed.

A probe run all four guidelines on every screen, in the app's light and dark themes. Only one check failed: the home's settings avatar is a 40 × 40 dp target, in both themes and against both tap-target guidelines. `_SettingsAvatar` in `home_greeting.dart` sizes its `InkWell` to the drawn 40 dp circle.

## Design Decision

**The avatar's target grows to 48 dp, and its circle stays 40 dp.** `_SettingsAvatar` puts the 40 dp circle in the centre of a 48 × 48 dp box. The tap and the semantics node cover the box.

The ink becomes an `InkResponse` with a 20 dp radius, so the ripple still fills the drawn circle and not the larger box. A Material icon button does the same: its visual sits inside a larger target. The circle moves 4 dp in from the right edge and 4 dp down, which is half the extra size on each side.

**Each screen's test file gains one guideline test, in both themes.** A helper in `test/support/guidelines.dart`, `expectMeetsGuidelines(tester)`, runs the four guidelines on the screen in view. Each screen's existing harness gains an optional `theme`. It defaults to none, so the file's other tests are unchanged, and the guideline test passes `AppTheme.light` and then `AppTheme.dark`.

The states covered are the ones that show different controls:

| Screen | States | Test file |
| --- | --- | --- |
| Splash | Its first second | `splash/splash_screen_test.dart` |
| Onboarding | The first step | `onboarding/onboarding_screen_test.dart` |
| Main | The home tab, then the history tab | `home/home_navigation_test.dart` |
| History | A record, then selection mode | `history/history_screen_test.dart` |
| Details | The top, then scrolled to the actions | `details/details_screen_test.dart` |
| Preview | The photograph | `preview/image_preview_screen_test.dart` |
| Settings | Signed in at the top and at the bottom, then signed out | `settings/settings_screen_test.dart` |
| Capture | Before a photograph, then with a result | `capture/capture_screen_test.dart` |

## Alternatives Considered

- **A 48 dp drawn circle.** Rejected: the design system draws the avatar at 40 dp, and the guideline asks for a target, not a bigger drawing.
- **One new test file that builds every screen itself.** Rejected: it would copy the private fakes of five test files, such as the settings screen's auth service and the capture screen's inference. Each harness already builds its screen.
- **Run the guidelines on every test of every file.** Rejected: most tests drive a state change, not a layout, and the four guidelines add a screenshot and a full semantics walk to each one.
- **The high-contrast themes too.** Rejected for this slice: they differ from light and dark only in card borders (SPEC 0130), which none of the four guidelines reads.

## Scope

- Includes:
  - `lib/core/features/home/widgets/home_greeting.dart`: `_SettingsAvatar`'s target and ink.
  - `test/support/guidelines.dart`: the helper.
  - The eight test files in the table: an optional `theme` on the harness, and the guideline test.
  - `test/features/home/home_widgets_test.dart`: the avatar test below.
- Does NOT include:
  - Any other screen change. The probe found none needed.
  - A manual TalkBack pass. The avatar keeps its label, and only its target grows.
  - Text scaling, motion, and focus order: SPEC 0121, SPEC 0120, and §3.7, respectively.

## Acceptance Criteria

- `settings_avatar_target`: the home's settings avatar is a button labelled "Configurações", with a 48 × 48 dp semantics node. Its circle is still drawn at 40 dp.
- `screens_meet_guidelines`: each screen in the table, in each listed state, passes all four guidelines in `AppTheme.light` and in `AppTheme.dark`.
- The existing tests pass unchanged, including SPEC 0118's guideline checks.

## Reproducibility

`flutter test test/features/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- No harness shows a real photograph: a record's image is a missing file, drawn as the broken-image fallback. Text over a real photograph is held by SPEC 0107's scrim test, not by `textContrastGuideline` here.
- The guidelines see the screen as the harness builds it. A screen state no harness shows, such as an error view, is outside these tests. The probe's states cover each screen's controls.
- The avatar's circle moves 4 dp, which changes the greeting row's height from 40 dp to 48 dp only if the greeting text is shorter than 48 dp. It is not: the two lines measure more than 48 dp.
