# VisioSoil UX Evolution Dossier — Index

## What this is

A diagnosis of the VisioSoil mobile experience as it exists today, a target
design for the capture → classification → recommendation journey, and an
incremental plan that decomposes the work into individually gated specs.

This dossier is **not** a spec. It authors no acceptance criteria that anyone
may implement directly. Every implementable slice leaves here as an entry in
[`13-roadmap.md`](13-roadmap.md) and must pass its own Spec Gate under
`docs/specs/NNNN-<slug>.md` per `.standards/docs/standards/spec_method.md`
before any code is written.

## Scope of this terminal

This terminal owns the mobile experience: interface, interaction,
accessibility, the design system, and GenUI planning. It does not alter model
training and does not implement the research agent's internal architecture. It
consumes the contracts those terminals produce, and where a contract does not
yet exist it proposes a provisional interface that is **explicitly marked as a
hypothesis**.

## Reading map

| Document | Contents |
| --- | --- |
| [`01-current-state.md`](01-current-state.md) | Stack, screen and component inventory, screen-by-screen audit |
| [`02-user-journey.md`](02-user-journey.md) | Journey map, the nineteen states, primary and alternative flows |
| [`03-problems.md`](03-problems.md) | Problems ranked by impact, with evidence |
| [`04-information-architecture.md`](04-information-architecture.md) | Navigation model, entity hierarchy, the two structural fixes |
| [`05-design-system.md`](05-design-system.md) | Source-of-truth split, token gaps, component gaps, content rules |
| [`06-capture-experience.md`](06-capture-experience.md) | Assisted capture, phase 1 and phase 2 |
| [`07-processing-states.md`](07-processing-states.md) | Named processing phases, timeouts, cancellation |
| [`08-results-and-uncertainty.md`](08-results-and-uncertainty.md) | Verdict bands, alternatives, abstention, presentation rules |
| [`09-microinteractions.md`](09-microinteractions.md) | Motion and haptics strategy |
| [`10-genui-strategy.md`](10-genui-strategy.md) | Deterministic adaptive composition, invariants, the server-driven gate |
| [`11-libraries.md`](11-libraries.md) | Dependency evaluations, including the rejections |
| [`12-accessibility.md`](12-accessibility.md) | Criteria, current violations, per-component obligations |
| [`13-roadmap.md`](13-roadmap.md) | Spec sequence, per-screen acceptance criteria |

## Decisions taken before drafting

Four forks were settled with the product owner before this dossier was written.
They are recorded here because every document downstream depends on them.

1. **This engagement produces documents, not code.** The output is this dossier
   plus a queue of specs. No implementation happens under this effort.
2. **Assisted capture is phased.** Phase 1 delivers pre-capture guidance and
   post-capture quality validation on the still image, keeping `image_picker`.
   Phase 2 replaces it with an in-app viewfinder and live overlay, behind its
   own spec and its own quality contract.
3. **Uncertainty is exposed in full.** `InferenceService` will return the whole
   probability distribution. The app abstains when evidence is insufficient and
   shows both candidates when two classes are close.
4. **GenUI is deterministic.** The interface recomposes from local rules over a
   fixed, compiled component registry. No model chooses layout. Generated text
   enters slots; it never selects them.

## Dependencies on other terminals

| Dependency | Owner | Status | Consumed as |
| --- | --- | --- | --- |
| Class list and output order | ML terminal | Exists (`ml/config.yaml`) | Five classes, order `Arenosa, Media, Siltosa, Muito Argilosa, Argilosa` |
| Model artifact `soil_classifier.tflite` | ML terminal | **Absent** — `assets/models/` holds only `.gitkeep` | Until it lands, every classification resolves to *not analysed* |
| Per-class validation metrics | ML terminal | Not published | Needed to calibrate the verdict thresholds in `08-results-and-uncertainty.md`, which ship as hypotheses |
| Image quality signals (blur, exposure, target found, target count) | Vision terminal | **Does not exist** | Phase 1 derives blur and exposure in-app; *target found* and *multiple targets* are specified as hypothetical contracts and are deliberately **not simulated** |
| `ManagementTipsResult` shape | Research agent terminal | Exists (`lib/models/management_tips_result.dart`) | Flat `tips` + `citations` + `sources` |
| Structured recommendation sections | Research agent terminal | **Divergent** — the design system's `RecommendationScreen` assumes water/crops/preparation sections that the contract does not carry | Coordination item, see `05-design-system.md` |
| Proxy availability | Research agent terminal | `researchServiceProvider` returns `UnavailableResearchService` | Management tips always report unavailable today |

## Honesty boundaries

Three things this dossier refuses to design around, because designing them
would misrepresent what the system can do:

- **Target detection.** The classifier is single-label over the whole frame.
  There is no signal for "no target found" or "multiple targets". Their UI
  contracts are specified as hypotheses; no colour or histogram heuristic in
  the app may stand in for them.
- **Live frame quality.** Until phase 2, there is no frame to analyse before
  the shutter. All quality feedback is post-hoc.
- **Threshold calibration.** Every numeric threshold in this dossier is a
  starting hypothesis. None was derived from validation data, because none is
  published yet.
