# SPEC: feat(profile): match Perfil and Configurações to the redesign mocks

## Problem

The Developer asked on 2026-10-26 that every screen follow the redesign v11 mocks (`docs/design/spec/telas/`) "fielmente e estritamente" ("faithfully and strictly"). SPEC 0201 to 0203 matched the shared chrome, the result screens, Home and the history. Perfil (PNG 21, 22) and Configurações (PNG 23, 24, 35, 36) still differ:

- **Cards.** Both screens draw Material cards with a shadow and a border. The mocks draw flat `surface` cards: radius 24 for the account card, 16 for every list.
- **Rows.**
  - The rows use Material icons at 24 dp, 16 sp titles and chevrons in `onSurfaceVariant`.
  - The mocks draw 22 dp Lucide icons in `primaryText` and 15 sp titles over 13 sp lines, with a 20 dp chevron in `textTertiary`.
  - Settings rows have no icon for Vibração and Tema.
- **Account card.**
  - The body copy is 16 sp.
  - "N análises e M classes" has no icon.
  - The Google button is a 14 sp app-coloured outlined button.
  - The mock sets 14 sp copy and a device line with a 20 dp phone icon. Its Google button carries Google's own colours: a white fill, a #747775 rule and #1F1F1F text at 17 sp.
- **Tema.**
  - The choice sits on a full-width segmented control under its own title.
  - The mock puts a compact 32 dp control at the end of the row, after a moon icon.
  - Both segmented controls lack the rule the mocks draw between segments.
- **Section labels.** They are 12 sp weight 800 in `onSurfaceVariant`. The mock's are weight 600 in `textTertiary`, tracked 0.6, 16 dp in from the card's edge, with 24 dp above and 8 dp below.
- **Margins.** Both screens sit 20 dp from the edge. The mocks put cards at 16 dp, and the Perfil title at 20 dp.

## Design Decision

The values below are measured on the 2× PNGs, as in SPEC 0203.

- **`SettingsTile` and `SettingsGroup`** (`lib/core/widgets/settings_tile.dart`). They replace Configurações' private `_SettingsTile` and `_SettingsGroup`, and Perfil's `ListTile`s.
  - A row is at least 56 dp tall, with 16 dp horizontal and 8 dp vertical padding.
  - It holds a 22 dp icon in `primaryText`, or `error` when destructive, then the text 12 dp after.
  - The title is 15 sp weight 500 in `onSurface`, with a 20 dp line.
  - The line under it is 13 sp in `onSurfaceVariant`, with an 18 dp line.
  - A tappable row without a trailing widget ends in a 20 dp Lucide `chevronRight` in `textTertiary`.
  - The group is a `surface` card with radius 16, rows separated by full-width `divider` rules, and no border or shadow outside Modo Sol.
  - `SettingsSwitchTile` takes the same metrics.
- **`SegmentedControl`.**
  - A rule in `outline` at `edgeWidth` separates the segments, as PNG 16 and 23 draw it.
  - A new `compact` mode draws a 32 dp pill sized to its labels, each segment 12 dp either side of its label, the widest label setting every segment's width. Its hit area reaches 8 dp above and below the pill, keeping the 48 dp target.
- **Configurações.**
  - The list keeps 16 dp margins.
  - Section labels are 12 sp weight 600 in `textTertiary`, tracked 0.6, 16 dp in from the list's edge. They have 24 dp above, none above the first, and 8 dp below.
  - Each row takes a Lucide icon:

    | Row | Icon |
    |---|---|
    | Conta | `user` (`cloud` once linked) |
    | Tema | `moon` |
    | Modo Sol | `sun` |
    | Vibração | `smartphone` |
    | Unidades | `ruler` |
    | Idioma | `languages` |
    | Guia de enquadramento | `scanEye` |
    | Salvar fotos na galeria | `image` |
    | Registrar localização | `mapPin` |
    | Backup na conta | `cloudUpload` |
    | Sincronizar só no Wi-Fi | `wifi` |
    | Exportar análises | `download` |
    | Limpar dados do aparelho | `trash2` |
    | Reduzir movimento | `zap` |
    | Tamanho do texto | `aLargeSmall` |
    | Como fotografar a amostra | `circleHelp` |
    | Privacidade e dados | `shield` |
    | Enviar comentário | `messageSquare` |
    | Versão | `info` |
    | Excluir conta | `userX` |

  - Tema is one row whose end holds the compact Sistema | Claro | Escuro control. §2 keeps Sistema, which the mock leaves out.
  - Tamanho do texto takes the same row form.
