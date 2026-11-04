# VisioSoil v11 · Microinteractions and haptics map

Principles:
- A haptic confirms a user action or a system result. None plays on scrolling or on a decorative animation.
- At most 1 haptic per event. None ever plays in a loop.
- The toggle **"Configurações → Preferências → Vibração"** (on by default) turns every haptic off. Implement it as `if (prefs.vibracao) HapticFeedback.x()`.
- **Reduce motion** (`MediaQuery.disableAnimationsOf`) replaces the animations with a 150 ms fade or with no animation. The haptics stay, because they are not motion. If vibration is off, they do not play.
- **Sun mode:** no particles, flash or sparkles. Only the state changes (colour/icon) and the haptics remain. The particle uses #1F4D2E, which has high contrast.
- **Curves (M3 tokens):**
  - emphasized `Cubic(.2,0,0,1)`
  - emphasizedDecelerate `Cubic(.05,.7,.1,1)`
  - emphasizedAccelerate `Cubic(.3,0,.8,.15)`
  - standardDecelerate `Cubic(0,0,0,1)`
  - standardAccelerate `Cubic(.3,0,1,1)`
- **Mock:** the indicator in the top-right corner (wave + haptic name) exists only in the prototype and does not go into the app. In the mock, `navigator.vibrate(pattern)` is called when available (Android/Chrome), and the pattern in ms is in the "Web pattern" column.

| Event | Flutter | Web pattern (ms) | Animation | Duration / curve |
|---|---|---|---|---|
| Tab change (bottom bar) | `HapticFeedback.selectionClick()` | 8 | The tab indicator stretches (scaleX .6→1.08→1) | 320 ms · emphasizedDecelerate |
| Segmented control ("Análises"/"Coleção", "Tema", "Texto") | `selectionClick()` | 8 | The indicator slides (already in v9) | 250 ms · emphasized |
| Shutter: capture allowed | `HapticFeedback.mediumImpact()` | 18 | The button sinks (scale .86) + 55% white flash | 280 ms emphasized + flash 260 ms standardDecelerate |
| Shutter: bad photo (blocked) | `heavyImpact()` ×2, 60 ms apart | 30·60·30 | Button shake (v3) + a fixed amber warning above the chips + an amber outline on the chips that failed | shake 300 ms linear · the warning enters in 240 ms emphasizedDecelerate and stays 3.8 s |
| Processing: settling | `HapticFeedback.lightImpact()` at the end (2.1 s) | 12 | 26 soil particles fall from the top (with scatter) and settle inside the class region. They disappear when the region fills. A 4% pulse on the region | each particle 760 ms emphasizedDecelerate, 28 ms stagger between them (from 1.15 s to 1.9 s) · exit 280 ms standardAccelerate · pulse 360 ms |
| Result entry | `mediumImpact()` (high/moderate confidence) · `lightImpact()` (low) | 18 / 12 | Blocks rise 8 px in a cascade (v10) + the confidence bar fills from the left | cascade 250 ms standardDecelerate (+30 ms per block) · bar 600 ms emphasizedDecelerate, 180 ms delay |
| Save (bookmark) | `lightImpact()` | 12 | The icon fills + pop scale 1.28 + snackbar "Salvo no histórico" | 340 ms emphasizedDecelerate · snackbar 250 ms |
| Remove from saved | `selectionClick()` | 8 | The icon empties + shrinks to .8 | 340 ms emphasizedDecelerate |
| History: swipe to reveal Delete | `selectionClick()` on passing the threshold (50 px) | 8 | The row moves back 12 px and the red "Excluir" button (104 px) enters from the right. The thumbnail stays visible | 240 ms emphasizedDecelerate |
| History: delete | `mediumImpact()` | 18 | "Excluir" expands to the full width and the row exits to the left, then its height collapses. Snackbar with "Desfazer" | exit 220 ms emphasizedAccelerate · collapse 260 ms emphasized (180 ms delay) |
| Undo delete | `lightImpact()` | 12 | The row returns (fade + scale .98→1) | 250 ms emphasizedDecelerate |
| Toggles (Settings) | `selectionClick()` | 8 | The switch thumb "springs" (squashes 1.18×.86 mid-travel) | 260 ms emphasizedDecelerate |
| Turn Vibration on | `lightImpact()` (a sample of what the user will feel) | 12 | The same spring as the toggle | 260 ms |
| Google sign-in linked | `mediumImpact()` and, 90 ms later, `lightImpact()` | 18·90·12 | The account card rises 10 px + a green ring expands on the avatar + cloud with a check (v9) | card 340 ms emphasizedDecelerate (120 ms delay) · ring 700 ms standardDecelerate |

No vibration on: scrolling, opening tips, the camera chips' progress (they already give visual feedback), boot, pull-to-refresh, network errors (they show only the error snackbar). The reason is to avoid excess.
