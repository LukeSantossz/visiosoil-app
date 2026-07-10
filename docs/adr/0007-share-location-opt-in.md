# Share location is opt-in, omitted by default: precise coordinates disclosed only on an explicit per-share choice

VisioSoil no longer includes a record's precise GPS coordinates or street-level
address in shared content by default. `ShareContentBuilder.caption` and
`composeCard`, and `ShareService.shareRecord`, gate the `Local:` and
`Coordenadas:` lines behind an `includeLocation` flag (default `false`);
`composeCard` forwards the flag to `caption`, so both the share text and the
visible card footer omit location unless the user opts in. The details share
action presents a per-share dialog defaulting to "share without location". The
re-rendered card image remains EXIF-free regardless.

## Status

Accepted. Implemented under issue #112 (SPEC `docs/specs/0005-share-location-opt-in.md`
approved at the Spec Gate). Prompted by the 2026-07-03 security audit as a
privacy-by-design gap (not a code bug). Part of the App Correctness & UX
milestone (M3).

### Decided
- **Default omit, per-share opt-in** — preserves the legitimate agronomic use (sending a colleague the sample's location) while defaulting to non-disclosure of a client's field coordinates.
- **Gate location in the single content builder** — `caption` is the one source of the metadata lines; `composeCard` forwards the flag, so the share text and the card footer never disagree.
- **No global preference** — the choice is made per share, so disclosing a location is always a deliberate act rather than a persisted default that can be forgotten.

## Considered Options
- **Coarsen coordinates to ~1 km** — rejected: still discloses an approximate client location without consent.
- **Omit location entirely (no opt-in)** — rejected: removes the legitimate use of sharing the sample's location with a colleague.
- **Keep the default-include status quo** — rejected: silently discloses a client's exact field location to every downstream recipient.
- **Default-omit with per-share opt-in (chosen)**.

## Consequences
- A default share of a soil card no longer leaks a client's field location; recipients see coordinates or address only when the sender explicitly opted in for that share.
- The card footer no longer shows the location by default — previously a visible disclosure separate from (and unaddressed by) the EXIF-free card rendering.
- The posture is reversible per share; a remembered "always include" preference could be layered on later without changing the default-omit stance.
