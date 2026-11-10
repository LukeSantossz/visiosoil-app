# VisioSoil · Redesign v11 · Specification for the Flutter implementation

Audience: the Flutter developer. Repo: `LukeSantossz/visiosoil-app`. Visual reference: [`screens/*.png`](screens/) (390×844 @2x) and the prototype, removed by SPEC 0253 and kept in the git history at [`docs/design/prototipo-v11/`](https://github.com/LukeSantossz/visiosoil-app/tree/10f490937fc4787423e1b90889303a8a597be479/docs/design/prototipo-v11).
The repo was read on 2026-10-22 (read only). The file names below follow the structure of `lib/core/theme`, `lib/core/widgets` and `lib/core/features/*` at that date.

> Golden rule: **the model returns only the texture class and the confidence.** There are no fractions, no top 3 and no field plot (details in §11).

This document was translated from pt-BR by SPEC 0254. Product copy stays in pt-BR, quoted, because it is what the screens show. Decimal commas in the prose became decimal points. Inside quoted copy they stay as the app writes them.

---

## 0. Status

SPECs 0178 to 0200 built this design, one per row of §12. SPECs 0201 to 0218 then matched the screens to the PNGs, and SPECs 0180, 0185 and 0186 adjusted contrast and typography (§15, §16).

The sections below record the design as approved on 2026-10-23 and 2026-10-24. Where later specs changed it on purpose, the change is listed here once, and the section it changes is left as approved.

### 0.1 Divergences between the repo and the redesign, resolved

The redesign opened with five divergences to resolve first. All five are resolved.

| Topic | Repo on 2026-10-22 | Redesign v11 (approved) | Resolved by |
|---|---|---|---|
| Confidence bands | `ConfidenceLevel`: high ≥ 0.80, moderate 0.60–0.79, low < 0.60 | **high ≥ 75, medium 50–74, low < 50**, with the label "Média" instead of "Moderada" | SPEC 0181: `highThreshold = 0.75`, `moderateThreshold = 0.50` |
| Haptics | `AppHaptics`: `selection`, `confirm` (light), `result` (medium), and a comment saying "no heavy tier" | `heavyImpact` ×2 **only** on a bad photo, plus delete, undo and the account-linking sequence | SPEC 0179: `blocked()` (heavy ×2) and `linked()`, behind the "Vibração" toggle |
| Curves | `AppMotion.standard = Cubic(.2,0,0,1)`, `emphasized = Cubic(.3,0,.1,1)`, `out` | 5 M3 curves (§6) | SPEC 0179: `emphasized = Cubic(.2,0,0,1)` and the other 4 |
| Sun mode | `lightHighContrast`/`darkHighContrast` (SPEC 0130), borders only | Its own palette, larger type and 56 dp targets | SPEC 0178 (`AppPalette.sun`, `AppDensity`) and SPEC 0182 (`AppTheme.sun`) |
| `class_score.dart` | A list of scores per class | The UI shows **only** the winning class | Nothing to build: the record stores the distribution (SPEC 0097) and no screen shows it |

### 0.2 Where the app departs from this document

| Spec | Section | What the app does |
|---|---|---|
| SPEC 0219 | §3.6 | A capture is saved when the camera returns the photograph. The bookmark's only action is removal |
| SPEC 0221 | §3.5, §6.3 | While classifying, the four model classes blink in turn and there are no particles. The predicted class then fills, with a 4% pulse over 360 ms |
| SPEC 0223 | §3.3, §3.7, §3.10 | The collection counts the contract's classes, `N/4` today, not 12 USDA classes. The "Coleção" grid lists the contract's classes |
| SPEC 0235, SPEC 0236, SPEC 0250 | §3.3, §3.7, §3.10, §3.11 | While no sync backend is wired, the app shows no sync status pill or banner, no "Sincronizar" action, and no "Backup na conta" or "Sincronizar só no Wi-Fi" row |
| SPEC 0241 | §3.2, §3.10 | The account copy says the analyses stay on the device. It no longer promises sync |
| SPEC 0243 | §3.9 | The tips disclaimer has no fill. Its text uses `onSurfaceVariant` |
| SPEC 0245 | §3.6, §3.8 | A record's date and time read `dd/MM/yyyy · HH:mm` everywhere |
| SPEC 0246 | §3.9 | The "Dicas" tab has no back arrow |
| SPEC 0247 | §3.7 | "Histórico" shows one line, "N análises", instead of the 3-cell summary |
| SPEC 0267 | §3.6, §7 | The result's app bar draws no bookmark, so a save neither fills nor pops one. The "Salvo no histórico" snackbar confirms the save, and a record is deleted from its Detalhes tab |
| `docs/agents/project.md` | §3.4 | Capture is camera-only by design, so the gallery slot stays empty |

---

## 1. Tokens

### 1.1 Colours (the hex values are the mock's; the names follow `AppPalette`)

| AppPalette token | Mock CSS | Light | Dark | Sun mode |
|---|---|---|---|---|
| background | --bg | #F8FAF5 | #121411 | #FFFFFF |
| surface | --surf | #FCFDF8 | #1E201D (the repo's value; the mock used #1A1C19) | #FFFFFF |
| surfaceContainer | --surf2 | #EEF1E9 | #232521 | #F2F2F2 |
| surfaceContainerHigh | --surf3 | #E0E4DA | #2F312D | #E6E6E6 |
| onSurface / onBackground | --on | #1A1C19 | #E2E3DD | #000000 |
| onSurfaceVariant | --on2 | #43483E | #C3C8BB | #000000 |
| textTertiary (ext) | --on3 | #5E6359 | #A3A89C | #1F1F1F |
| outlineVariant | --line | #C3C8BB | #43483E | #000000 |
| divider (ext) | --line2 | #E0E4DA | #2F312D | #000000 |
| outline | --outline | #73796D | #8D9287 | #000000 |
| primary (fill) | --pri | #4A7C59 | #B1D1B9 | #1F4D2E |
| primaryText (ext: green text/icon on the background) | --priT | #3B6A49 | #B1D1B9 | #1F4D2E |
| onPrimary | --onpri | #FFFFFF | #1B3625 | #FFFFFF |
| primaryContainer | --pc | #CCE8D4 | #324D3B | #FFFFFF (+ 2 px black border) |
| onPrimaryContainer | --onpc | #0D2818 | #CBEAD2 | #000000 |
| secondary | --sec | #8B6F47 | #E4C192 | #4A3417 |
| secondaryContainer | --sc | #F5E6D3 | #5A431E | #FFFFFF |
| onSecondaryContainer | --onsc | #2D1F0E | #FFDDB1 | #000000 |
| warning (ext, text on warningContainer = onWarningContainer) | --warn | #6D4C1D | #FEB968 | #4A3417 |
| warningContainer (ext) | --wc | #FBEBD2 | #604012 | #FFFFFF |
| error | --err | #BA1A1A | #FFB4AB | #8C0009 |
| errorContainer | --ec | #FFDAD6 | #93000A | #FFFFFF |
| onErrorContainer | --onec | #410002 | #FFDAD6 | #8C0009 |
| selected (ext: selected row/chip) | --sel | #E4F0D9 | #243517 | #FFFFFF |
| destructive (the swipe's "Excluir" button) | — | #B3261E / text #FFF | same | same (contrast 6.5:1) |
| Focus ring | — | primary 2 px | primary 2 px | outline 3 px #000 + halo 6 px #FFD400 |

Amber of the "bad photo" warning: `warningContainer` background, `warning` text, amber outline (`warning`) on the chips that failed.
Decorative background (glow), only in the light and dark themes: primary at 13–16% (light) / #B1D1B9 at 10% (dark). None in Sun mode.

### 1.2 Typography: Inter
- Font: `Inter` (asset or `google_fonts`), with the features `cv11` and `ss01` (`FontFeature('cv11')`, `FontFeature('ss01')`). Tabular figures (`tnum`) in percentages, times and statistics.
- Light/dark base (Sun mode in parentheses):

| Role | Use | Size/height | Weight |
|---|---|---|---|
| displaySmall | the result's confidence % | 40/44 | 650 |
| headlineMedium (`t-title`) | screen titles and the class name | 28/36, tracking −0.025em | 650 |
| titleMedium | card title, name in a row (`.k`) | 16/22 (17/24) | 600 |
| bodyLarge (`t-body`) | paragraphs | 16/24 (18/27) | 400 |
| bodyMedium (`t-sm`) | supporting text | 14/20 (16/24) | 400 |
| labelLarge | buttons | 15–16 (17) | 600 |
| labelMedium | bottom bar | 12 (14, 600) | 500/700 sel. |
| bodySmall (`t-xs`) | metadata and captions | 12/16 (14/20, colour #000) | 400 |
| pill | status badge | 12 (14), height 24 (28) | 600 |

### 1.3 Spacing (keep `AppSpacing`)
xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48. Side margin of the screens: 20 (mock). Use `lg`+4 = 20 or create `AppSpacing.page = 20`. Gap between sections: 24. List: a row with a `min-height` of 56 (64 in Sun mode), vertical padding 8 and gap 12.

### 1.4 Radii, targets and borders
- Radii: mock r1 4 · r2 8 · r3 12 · r4 16. Repo: sm 8 · md 12 · lg 16 · xl 24 · pill 999. Add `AppRadius.xs = 4` and use `6` on the badge (status pill).
- Buttons: pill (999). Cards: 16. Sheets: 24 at the top. Thumbnail: 12. Camera/frame: 16.
- Density (create `ThemeExtension<AppDensity>`): `tap` 48 (light/dark) / 56 (Sun); `buttonHeight` 52 / 56; `borderWidth` 1 / 2; `navHeight` 80 / 88; `shutter` 72 / 80.

### 1.5 Elevation
Flat by default. Use the existing `AppPalette` shadows: `shadowCard` (cards, 0 1 2), `shadowControl` (chips and controls), `shadowElevated` (sheets, snackbar, menus). Dark: no shadow; elevation comes from the tone (surface → surfaceContainer). Sun mode: **no shadow**, only a 2 px black border.

---

## 2. ThemeData and ColorScheme (M3)

Extend `AppTheme._build(AppPalette p)` (already `useMaterial3: true`):
- `ColorScheme`: primary, onPrimary, primaryContainer, onPrimaryContainer, secondary…, error…, `surface`=p.surface, `onSurface`, `onSurfaceVariant`, `outline`, `outlineVariant`, `surfaceContainerLowest`=background, `surfaceContainer`=--surf2, `surfaceContainerHigh`=--surf3, `inverseSurface`, `onInverseSurface`, `inversePrimary`. `scaffoldBackgroundColor = p.background`.
- Tokens outside M3 (`primaryText`, `textTertiary`, `divider`, `warning*`, `selected`, `destructive`) stay in `AppPalette` (already a `ThemeExtension`).
- Add `static ThemeData get sun => _build(AppPalette.sun)`, with:
  - a scaled `textTheme` (§1.2);
  - `materialTapTargetSize: padded`;
  - `visualDensity: standard`;
  - `ButtonStyle.minimumSize: Size(64,56)`;
  - a 2 px black `side` on Outlined, cards, chips and Switch (track outline);
  - `NavigationBarTheme`: height 88, a black indicator and a white icon when selected.
- Theme selection: a "Tema" segmented control with "Sistema" | "Claro" | "Escuro" (default "Sistema") + a separate "Modo Sol" switch. Turning Sun on overrides the theme; turning it off returns to the chosen theme. The legacy "Alto contraste" switch goes away (Sun replaces it). The initial default follows the system (light/dark); Sun mode turns on only manually. Sun mode forces the high-contrast light theme and ignores `platformBrightness`.
- Floating `SnackBar`, radius 8, `inverseSurface`. `NavigationBar` with `indicatorColor = primaryContainer` (already exists).

---

## 3. Screen inventory

Convention: each screen has the states **ok · empty · loading · error · offline** where they apply. "Bad photo" exists only on the camera. Confidence: **high ≥ 75** (primaryContainer, `verified` icon, label "Confiança alta"), **medium 50–74** (warningContainer, `info`, "Confiança média"), **low < 50** (errorContainer, `warning`, "Confiança baixa"). The mock has a PNG only for high. Medium and low follow the same screen, with the colours and text of the table in §3.14. All mock text marked "Exemplo"/"Simulação", and the data (Ana Ribeiro, Rio Verde), are fictitious.

### 3.1 Boot "Peneira" (sieve): `splash_screen.dart` · [`screens/01-boot-sieve.png`](screens/01-boot-sieve.png)
- Layout: a green background (#1B3625 dark / #1F4D2E Sun / primary light). In the centre, the sieve mesh with grains falling and settling. The `visio_soil_logo.dart` logo, and below it "VisioSoil" + "Análise de textura do solo". A "Pular" text button in the bottom corner.
- Motion (§6): ≈1.6 s in total, then a Hero of the logo to the Home app bar. Reduce motion: a static logo and a 150 ms fade.
- It appears only on a cold start. On a warm return, none.

### 3.2 Onboarding (4 steps): `onboarding_screen.dart`
Common header: "Passo N de 4" + a step indicator (4 dashes). An illustration at the top (up to 330 px in Sun mode, where it is white with a 2 px bottom border).
1. **Optional Google sign-in** (`02`, `03` loading, `04`/`37` linked)
   - Title: "Vincular conta para salvar e sincronizar suas análises"
   - Text: "Guardamos suas análises, fotos e coleção na sua conta Google. Sem conta, tudo fica só neste aparelho."
   - Buttons: ["Continuar com o Google"] (brand button, §9) · ["Agora não"] (text)
   - Loading: the button becomes "Vinculando sua conta…" with a spinner, disabled. "Agora não" stays active.
   - Linked: title "Conta vinculada", text "Suas análises vão sincronizar sozinhas quando houver internet.", the account card (avatar with initials "AR", name, e-mail) and ["Continuar"]. Haptic medium, then light 90 ms later. A green ring on the avatar.
   - Error (no PNG): snackbar "Não foi possível vincular. Tente de novo ou continue sem conta." The buttons return to their initial state.
   - Offline (no PNG): the Google button is disabled, with the caption "Sem conexão. Você pode vincular depois em Perfil."
2. **Sample photo** (`05`): "Fotografe a amostra de solo" / "Destorroe uma porção da camada de 0–20 cm e enquadre na moldura. O app checa luz, foco e distância antes de liberar a foto." · ["Continuar"] · ["Pular"]
3. **Estimated class** (`06`): the triangle illustration ("Argila"/"Areia"/"Silte") · "Veja a classe textural estimada" / "O resultado mostra a classe textural estimada pelo modelo e a confiança dela, em palavras e em percentual." · ["Continuar"] · ["Pular"]
4. **Camera permission** (`07`): "Permita o acesso à câmera" / "Usamos a câmera para fotografar o solo. Funciona sem internet; as análises sincronizam quando houver sinal." A list with:
   - "Câmera, para fotografar a amostra. As fotos ficam no aparelho."
   - "Localização aproximada, opcional, para registrar onde a amostra foi coletada."

   Buttons: ["Permitir câmera"] · ["Agora não"]. Denied: reuse `camera_permission_denied_view.dart`.

### 3.3 Home: `home_screen.dart` · `08`, `09` empty, `25` Sun, `27` dark
- App bar: "Início". Hero card `hero_capture_card.dart`: ["Analisar solo"] (primary CTA, camera icon).
- "Esta semana": `stats_grid.dart` with 3 cells: "6 análises" · "7/12 coleção" · "82% última confiança" (empty: "0", "0/12", "— última classe").
- "Recentes" + a "Ver todas" link: up to 5 rows (thumbnail, class, "hoje 10:42", "82%", status pill **"Enviada" / "Pendente" / "Erro"**). A row with an error: "—" in place of the %.
- Empty (`09`): "Suas análises aparecem aqui." / "Fotografe a camada de 0–20 cm, na sombra e sem palha."
- Loading: a skeleton (3 cells + 3 rows) with shimmer. Reduce motion: no shimmer.
- Error: `home_data_error.dart` with "Não foi possível carregar suas análises." ["Tentar de novo"].
- Offline: Home works (it is local). Show only the "Pendente" pill.
- NavigationBar: "Início" · "Histórico" · "Dicas" · "Perfil".

### 3.4 Guided camera: `guided_camera_screen.dart` · `10`, `11` ready, `12` bad photo, `28` shutter
- Top bar: back + "Nova análise". A central frame (`capture_guide_overlay.dart`) with a dynamic hint at the top, for example "Aproxime até a amostra preencher a moldura" and "Procure sombra uniforme ou mais luz".
- 3 quality chips (`live_reading`): **"Luz"** ("Baixa"/"Boa" · "180 lx"), **"Foco"** ("Desfocado"/"Ajustando…"/"Nítido"), **"Distância"** ("48 cm", target 18–25 cm). Each chip has 3 states: failed, adjusting, ok.
- Footer: the caption "Captura liberada quando os 3 itens estiverem ok", a gallery button (56 in Sun mode) and the shutter (72/80).
- **Ready** (`11`/`28`): every chip is ok, the shutter enables and the green ring enters. Tap: scale .86 + a 55% white flash (no flash in Sun mode) + mediumImpact.
- **Bad photo** (`12`): a tap while some chip is failing. The button shakes (300 ms), and the fixed amber warning enters above the chips for 3.8 s, with the text "Ainda não dá para fotografar" and a detail built from the chips that failed, for example "Pouca luz, fora de foco, longe demais. Procure sombra clara, aproxime até a amostra preencher a moldura e segure firme." The chips that failed get an amber outline, and heavyImpact ×2 plays. The detail is composed of parts: light → "Pouca luz" / "Procure sombra clara"; focus → "fora de foco" / "segure firme"; distance → "longe demais"/"perto demais" / "aproxime até a amostra preencher a moldura".
- No permission: `camera_permission_denied_view.dart`. Camera error: "Não foi possível abrir a câmera." ["Tentar de novo"].
- Remove from the UI the "Simulação" label and the haptic indicator (they exist only in the mock).

### 3.5 Processing: inside the result flow · `13`, `29`, `30`, `31`, `38` Sun
- App bar "Resultado". A large texture triangle ("Argila"/"Areia"/"Silte") with the particles falling (§6.3). At the end, the class's region fills and shows its name ("Franco-argilosa").
- Texts: "Analisando a amostra" · "Comparando com o modelo no aparelho" · "cerca de 5 s" + a thin indeterminate progress bar.
- Fixed caption: "Diagrama ilustrativo, com regiões aproximadas (USDA/SBCS). Mostra a classe, não a posição da amostra."
- Sun (`38`): no particles. The region fills in #1F4D2E and there is only a change of state.
- A timeout over 15 s goes to the result's error.

### 3.6 Result: `details_screen.dart`/`classification_header.dart` · `14`, `32` entry, `33` saved, `26` Sun, `15` error
- Top: "22/10/2026 · 10:42" · overline "Classe textural (triângulo USDA)" · **the class name** (headline) · badge "Confiança alta" + "82%" (display, tnum) + the confidence bar.
- Tabs (segmented): **"Visão geral" · "Manejo" · "Detalhes"**.
- "Visão geral":
  - "O modelo estima a classe textural pela foto. A confiança indica o quanto ele está seguro dessa classe."
  - Card "No triângulo textural": the highlighted region, with "A região está destacada." and the diagram's caption.
  - Card "Sobre a classe" · "Referência geral": "Solos franco-argilosos costumam ter 27–40% de argila e 20–45% de areia, segundo o triângulo USDA. Retêm bem água e nutrientes e compactam com facilidade quando úmidos." + the note "Faixa típica da classe, não medição desta amostra." (static text per class, not model output).
  - Card "Amostra": "Rio Verde, GO · −17,79, −50,92 · Camada 0–20 cm · solo seco ao ar".
  - Notice: "Estimativa por imagem. Para laudo, confirme com análise granulométrica em laboratório."
- Footer: ["Corrigir"] (outlined, opens `labels_dialog.dart`) · ["Dicas de manejo"] (primary). A "Salvar" action (bookmark) in the app bar.
- Saved (`33`): the bookmark fills, pops to 1.28, the snackbar "Salvo no histórico" shows and lightImpact plays.
- Error (`15`): "Não deu para classificar" / "A foto ficou escura e com reflexo. Refaça na sombra, com a amostra preenchendo a moldura." · ["Fotografar de novo"] · ["Ver dicas de captura"]. The reason comes from `image_quality_report`. Variations: "A foto ficou desfocada…" / "A amostra ficou pequena na moldura…".
- Offline: the result is local and works. The "Manejo" section shows "Dicas atualizadas precisam de internet. Mostrando as últimas salvas."

### 3.7 History: `history_screen.dart` · `16`, `17` empty, `18` offline, `34` swipe
- App bar "Histórico" + search + filters (`history_filter_bar.dart`). Segmented: **"Análises" · "Coleção"**.
- A 3-cell summary: "25 análises" · "6 nesta semana" · "7/12 classes".
- A list grouped by date ("Hoje", "Ontem", "18 out"). Each row: a 56 thumbnail with radius 12, the class, "10:42 · 82% de confiança", and a chevron or a "Pendente" pill.
- **Swipe to delete** (`34`): dragging left past 50 px moves the row back 12 px, and the red "Excluir" button (width 104, trash icon) enters from the right. **The thumbnail and the text stay visible.** Tapping "Excluir": the button expands to the full width, the row exits and its height collapses. Snackbar "Análise excluída" ["Desfazer"] (5 s). Implement it with a custom `Dismissible`/`Slidable`, without a modal confirmation (undo replaces it). Accessibility: a semantic "Excluir" action (`CustomSemanticsAction`), since the swipe is not accessible.
- Empty (`17`): "Nenhuma análise ainda" / "Suas análises aparecem aqui, agrupadas por data, mesmo sem internet." ["Fazer primeira análise"].
- Offline (`18`): the banner "Sem conexão" / "1 análise aguarda envio. Tudo continua salvo neste aparelho." (plural: "N análises aguardam envio.").
- Loading: "Carregando histórico" (skeleton). Error: "Não foi possível carregar o histórico." ["Tentar de novo"].
- "Coleção": a grid of the 12 USDA classes (`history_grid.dart`). The classes collected are coloured with `soil_texture_colors.dart`; the others are outlined.

### 3.8 Analysis details: `details_screen.dart` · `19`
The sample photo at the top (a Hero from the thumbnail). A list of label/value pairs:
- "Classe estimada · Franco-argilosa"
- "Confiança · Alta · 82%"
- "Data e hora · 22/10/2026 · 10:42"
- "Coordenadas · −17,79 · −50,92"
- "Captura · 1.480 lx · 21 cm · nítido"
- "Modelo · no aparelho · v0.3"

Actions: share and delete (`confirm_destructive_action.dart`).

### 3.9 Management tips: `management_tips_section.dart` · `20`
- The header "Dicas de manejo", the context "Franco-argilosa · Soja · safra 26/27 · 4 dicas" and a sample notice (in the real app: a real source and citation).
- A timeline by phase: "Antes do plantio · Agora", "Semeadura · Próximo", "Ciclo da cultura". The tip card: title, text and source.
- Loading: "Carregando dicas". Offline: the last cached ones + a notice. Error: "Não foi possível carregar as dicas." ["Tentar de novo"]. Empty: "Sem dicas para esta classe ainda."

### 3.10 Profile (the bar's 4th tab): `21` anonymous, `22` linked (create `profile_screen.dart`; it did not exist on 2026-10-22)
- Anonymous:
  - the card "Sem conta vinculada · Dados só neste aparelho";
  - "Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem.";
  - "25 análises e 7 classes guardadas neste aparelho";
  - ["Continuar com o Google"].
- Linked: avatar, name, e-mail, "Sincronizado hoje, 10:45" ["Sincronizar"].
- "Neste aparelho": 25 análises · 7/12 coleção · 23 enviadas (anonymous: "só no aparelho").
- Links: "Configurações · Tema, câmera, dados e acessibilidade" · "Como fotografar a amostra · Luz, distância e preparo".
- Linked: ["Sair da conta"] + "As análises continuam neste aparelho".

### 3.11 Settings: `settings_screen.dart` · `23`, `24` export, `35`/`36` vibration
Sections and items (the copy is exact):
- **"Conta":**
  - anonymous: "Não vinculada · dados só neste aparelho";
  - linked: "Conta Google · e-mail".
- **"Preferências":**
  - "Tema" (segmented "Claro" | "Escuro" | "Modo Sol"), caption "Alto contraste e letras maiores para o campo";
  - **"Vibração"** (switch, on by default, right below "Modo Sol") "Toques sutis ao capturar, salvar e concluir";
  - "Unidades" "Distância em cm";
  - "Idioma" "Português (Brasil)".
- **"Câmera e análise":**
  - "Guia de enquadramento" "Moldura e checagem de luz, foco e distância";
  - "Salvar fotos na galeria";
  - "Registrar localização" "Aproximada, opcional".
- **"Dados e sincronização":**
  - "Backup na conta": "Requer conta vinculada" (disabled) / "Último: hoje, 10:45" ["Fazer agora"];
  - "Sincronizar só no Wi-Fi";
  - "Exportar análises" "Planilha CSV";
  - "Limpar dados do aparelho" "Apaga análises e fotos locais" (destructive, with a confirmation).
- **"Acessibilidade":**
  - "Reduzir movimento" "Troca animações por transições curtas" (default: follows the system);
  - "Tamanho do texto" (segmented "Padrão" | "Grande").
- **"Sobre e ajuda":** "Como fotografar a amostra" · "Privacidade e dados" · "Enviar comentário" · "Versão".

The export sheet (`24`):
- "25 análises em uma planilha CSV.";
- checkboxes "Classe e confiança" (fixed), "Data e hora", "Localização aproximada", "Incluir fotos (arquivo .zip)";
- ["Exportar"].

Use `share_service`.

### 3.12 Capture guide: `capture_guide_screen.dart`
It keeps its current content, with the new tokens (outside the mock's scope).

### 3.13 Global snackbars and banners
"Salvo no histórico" · "Análise excluída" ["Desfazer"] · "Sem conexão" (banner) · network error: a snackbar only, no haptic.

### 3.14 Confidence table (single source: `ConfidenceLevel`)
| Level | Band | Label | Container | Icon | Supporting text | Entry haptic |
|---|---|---|---|---|---|---|
| high | ≥ 75% | "Confiança alta" | primaryContainer | verified | — | mediumImpact |
| medium | 50–74% | "Confiança média" | warningContainer | info_outline | "Resultado provável. Se puder, refaça a foto para confirmar." | mediumImpact |
| low | < 50% | "Confiança baixa" | errorContainer | warning_amber | "O modelo não está seguro. Refaça a foto na sombra, com a amostra preenchendo a moldura." + ["Fotografar de novo"] | lightImpact |

Always show the label **and** the percentage (never the colour alone).

---

## 4. Reusable components (`lib/core/widgets/`)

| Component | Props | States |
|---|---|---|
| `VisioButton` (exists) | `label`, `icon?`, `variant` (primary/outlined/text/destructive), `onPressed?`, `loading` | default, pressed (scale .97, `press_scale.dart`), disabled, loading (spinner + an alternative label) |
| `GoogleSignInButton` | `onPressed`, `loading`, `label` ("Continuar com o Google") | default, pressed, loading, disabled (offline). Follow §9 |
| `VisioAppBar` (exists) | `title`, `leading?`, `actions` | — |
| `StatCell` / `StatsRow` | `value`, `label`, `semanticLabel` | normal, skeleton |
| `AnalysisTile` | `record`, `onTap`, `onDelete?`, `dense` | normal, pending, error, skeleton, swipe-revealed, deleting |
| `SwipeToDelete` | `child`, `onDelete`, `onUndo`, `threshold=50` | closed, revealed, exiting |
| `SoilThumb` | `image`, `size` (56), `heroTag` | loading, ok, no image (texture per class) |
| `StatusPill` | `status` (sent/pending/error) | 3 colours. Sun: white with a black border |
| `ConfidenceBadge` | `score` (0–1) → `ConfidenceLevel` | high/medium/low; `compact` (% only) |
| `ConfidenceBar` | `score`, `animate` | fills in 600 ms |
| `TextureTriangle` | `highlightClass`, `mode` (static/processing), `onSettled` | empty, particles, settled, highlighted |
| `QualityChip` | `kind` (light/focus/distance), `value`, `status` | failed (amber in the warning), adjusting, ok |
| `ShutterButton` | `enabled`, `onCapture`, `onBlocked` | disabled, ready (ring), pressed, shake |
| `CaptureAlert` | `failures: Set<QualityKind>` | enters / visible 3.8 s / exits |
| `SegmentedControl` | `options`, `value`, `onChanged` | the indicator slides in 250 ms |
| `SettingsSwitchTile` | `title`, `subtitle`, `value`, `onChanged`, `haptic` | on/off/disabled, the thumb's spring |
| `EmptyState` / `ErrorState` / `LoadingIndicator` (exist) | `icon`, `title`, `message`, `action?` | — |
| `OfflineBanner` | `pendingCount` | singular/plural |
| `AccountCard` | `account?` | anonymous, linked, linking |
| `StepIndicator` | `total=4`, `current` | — |
| `TipCard` / `TipTimeline` | `phase`, `title`, `body`, `source` | normal, skeleton |

---

## 5. Layout principles
- The grid is a single column with a margin of 20 and a maximum content width of 560 (tablet, §10).
- Lucide icons (`lucide_icons_flutter`, or export the SVGs used), with a stroke of 1.75 (2.25 in Sun mode). The logo is `visio_soil_logo.dart`, which draws it in code. The source SVG the mock cited (`/workspace/logo/visiosoil-logo.svg`) was on the designer's machine and is not in the repository.
- No flashy gradient, strong glow or emoji. One primary CTA per screen.

## 6. Motion

### 6.1 Tokens (add to `AppMotion`)
```dart
static const emphasized = Cubic(.2, 0, 0, 1);          // M3 emphasized (replaces the current .3,0,.1,1)
static const emphasizedDecelerate = Cubic(.05, .7, .1, 1);
static const emphasizedAccelerate = Cubic(.3, 0, .8, .15);
static const standardDecelerate = Cubic(0, 0, 0, 1);
static const standardAccelerate = Cubic(.3, 0, 1, 1);
// durations: instant 90 · fast 140 (mock 120) · base 220 (mock 200–250) · slow 380 · reveal 640
```

### 6.2 Boot "Peneira" (≈1.6 s)
1. The mesh enters with a fade and scale .96→1 (250 ms, emphasizedDecelerate).
2. Grains (CustomPainter) fall through the mesh with a 20 ms stagger and settle (760 ms, emphasizedDecelerate).
3. The logo and the name rise 8 px with a fade (250 ms, standardDecelerate).
4. At 1.2 s, a Hero of the logo to Home.

"Pular" ends it at once. Reduce motion: the logo only, a 150 ms fade.

### 6.3 Processing particles (CustomPainter)
- 26 particles (circles and irregular polygons of 2–4 px in the class's texture colour; Sun: not rendered).
- Each goes from a random y above the triangle to a random point **inside the class's polygon** (rejection sampling), with scatter in x.
- 760 ms emphasizedDecelerate each, a 28 ms stagger, in a window from 1.15 s to 1.9 s.
- At 2.1 s: lightImpact, a 4% pulse on the region (360 ms) and the particles' exit (280 ms standardAccelerate).
- Implementation: one 2.4 s `AnimationController` and one `CustomPainter` that reads `controller.value` and computes each particle's progress with `Interval`. Pre-generate the positions with `Random(seed)`. Wrap it in a `RepaintBoundary`. No widget per particle.

### 6.4 Other transitions
- Routes: shared axis X (push 300 ms emphasized) and fade-through on the bar's tabs.
- Hero: thumbnail → the details photo (tag `record.id`); boot logo → Home.
- Result entry: blocks rise 8 px in a cascade (250 ms, +30 ms/block); the confidence bar fills (600 ms, 180 ms delay).
- Swipe, save, toggles and sign-in: exactly as in the table of §7.
- A 1.2 s skeleton shimmer in a loop (off with reduce motion).

### 6.5 Reduce motion
`final reduce = MediaQuery.disableAnimationsOf(context) || prefs.reduzirMovimento;`
- If `reduce`, durations of 0 or a 150 ms fade. No particles, no shake (the amber warning stays), no shimmer and no Hero (use a fade).
- **The haptics stay** (they are not motion).

## 7. Haptics
The full table (event → Flutter API → animation → duration/curve) is in [`haptics.md`](haptics.md) (in this folder). Implementation:
```dart
abstract final class AppHaptics {
  static bool enabled = true;                 // tied to the Vibração toggle (prefs)
  static Future<void> selection() async { if (enabled) await HapticFeedback.selectionClick(); }
  static Future<void> confirm()  async { if (enabled) await HapticFeedback.lightImpact(); }   // settle, save, undo, low confidence, turning vibration on
  static Future<void> result()   async { if (enabled) await HapticFeedback.mediumImpact(); }  // shutter, high/medium result, delete
  static Future<void> blocked() async {        // bad photo
    if (!enabled) return; await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 60)); await HapticFeedback.heavyImpact(); }
  static Future<void> linked() async {         // account linked
    if (!enabled) return; await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 90)); await HapticFeedback.lightImpact(); }
}
```
- Summary of the uses:
  - `selection`: tab, segmented control, toggle, swipe past the threshold, remove from saved;
  - `result`: shutter, high/medium result, delete;
  - `confirm`: settling, save, undo, low result, turning "Vibração" on;
  - `blocked`: bad photo;
  - `linked`: sign-in.
- No vibration on: scrolling, opening tips, the chips' progress, boot, pull-to-refresh, network errors.
- When "Vibração" is turned on, play `confirm` after the preference is written, as a sample.

## 8. Accessibility
- **Contrast:** text ≥ 4.5:1 and icons/borders ≥ 3:1 in the light and dark themes. In Sun mode, ≥ 7:1 (black text on white, and #1F4D2E on white = 9.6:1). Test with `meetsGuideline(textContrastGuideline)`.
- **Targets:** ≥ 48 dp (`androidTapTargetGuideline`); 56 dp in Sun mode. The camera chips are not tappable (only `Semantics(liveRegion)`).
- **Semantics:**
  - history row: `"Franco-argilosa, 10:42, 82% de confiança"` + the action "Excluir";
  - badge: "Confiança alta, 82 por cento";
  - shutter: "Fotografar", with `enabled` and the hint "Aguardando luz, foco e distância" when blocked;
  - the bad-photo warning and the snackbar: `liveRegion: true`;
  - triangle: `excludeSemantics` + the label "Diagrama do triângulo textural, classe Franco-argilosa destacada";
  - stat: "6 análises nesta semana".
- **Font scale:** support up to 200% (`MediaQuery.textScalerOf`). No fixed height on rows and buttons (use `minHeight`). From 1.3× on, the stats go to 1 column and the footer buttons stack. "Tamanho do texto: Grande" applies 1.15× on top of the system scale.
- A visible focus on every interactive element (the ring of §1.1), and a reading order equal to the visual one.
- Do not depend on colour: status, confidence and chips always carry text or an icon.

## 9. Optional Google sign-in
- Sign-in is **optional**: the app works 100% anonymous and local. "Agora não" in the onboarding, and linking later from "Perfil" or "Configurações". `google_auth_service.dart` and `google_sign_in_gateway.dart` already exist; only the UI needs wiring.
- **Branding (Google Identity guidelines):**
  - use the official multicolour "G" logo, not recoloured, on a white/light background (#FFFFFF, border #747775) or a dark one (#131314, text #E3E3E3, border #8E918F). In Sun mode, the light version with a height of 56;
  - the exact text **"Continuar com o Google"**, Roboto Medium 14 (or the system font), pill shape, padding of 12 and a gap of 10 between the logo and the text;
  - do not use the logo alone, do not use the app's primary colour on the button, and do not add another icon.
- After linking: a green ring on the avatar + `AppHaptics.linked()`. On an error: a snackbar (§3.2). On signing out: the confirmation "Sair da conta? As análises continuam neste aparelho."

## 10. Responsiveness
- **Small screens (≤ 360 × 640):**
  - the camera frame shrinks to 80% of the width;
  - the onboarding illustration has a maximum height of 200;
  - stats with 3 columns and a value of 20;
  - the result's footer stacked;
  - the NavigationBar keeps its labels.
- **Tablet (≥ 600 dp):** a `NavigationRail` on the left.
  - Content with a maximum width of 560, centred.
  - History as master-detail at ≥ 840 (list 360 + details).
  - The result in 2 columns (triangle | information).
  - The camera in full screen, in portrait.
- Orientation: the phone locked in portrait, the camera included. The tablet is free (the camera also in portrait).
- Safe areas: `SafeArea` everywhere. The camera edge-to-edge.

## 11. Do NOT implement
1. **Fractions** of sand/silt/clay of the sample (the model does not return them). The ranges in "Sobre a classe" are reference text per class.
2. **Top 3**, or any list of alternative classes or probabilities.
3. **Field plot** ("talhão": registration, selection or grouping by area).
4. **The vibration indicator** (the wave and the haptic's name in the corner) and the mock's "Exemplo"/"Simulação" badges.
5. The mock's fictitious data (Ana Ribeiro, Rio Verde, "exemplo" tips).

## 12. Implementation order (small PRs)
| # | PR | Acceptance criteria | Delivered by |
|---|---|---|---|
| 1 | Tokens: `AppPalette` (light/dark/sun), `AppDensity`, `AppRadius.xs`, Inter, `AppTypography` | Golden tests of the 3 palettes. Contrast checked by a test. No screen changes layout | SPEC 0178 (+ SPEC 0186) |
| 2 | `AppTheme.sun` + a 3-theme selector in `appearance_provider` | Changing the theme in "Configurações" updates everything without a restart. 56 targets in Sun mode (a custom `androidTapTargetGuideline`) | SPEC 0182 (+ SPEC 0184) |
| 3 | `ConfidenceLevel` 75/50 + "Média" + `ConfidenceBadge`/`ConfidenceBar` | Tests at the limits 49.9/50/74.9/75. A badge with the label + % | SPEC 0181 (+ SPEC 0187) |
| 4 | `AppMotion` (M3 curves) + an extended `AppHaptics` + the "Vibração" toggle + reduce motion | Vibration off silences everything. With `disableAnimations`, no animation above 150 ms (widget test) | SPEC 0179 |
| 5 | Base components (§4): buttons, pills, tiles, stat, segmented control, switch tile, states | Widget tests of each state. Semantics on all | SPEC 0183 |
| 6 | Home (`08`/`09`/`25`/`27`) | Matches the PNG in the 3 themes (golden). Empty, skeleton and error | SPEC 0189 |
| 7 | Camera: chips, shutter, bad-photo warning (`10`/`11`/`12`/`28`) | Blocked: shake, a warning for 3.8 s and haptic ×2. Ready: medium and flash (no flash in Sun mode) | SPEC 0191 |
| 8 | Processing + `TextureTriangle` with particles (`29`–`31`/`38`) | 60 fps on an entry-level device (profile mode). No particles in Sun mode or with reduce motion | SPEC 0188 |
| 9 | Result + error + save (`14`/`15`/`32`/`33`) | 3 confidence levels. A haptic per level. The saved snackbar | SPEC 0194 (+ SPEC 0196, SPEC 0197) |
| 10 | History + swipe/undo + offline + collection (`16`–`18`/`34`) | The swipe keeps the thumbnail visible. Undo restores the position. A semantic "Excluir" action. A plural banner | SPEC 0190 |
| 11 | Details + Hero (`19`) and Tips (`20`) | A Hero without jank. Offline and error states | SPEC 0198 |
| 12 | Profile as the 4th tab (`21`/`22`) + Settings + Export (`23`/`24`/`35`/`36`) | Every item with exact copy. The CSV generated with the chosen columns | SPEC 0192 |
| 13 | 4-step onboarding + Google sign-in (`02`–`07`/`37`) | "Pular" works. The Google button follows the branding. Error and offline handled | SPEC 0199 |
| 14 | Boot "Peneira" + the logo's Hero (`01`) | ≤ 1.6 s. "Pular". Reduce motion | SPEC 0193 |
| 15 | Responsive (rail, master-detail) + 200% font scale | No overflow at 320×568 and with text at 200%. Rail at ≥ 600 dp | SPEC 0200 |

## 13. PNG reference ([`screens/`](screens/))
01 boot · 02–04, 37 sign-in · 05–07 onboarding · 08, 09, 25, 27 home · 10, 11, 12, 28 camera · 13, 29–31, 38 processing · 14, 15, 26, 32, 33 result · 16–18, 34 history · 19 details · 20 tips · 21, 22 profile · 23, 24, 35, 36 settings.

## 14. Approved decisions (2026-10-23)
1. **Initial theme:** follows the system (light/dark). Sun mode turns on only manually, in "Configurações".
2. **Copy:** the supporting texts for medium/low confidence (§3.14) and the error/offline texts (§3.2, §3.3, §3.6, §3.7, §3.9) are approved as final copy.
3. **Dark `surface`:** #1E201D (the repo's value).
4. **`AppMotion.emphasized`:** becomes `Cubic(.2,0,0,1)` (M3), the existing animations included.
5. **Orientation:** the phone locked in portrait, the camera included.
6. **Profile:** a new screen, the bar's 4th tab ("Início" · "Histórico" · "Dicas" · "Perfil"). "Configurações" is reached from "Perfil".
7. **Heavy haptic:** `heavyImpact` ×2 (60 ms apart) only on a bad photo. It overrides the repo's "no heavy tier" rule.
8. **Confidence:** high ≥ 75, medium 50–74, low < 50, with the label "Média" (replaces "Moderada").

## 15. Contrast adjustment (2026-10-23)

- tertiary #6B7F5A became #677A57 (4.67:1 with white text).
- warning #C88A3D became #B07A35 (3.7:1 on white, for an icon). For warning text, use #9E6B2C (4.57:1).
- Card: https://trello.com/c/Q4FBNyiY

## 16. QA decisions for v11 (2026-10-24)

- Theme: a segmented "Sistema" | "Claro" | "Escuro" (default "Sistema") + a separate "Modo Sol" switch, as on screen 23. It overrides the old 3-option text. Turning Sun off returns to the chosen theme.
- "Alto contraste" leaves "Configurações"; Sun mode covers that case.
- Amber, distinct roles: `onWarningContainer` #6D4C1D is the warning's text on `warningContainer` #FBEBD2 (6.63:1); `warning` #B07A35 is only an icon/bar on white; `warningText` #9E6B2C is amber text on white. In Sun mode, amber text uses #4A3417.
