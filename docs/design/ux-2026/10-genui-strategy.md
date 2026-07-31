# GenUI Strategy

## 1. Which meaning of GenUI

The word covers two very different architectures:

- **Adaptive composition** — the interface recomposes itself from a fixed set of
  compiled components according to context. The composition rule is code.
- **Server-driven UI** — a backend returns a description of an interface, which
  the client renders. The composition rule is data, and it arrives at runtime.

**Decision (taken with the product owner): adaptive composition.**

The reasons are specific to this product rather than general preference. ADR
0001 records indirect prompt injection as the primary threat to the research
agent, because the agent reads arbitrary web pages; the ADR requires all fetched
content to be handled as data and never as instructions. A server-driven layout
whose content originates in those same pages is a channel through which fetched
material would influence structure — the exact boundary the ADR draws. And the
brief's own constraint is that GenUI must not introduce artificial complexity or
generative components without demonstrated functional benefit.

Server-driven UI remains documented in §6 with the conditions under which it
could be reconsidered.

## 2. What actually varies

The result surface has real, enumerable variation. That variation is the case
for adaptive composition; it is not invented to justify the technique.

| Signal | Values |
| --- | --- |
| Verdict band | conclusive, ambiguous, insufficient, not analysed |
| Quality verdict | ok, advisory, blocking, unvalidated |
| Connectivity | online, offline |
| Cached tips | present, absent |
| Tips status | grounded, abstained, never generated |
| Sources | present, absent |
| Location | resolved, unavailable |
| Record age | fresh (just captured), historical |
| History size | empty, non-empty |

The current details screen renders a nearly fixed layout across all of these,
with a handful of `if` statements scattered through four widget files. The
composition is already conditional; it is simply implicit, untested and
inconsistent between screens.

## 3. Component registry

Fixed, compiled, closed. Nothing outside this list can appear in a composed
result surface.

| Component | Purpose |
| --- | --- |
| `VerdictHeader` | The conclusion, or the statement that there is none |
| `AlternativesPair` | Two candidates with scores |
| `TextureScale` | The five-step ramp with zero, one or two highlights |
| `QualityNotice` | A quality advisory or block reason |
| `InfoTile` | A labelled attribute — location, timestamp, confidence detail |
| `TipCard` | One advisory tip with its citations |
| `SourcesList` | Numbered sources |
| `DisclaimerBanner` | The standing limit statement |
| `OfflineNotice` | What is unavailable without a connection |
| `EmptyState` | Nothing to show, with the reason |
| `NextActionBar` | Up to one primary action and any secondaries |

## 4. Composition

A pure function:

```dart
List<Slot> compose(ResultContext context);
```

`ResultContext` is the signal set from §2. `Slot` names a registry component
plus its data. The function has no side effects, no I/O and no randomness, so
the full cross-product of contexts can be enumerated in tests and asserted
against golden layouts.

### 4.1 Invariants

These are what prevent an incoherent layout. Each is a test.

1. Exactly one `VerdictHeader`, and it is always first.
2. `AlternativesPair` appears if and only if the verdict is ambiguous.
3. `TipCard` never appears without `DisclaimerBanner` in the same composition.
4. No soil-scale colour appears unless the verdict is conclusive.
5. `NextActionBar` is always last and carries at most one primary action.
6. `SourcesList` appears if and only if at least one `TipCard` cites a source.
7. **Generated content occupies slots; it never selects them.** No field of any
   agent response is an input to `compose`. The only agent-derived inputs are
   *presence* and *status* — whether tips exist, and whether the agent grounded
   or abstained — never their text.

Invariant 7 is the structural separation between generated content and
interaction structure that the brief asks for. It is enforced by type: the
signature of `ResultContext` simply has no field carrying tip text.

### 4.2 Contextual next actions

The clearest functional payoff, and the thing a fixed layout does badly today:

| Context | Primary action |
| --- | --- |
| Ambiguous verdict | Refazer a captura |
| Insufficient evidence | Refazer a captura |
| Conclusive, fresh, unsaved | Salvar registro |
| Conclusive, saved, online, no tips | Gerar dicas de manejo |
| Conclusive, saved, offline, no tips | Salvar e gerar depois |
| Conclusive, saved, tips cached and stale | Atualizar dicas |
| Not analysed, model unavailable | — none; secondaries only |

Today the details screen offers Share and Delete in every one of these states,
and the tips action is buried inside a section.

### 4.3 Fallback

An unrecognised or incomplete context composes a minimum fixed layout:
`VerdictHeader` in its not-analysed form, the available `InfoTile`s, and a
`NextActionBar` with secondaries only. Never an empty screen, never a partial
render, never a thrown exception reaching the widget tree.

## 5. What this does not do

- It does not generate text. All text is either compiled copy or agent output
  that already exists and is already cited.
- It does not call a model to lay anything out.
- It does not vary between runs. The same context always composes the same
  layout, which is what makes it testable and what makes support tractable.
- It does not extend beyond the result surface. Home, history and settings stay
  as written; composing them would be technique in search of a problem.

## 6. The server-driven gate

Recorded, not planned. If it is ever reconsidered, all of the following must
exist first:

- A versioned schema with a closed component whitelist, rejecting any unknown
  component rather than skipping it.
- A validator running before any widget is built, with a size ceiling on the
  document and on every field.
- Text sanitisation at the boundary, with the ADR 0001 rule intact: fetched
  content is data, never instruction.
- Offline behaviour: the last valid document cached, and the deterministic
  `compose` from §4 as the fallback when none is available.
- Accessibility guarantees that survive an arbitrary document — required
  semantic labels in the schema itself, not optional ones.
- The invariants in §4.1 enforced against the received document, not merely
  against locally composed ones.

Absent any of those, the answer is no.

## 7. Acceptance criteria

- `compose_is_pure` — identical contexts produce identical slot lists.
- `invariants_hold_across_cross_product` — every enumerated context satisfies
  all seven invariants.
- `no_generated_text_in_context` — `ResultContext` exposes no field carrying
  agent-produced text, asserted structurally.
- `fallback_never_empty` — an unrecognised context composes the minimum layout.
- `contextual_primary_action` — each row of the table in §4.2 produces its
  stated primary action.
