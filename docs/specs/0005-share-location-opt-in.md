# SPEC: fix(share): make precise coordinates in share text an explicit opt-in

## Problem

Every share of a soil record embeds the record's precise GPS coordinates and
street-level address in both the share text and the visible card footer,
disclosing a client's exact field location to every downstream recipient without
the sender's explicit intent.

## Design Decision

Omit location (address and coordinates) from the shared content by default;
include it only when the user explicitly opts in, per share.
`ShareContentBuilder.caption` and `composeCard` gain an `includeLocation` flag
(default `false`) that gates the `Local:` and `Coordenadas:` lines; `composeCard`
forwards the flag to `caption`, so the card footer omits location just as the
text does. `ShareService.shareRecord` forwards the flag. In the details share
action, tapping "Compartilhar" on a record that has a location shows a dialog
offering "Compartilhar sem localização" (default) and "Incluir localização" (with
a one-line warning that the exact location becomes visible to recipients); a
record with no location shares directly with no dialog.

## Alternatives Considered

1. Coarsen coordinates to ~1 km by default — REJECTED: still discloses an
   approximate client location without consent and muddies the guarantee that
   the exact location is shared only on an explicit opt-in.
2. Omit location entirely, with no opt-in — REJECTED: removes the legitimate
   agronomic use of sending a colleague the sample's location; the chosen stance
   preserves it behind an explicit per-share choice.

## Scope

- Includes:
  - `includeLocation` flag (default `false`) on `ShareContentBuilder.caption` and
    `composeCard`, gating the address and coordinates lines; `composeCard`
    forwards it to `caption`.
  - `ShareService.shareRecord({bool includeLocation = false})` forwarding the
    flag to both `caption` and `composeCard`.
  - Details share action: a per-share opt-in dialog (default omit); direct share
    when the record has no location.
- Does NOT include:
  - Any change to the card image pipeline beyond the footer text (still
    EXIF-free).
  - A persistent/global "always include location" preference (per-share only).
  - Coarsening coordinate precision.

## Acceptance Criteria

- `caption_omits_location_by_default`: `caption(record)` for a record with an
  address and coordinates returns text without the `Local:` and `Coordenadas:`
  lines.
- `caption_includes_location_when_opted_in`: `caption(record,
  includeLocation: true)` includes both the `Local:` and `Coordenadas:` lines.
- `share_service_omits_location_by_default`: `shareRecord(record)` produces share
  text (and card footer) without location.
- `share_service_includes_location_when_opted_in`: `shareRecord(record,
  includeLocation: true)` produces share text with location.
- `details_share_prompts_opt_in_for_a_located_record`: tapping "Compartilhar" on
  a record with a location shows the opt-in dialog; choosing "sem localização"
  calls `shareRecord` with `includeLocation: false`.

## Reproducibility

`flutter test test/services/share_content_builder_test.dart
test/services/share_service_test.dart test/features/details/`; `flutter analyze`.
Deterministic, no randomness. Toolchain Flutter 3.44.1 / Dart 3.12.1.

## Risks and Assumptions

- Assumption: a per-share choice (not a global setting) is the right UX. If the
  dialog proves repetitive in practice, a remembered preference could be added
  later without changing this default-omit posture.
- Privacy posture: defaulting to non-disclosure is hard to walk back once records
  have circulated; promote to an ADR at the Gate as a durable stance.
