# Information Architecture

## 1. Entity model

The product has one first-class entity and three attributes that users treat as
objects in their own right.

```
Soil record
├── photograph          — an attribute, viewable full-screen
├── classification      — an attribute: class, distribution, verdict band
├── location            — an optional attribute
└── management tips     — a derived, cached, advisory attachment
```

Everything in the interface should be reachable as *this record, and something
about it*. The current navigation does not obey that: the photograph is a
destination that contains a link to the record, which is backwards.

## 2. Navigation model

The app mixes two models and this is not itself a problem — it becomes one only
where the two overlap.

- **Tabs** for the two persistent surfaces: Home and History. Correct.
- **Pushed routes** for transient tasks: capture, details, settings,
  onboarding. Correct.
- The overlap is `/preview` and `/details`, both pushed, both showing one
  record.

`mainTabIndexProvider` (spec 0029) lets pushed content select a tab, which is
how "Ver tudo" reaches History. That mechanism stays.

## 3. Structural fix 1 — the capture route stops being a waiting room

**Today**

```
home ──"Nova análise"──▶ /capture (empty placeholder + "Câmera" button)
                             │
                             └──▶ OS camera ──▶ /capture (photo + chips)
```

The route is entered, shows nothing useful, and waits for a second tap.

**Target**

```
home ──"Nova análise"──▶ [guide, first time only] ──▶ OS camera
                                                          │
                                                          ▼
                                              /capture (photo present)
```

`/capture` is only ever rendered with a photograph in hand. Its identity
changes from *capture screen* to *analysis screen*: it holds the quality
verdict, the processing phases, the result, and the save decision.

Consequences:

- The "Selecione uma imagem" placeholder and its false promise of gallery
  selection disappear, because the state it described no longer exists.
- Camera cancellation returns to home rather than to an empty screen.
- The capture guide gains a real home: shown before the first camera launch,
  then reachable by a "Como capturar" link on the analysis screen.
- The route needs a guard: reaching `/capture` with no image (deep link, process
  restart) must re-enter the camera or return home, never render the old empty
  state.

## 4. Structural fix 2 — the photograph stops being a destination

**Today**

```
history ──tap──▶ /preview ──"info"──▶ /details
                 (photo,               (photo, timestamp,
                  timestamp,            location, classification,
                  location)             tips, actions)
```

Two screens, one entity, overlapping content, and the subordinate one is
entered first.

**Target**

```
history ──tap──▶ /details ──tap on hero──▶ /preview
                                            (photo only, zoomable)
```

`/preview` becomes a pure full-screen photograph viewer: `InteractiveViewer`,
a close affordance, nothing else. Its info panel is deleted, because everything
in it is already in details. Its drag handle is deleted, because it implied a
sheet that never moved.

Consequences:

- `_PreviewErrorView` and the preview's `_RecordNotFoundView` disappear. The
  record is already loaded by details before the viewer opens, so the viewer
  needs no loading, error or not-found state of its own — it needs only a
  broken-image fallback, which it already has.
- Two of the five error presentations catalogued in `03-problems.md` are
  removed by this change alone.
- The preview's two unlabelled circle buttons reduce to one labelled close.

## 5. Screen map, target

| Surface | Type | Purpose | Reached from |
| --- | --- | --- | --- |
| Splash | Route | Brand moment, boot | Launch |
| Onboarding | Route | Value, permission priming | First launch; Settings |
| Home | Tab | Overview, primary call to action | Default |
| History | Tab | Find a previous record | Tab bar; "Ver tudo" |
| Capture guide | Route | Technique before the camera | First capture; "Como capturar" |
| Analysis (`/capture`) | Route | Quality, processing, verdict, save | After the camera returns |
| Details | Route | The record and everything about it | Home row; History card; after save |
| Photo viewer (`/preview`) | Route | The photograph, full-screen | Details hero |
| Recommendation | Section or route | Advisory guidance with sources | Details |
| Settings | Route | Account, data, help | Home avatar |

## 6. The recommendation surface

The design system publishes `RecommendationScreen` as a full screen. The app
implements it as `ManagementTipsSection` inside details.

**Recommendation: keep it a section, not a screen.** Reasons:

- The guidance is meaningless without the classification it derives from.
  Separating them puts the evidence on one screen and the conclusion on another.
- The section already handles cache-first display, offline, abstention and
  refresh correctly. A route split would duplicate all four.
- A full screen implies the guidance is the product's output. It is advisory,
  per ADR 0001, and the texture reading is the output.

If the content grows past what a section can hold — which the design system's
three structured sections would do — the correct escalation is an expandable
section or a bottom sheet from details, not a sibling route. This is recorded
in `05-design-system.md` §5 as part of the contract coordination item.

## 7. Content hierarchy on the analysis and details screens

Ordered by what the user needs first. This ordering is the input to the GenUI
composition rules in `10-genui-strategy.md`.

1. **Verdict** — what the system concluded, or that it concluded nothing.
2. **Qualification** — the band, the limits, and any quality advisory.
3. **Alternatives** — only when ambiguous.
4. **Evidence** — the texture scale, the percentage, the photograph.
5. **Context** — location, timestamp.
6. **Derived guidance** — management tips and their sources.
7. **Actions** — save, retake, share, delete.

The current details screen orders these as: photograph, class, badge, banner,
info, tips, actions. The photograph leads, which places the input above the
conclusion. Under the target ordering the photograph becomes evidence,
subordinate to the verdict — it stays visually prominent as the sliver hero but
no longer occupies the first reading position on its own.
