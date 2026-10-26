# SPEC: fix(home): match Início in Modo Sol to PNG 25

## Problem

The Developer asked on 2026-10-26 for "100% de fidelidade ao mock" ("100% fidelity to the mock"). Rendering Início in Modo Sol and comparing every line of ink with PNG 25 leaves four gaps. The first two push everything below them 15 dp down.

- **Stat labels.** "análises", "coleção" and "última confiança" take Modo Sol's enlarged `bodySmall`, 14 sp. PNG 25 keeps the light theme's 12 sp, so its cards are 8 dp shorter.
- **Recent rows.** The class takes Modo Sol's `titleMedium`, 17/24, so a row repeats every 66 dp. PNG 25 keeps light mode's 16/22, and its rows repeat every 64 dp, as PNG 08's do.
- **"Ver todas"** is drawn at Modo Sol's 17 sp `labelLarge` in `primaryText`. PNG 25 draws it at 14 sp in ink.
- **Navigation.** The selected label is `primary`. PNG 25 draws every label in ink.

PNG 36 keeps Modo Sol's enlarged subtitles in Configurações, so the fix is per widget, not a change to Modo Sol's type scale.

## Design Decision

Each value below is read from the 2× PNG 25, 2 px to the dp.

- **`StatCell`'s label** is `bodySmall` at 12/16 in every theme, so the light theme does not change.
- **`AnalysisTile`'s class on Início** (`showSyncStatus`) is `titleMedium` at 16/22 in every theme. The light theme's is already 16/22.
- **Início's "Ver todas"**:
  - 14 sp, in `onSurface` in Modo Sol and in `primaryText` otherwise;
  - 48 dp tall in every theme. That is Material's least target, and PNG 25 lays the row out at it; Modo Sol's 56 dp would push "Recentes" 4 dp down and the list 8 dp.
- **Modo Sol's navigation bar** draws the selected label in `onSurface` at weight 700. The black indicator behind the icon still marks the selection.

## Alternatives Considered

- **Drop Modo Sol's `bodySmall` and `titleMedium` to the light sizes for the whole app.** Rejected: PNG 36 draws Configurações' subtitles enlarged, so the mocks do not scale every style the same way.

## Scope

- Includes:
  - `StatCell`'s label style, `AnalysisTile`'s class style on Início, and Início's "Ver todas";
  - Modo Sol's navigation label colour;
  - their tests.
- Does NOT include:
  - the home's background contours, a separate gap in every theme;
  - the rows' photographs and names, which are data.

## Acceptance Criteria

- `sun_home_matches_the_mock`, in Modo Sol:
  - a stat label is 12 sp;
  - a recent row's class is 16 sp, and the row is 63 dp tall;
  - "Ver todas" is 14 sp in `onSurface`, and 48 dp tall;
  - the selected navigation label is `onSurface`.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- Perfil's stat cards share `StatCell`. In Modo Sol their labels become 12 sp too, as PNG 25's are. No Modo Sol mock of Perfil says otherwise.
