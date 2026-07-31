# Incremental Plan and Acceptance Criteria

## 1. Sequencing principle

Ordered by cost to the user, not by cost to build: field-decision risk first,
then access, then friction on the primary flow, then system debt. Two
departures from strict impact order, both deliberate and both stated below.

Each row becomes one spec under `docs/specs/NNNN-<slug>.md` and passes its own
Spec Gate. Numbers here are sequence positions, not spec numbers. **0030 is
taken** — the vision terminal's soil image acceptance criteria — so the next
available number is 0031.

## 2. The sequence

| # | Spec | Closes | Depends on |
| --- | --- | --- | --- |
| 1 | Confidence contract and verdict bands | P0-1, P0-2, P2-5 | — |
| 2 | Result presentation and the texture scale | P0-1 | 1 |
| 3 | Accessibility baseline | P0-4, P2-8 | — |
| 4 | Permission priming and onboarding relocation | P0-3 | — |
| 5 | Capture flow without the dead screen | P1-1 | 4; the §3 decision below |
| 6 | Wire the quality gate into the capture flow | P1-2 | 5; **SPEC 0030** |
| 7 | Named processing phases, Save ungated from location | P1-4 | 1, 6 |
| 8 | Connectivity and sync made visible | P1-3 | — |
| 9 | State consolidation and missing design-system components | P2-1, P2-2, P2-4, P2-6 | 2 |
| 10 | Details and preview information architecture | P2-3 | 9 |
| 11 | Dark theme and high-contrast mode | P2-7 | 3, 9 |
| 12 | Microinteractions and haptics | — | 3, 9 |
| 13 | GenUI composition layer | — | 2, 6, 8 |
| 14 | Phase 2: in-app viewfinder | — | 6, 13 |
| 15 | Persist the distribution (migration v4 → v5) | — | 1 |

**Departure 1 — accessibility is third, not last.** It is a P0, and it is far
cheaper to apply before the new screens in specs 5 through 10 exist than to
retrofit afterwards. Placing it third also front-loads the shared widget changes
(`VisioIconButton`, the tappable wrapper) that later specs consume.

**Departure 2 — spec 15 is last despite depending only on spec 1.** It is a
schema migration, and it is sequenced after the interface work has stabilised so
the persisted shape is decided once. Until it lands, a record reopened from
history renders from its persisted top-1 alone, so a verdict that was ambiguous
at capture time reappears as a plain low-confidence reading; specs 1 and 2 must
state that limitation in their own acceptance criteria rather than let it pass
silently.

## 3. What blocks what, externally

| Blocker | Blocks | Owner |
| --- | --- | --- |
| No `.tflite` artifact | Real validation of specs 1, 2, 6, 7 | ML terminal |
| No published validation metrics | Threshold calibration in specs 1 and 6 | ML terminal |
| No real images to calibrate against | The provisional thresholds in SPEC 0030, consumed by spec 6 | ML terminal |
| No `TargetSignal` producer | The dormant states in spec 6 | Vision terminal — **deferred by ADR 0009**, not merely absent |
| Recommendation contract divergence | Any structured recommendation UI | Research agent terminal, jointly |
| `researchServiceProvider` returns `UnavailableResearchService` | End-to-end validation of spec 13 | Research agent terminal, issue #95 |

None of these blocks the specs from being written or the interfaces from being
built against the contracts as they stand. They block *validation*, and each
spec must state which of its acceptance criteria can only be verified once the
blocker lifts.

### 3.1 Cross-terminal decisions that must be taken first

Unlike the blockers above, these are not waiting on artifacts. They are waiting
on a decision, and taking them late is more expensive than taking them now.

| Decision | Blocks | Recorded in |
| --- | --- | --- |
| **The capture guide drops the coin and the 70 % fill** that the dataset is collected under. Adopting the design system's four-step guide would delete two protocol rules from the only place the user reads them, reopening the gap ADR 0009 exists to close | Spec 5 | `06-capture-experience.md` §2.1 |
| **Applying the ROI crop in both `ml/src/preprocess.py` and `inference_service.dart`.** SPEC 0030 defines the crop and deliberately does not apply it; until a follow-up applies it in both places together, both still squash the aspect ratio, and the framing guide in spec 14 would describe a region that is not what gets classified | Spec 14, and any preprocessing change | SPEC 0030, Scope |
| **Where quality flags live on `SoilRecord`.** SPEC 0030 excludes persisting them; ADR 0009 requires the record to store which criteria failed. The column is this terminal's to add | Spec 6 | `06-capture-experience.md` §2.3 |
| **Recommendation section structure** — extend `ManagementTip` with a closed `category` enum, or retire the design system's `RecommendationScreen` | Spec 13 | `05-design-system.md` §5 |

## 4. Acceptance criteria by screen

Criteria are stated in the repository's established form: a lowercase
identifier, then a verifiable statement. They are the input to each spec's own
criteria section, not a substitute for it.

### Splash

- `no_cold_permission_request` — the splash requests no permission.
- `boot_failure_is_recoverable` — a storage or database failure routes to a
  retryable error screen rather than remaining on the logo.

### Onboarding

- `onboarding_states_value_first` — the first step describes what the product
  gives the user, not how to hold the phone.
- `permission_priming_precedes_system_dialog` — the camera permission rationale
  is shown before the system dialog, and location is presented as optional.