- **Perfil.**
  - The title is 20 dp in, its line 12 dp below the safe area, and the account card 16 dp under it. Cards sit at 16 dp margins.
  - **Account card** (`AccountCard`, shared with the onboarding).
    - The card is on `surface`, radius 24, with 20 dp padding.
    - Avatar. When unlinked, it is a 56 dp circle of `surfaceContainer` at 50 % holding a 28 dp Lucide `user` in `onSurfaceVariant`. When linked, it holds the initials on `primaryContainer`.
    - The title is 18 sp weight 600, 14 dp after the avatar, over a 14 sp line in `onSurfaceVariant`.
    - Perfil's copy below is 14/20 in `onSurfaceVariant`, 14 dp under the header.
    - Then, 12 dp lower, a 20 dp Lucide `smartphone` in `primaryText`, then the count line at 13/18, 8 dp after it.
    - Then the Google button, 16 dp lower.
    - When linked, the sync row keeps its honest copy, "Dados só neste aparelho" and a disabled "Sincronizar", behind a Lucide `cloud`.
  - **`GoogleSignInButton`** (shared with the onboarding). It follows Google's brand button:
    - a 48 dp pill;
    - a white fill with a #747775 1 dp rule, or Google's dark variant #131314 with #8E918F in the dark theme;
    - "Continuar com o Google" at 17 sp weight 500 in #1F1F1F (#E3E3E3 dark), 12 dp after the 24 dp logo;
    - Modo Sol keeps white with a 2 dp black rule.
  - "Neste aparelho" is placed and set as Home's section titles.
  - The stats use Lucide `scan`, `layers`, and `hardDriveDownload` (`cloudCheck` once linked).
  - The collection counts the twelve USDA reference classes, as Home and the history count them (SPEC 0203). The sentence's class count keeps counting the classes the records hold.
  - The links card follows `SettingsGroup`, 24 dp under the stats.

## Alternatives Considered

- **Drop Sistema from Tema, as the PNG does.** Rejected: the design spec's §2 and decision 23 keep Sistema, and dropping it would remove a working preference. The control keeps three options in the mock's compact form.
- **Size compact segments to their own labels.** Rejected for now: the sliding indicator would need each segment's measured offset. Equal widths, set by the widest label, differ from the mock by a few dp.

## Scope

- Includes:
  - `ProfileScreen`, `SettingsScreen`, `AccountCard` and `GoogleSignInButton`;
  - `SettingsSwitchTile`, and the new `SettingsTile` and `SettingsGroup`;
  - `SegmentedControl`'s separator and compact mode.
- Does NOT include:
  - The Dicas tab, which follows in its own change.
  - The export sheet's content (PNG 24), which already matches its copy.
  - Settings that have no implementation behind them; they keep their current enabled or disabled state.

## Acceptance Criteria

- `settings_rows_match_the_mock`:
  - a `SettingsTile` row is 56 dp tall;
  - its icon is 22 dp in `primaryText`;
  - its title is 15 sp weight 500;
  - its line is 13 sp;
  - its chevron is Lucide `chevronRight` in `textTertiary`.
- `settings_groups_are_flat`: a `SettingsGroup` draws `surface` with radius 16 and no shadow or border, and Modo Sol draws a border.
- `section_labels_match_the_mock`: the section label is 12 sp weight 600 in `textTertiary`, tracked 0.6.
- `theme_row_holds_a_compact_control`:
  - the Tema row shows `LucideIcons.moon`, "Tema", and a 32 dp segmented pill on the same line;
  - choosing "Escuro" stores the dark theme.
- `segments_are_separated`: a segmented control of two options draws one separator rule.
- `profile_account_card_matches_the_mock`:
  - the unlinked card has radius 24;
  - its avatar is 56 dp with a 28 dp Lucide `user`;
  - the count line sits beside a Lucide `smartphone`.
- `google_button_wears_google_colours`:
  - in the light theme the button fills white, with a #747775 side and #1F1F1F 17 sp text;
  - it is 48 dp tall.
- `profile_collection_counts_reference_classes`: with records of "Argila" and "Argilosa", the collection stat reads "1/12".
- `profile_links_use_the_settings_row`: Perfil's links are `SettingsTile`s inside a `SettingsGroup`.
- Existing tests pass. They are updated only where they pinned the old icons, sizes, `ListTile`s, `Card`s or the full-width Tema control.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze` and `mf check`.

## Risks and Assumptions

- The sizes are read from 2× PNGs, so they can be a sub-pixel off.
- The Google colours are Google's published brand-button values, which the PNG's pixels match (#747775, #1F1F1F).
- Lucide names come from `lucide_icons_flutter` 4.0.1. Where the mock's glyph is ambiguous at 22 dp (Guia de enquadramento, Vibração), the closest Lucide icon is used.