- `capture_technique_removed` — framing, lighting and angle content no longer
  appears here; it lives in the capture guide.

### Home

- `record_row_is_accessible` — the last-analysis row is a labelled, ink-responsive
  target of at least 48 dp that merges its children into one semantic node.
- `confidence_chip_carries_band` — the chip shows the verdict band, with the
  percentage as secondary detail, and shows no soil-scale colour for a
  non-conclusive record.
- `home_scales_to_200_percent` — the greeting, hero card and stat cards render
  without clipping at 200 % text scale.

### Capture guide

- `guide_shown_before_first_camera` — appears before the first camera launch and
  not on subsequent ones.
- `guide_reachable_on_demand` — a "Como capturar" affordance on the analysis
  screen opens it.
- `guide_copy_matches_capability` — step 4 does not promise an on-screen framing
  guide until phase 2 ships it.
- `guide_matches_roi` — any framing guidance describes the largest centred
  square, matching SPEC 0030's region of interest.
- `protocol_rules_are_not_silently_dropped` — the guide states every rule the
  dataset is collected under, or the collection protocol was changed by a
  recorded joint decision.

### Analysis (`/capture`)

- `no_empty_capture_screen` — the route never renders without an image.
- `no_gallery_copy` — no string implies selection from a gallery.
- `phases_are_named` — a named phase is shown and changes when the phase does.
- `quality_gates_classification` — a blocking quality verdict prevents
  classification from starting.
- `quality_blocks_name_every_defect` — a block lists every failing criterion from
  the report, not the first, and offers both retake and record-anyway.
- `quality_failure_is_not_a_block` — an `unvalidated` verdict lets classification
  run, with the advisory that the check did not run.
- `quality_flags_persist` — a record saved through the override stores which
  criteria failed, and reopening it shows them.
- `save_not_gated_by_location` — with classification settled and location
  pending, Save is enabled and the record persists with null coordinates.
- `timeout_distinguished_from_failure` — a timeout and an error produce
  different messages.
- `unavailable_offers_no_retry` — with no model artifact, the state reads as
  not analysed and offers no retry.
- `processing_is_cancellable` — cancelling leaves no orphaned isolate.
- `phase_changes_announced` — transitions and verdict arrival are announced to
  assistive technology.

### Result surface (analysis and details)

- `verdict_conclusive` — high top-1 with a wide margin renders the class, its
  scale colour, the badge and the standing limit line.
- `verdict_ambiguous` — a narrow margin renders both candidates, neither
  asserted, both highlighted on the texture scale, with retake as primary.
- `verdict_insufficient_asserts_nothing` — below the floor: no class name, no
  soil-scale colour, no headline percentage; offers retake and
  record-without-class.
- `unclassified_is_not_low_confidence` — a record with no score renders as not
  analysed, visually distinct from insufficient evidence.
- `insufficient_is_not_error_coloured` — the insufficient state uses no `error`
  role colour.
- `no_causal_claim_without_signal` — retake guidance names lighting or framing
  only when the quality gate flagged them.
- `conclusive_states_its_limits` — a high-confidence result still carries the
  limit statement.

### Details

- `hero_opens_viewer` — tapping the hero image opens the full-screen viewer.
- `tips_never_without_disclaimer` — no tip renders without the disclaimer.
- `abstention_is_not_an_error` — an agent abstention renders as an informational
  state, not an error state.
- `destructive_separated` — Delete is not within 24 dp of a primary action.

### Photo viewer (`/preview`)

- `viewer_is_photo_only` — the viewer renders the photograph, a labelled close
  affordance and nothing else.
- `viewer_has_no_duplicate_info` — no timestamp, location or classification
  appears in the viewer.

### History

- `card_shows_class_and_confidence` — each card shows the texture class and the
  verdict band, not only a timestamp.
- `card_is_labelled` — each thumbnail carries a derived semantic label.
- `selection_has_non_gesture_entry` — selection mode is reachable without a long
  press.
- `cap_is_disclosed` — when the 150-record cap truncates results, the interface
  says so.
- `tap_opens_details` — a card opens details, not the photo viewer.

### Settings

- `destructive_is_visually_distinct` — "Apagar todos os dados" is not in the same
  visual family as non-destructive tiles.

### Cross-cutting

- `one_error_presentation` — all recoverable errors use one component; the black
  canvas variants are gone.
- `one_loading_presentation` — no raw `CircularProgressIndicator` outside
  `LoadingIndicator`.
- `app_bar_is_shared` — every screen with an app bar uses `VisioAppBar`.
- `tokens_only` — no off-scale spacing, radius or colour literals in new or
  edited files.
- `token_contrast_verified` — the automated contrast test passes, with any
  accepted failure documented.
- `reduce_motion_zero_duration` — with animations disabled, no animation runs
  and no content is hidden.
- `analyze_clean_tests_green` — `flutter analyze` reports no issues and
  `flutter test` passes.

## 5. What this plan does not include

- Any change to model training, export, or the `ml/` pipeline.
- Any implementation of the research agent's internal architecture.
- Gallery image selection — the product is camera-only by design, permanently.
- Automatic capture, which is deferred within spec 14 until the live signals
  have been calibrated in the field.
- Localisation infrastructure; see `11-libraries.md` §4.
- Cloud sync itself. Spec 8 makes the existing sync state *visible*; it does not
  wire `SyncEngine` into the provider graph.
