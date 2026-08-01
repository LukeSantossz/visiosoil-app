# Model monitoring is local-first: aggregates stay on the device and no image, coordinate, or record is transmitted

VisioSoil monitors its classifier with counters computed and stored on the
device. Nothing is transmitted automatically. Sharing a diagnostics summary is
an explicit user action through the existing share flow, and the summary
contains only aggregates. Photographs, coordinates, addresses, and record
contents are never included in it, under any setting.

## Status

Accepted. Recorded during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §18). It answers the brief's
requirement to separate anonymous telemetry, technical metadata, and sensitive
data before any monitoring is built.

### Decided

Three tiers, with a different rule for each.

- **Tier 1 — anonymous aggregates.** Counts and distributions with no
  identifier and no per-record row: classifications by predicted class, verdict
  band distribution, `rejectedOod` rate, quality-flag frequency by criterion,
  `failed` rate split by cause, inference latency percentiles, and the model and
  dataset versions the counts belong to. Retained on the device, resettable by
  the user, shareable only by explicit action.
- **Tier 2 — technical metadata about one analysis.** Model version, dataset
  version, quality flags, inference milliseconds, status. This is written to the
  record row itself because the user needs it to interpret an old result. It
  travels wherever the record travels and nowhere else, which today is nowhere:
  `SyncEngine` and `RemoteSyncBackend` exist but are not wired into the provider
  graph.
- **Tier 3 — sensitive.** The photograph, the coordinates, the address, and the
  record as a whole. These never enter Tier 1, never leave the device as
  telemetry, and are governed by the decisions already in force: ADR 0005 strips
  EXIF at the storage boundary and ADR 0007 makes location sharing opt-in per
  share.
- **No automatic transmission in any tier.** There is no analytics SDK, no
  crash-reporter image attachment, and no background upload. A monitoring
  feature that ships a network client is a different decision and needs its own
  ADR.

### Not decided here

Whether images may later be contributed back to the training set. That is a
separate, per-record, explicitly consented act with its own consent copy and its
own storage decision, and it is out of scope. This ADR only forbids doing it
silently or in bulk.

## Considered Options

- **Server-side monitoring with sampled image upload** — rejected. It is the
  strongest drift detector available and it is also the one option the product
  cannot take: field photographs are the user's professional data, the app has
  no backend, and ADR 0008 already rejected cloud inference on the same
  reasoning. Adopting it would require a backend, a data-processing agreement,
  and a consent flow, none of which exist.
- **Anonymous telemetry over the network, aggregates only** — rejected for this
  phase, not on principle. It is defensible and it is what most products do. It
  is rejected because it requires a server that does not exist, and building one
  to receive counters that nobody is yet positioned to act on inverts the order
  of work. Revisit when a backend exists for sync.
- **No monitoring at all** — rejected. Without the rejection rate and the
  quality-flag distribution there is no signal that the deployment population
  has drifted away from the collection population, which §3 of the study
  identifies as the programme's main deployment risk.
- **Local-first aggregates (chosen).**

## Consequences

- Drift detection is delayed rather than absent, and its resolution is coarse.
  It arrives when a user chooses to share a summary. This is a real weakening
  and is accepted knowingly; the compensating signal is that the `rejectedOod`
  rate and the quality-flag frequency are themselves drift proxies and are
  visible to the user immediately, on their own device, without anyone
  collecting anything.
- The diagnostics summary is human-readable, because its only consumer is a
  person deciding whether to send it. A binary telemetry payload the user cannot
  inspect would contradict the consent model it depends on.
- Storage is bounded: aggregates are counters, not an event log, so retention
  does not grow with usage. No per-record telemetry rows are kept.
- The Tier 2 fields require a schema migration to store status, quality flags,
  and the model and dataset versions on `soil_records`. Schema is at v4; this is
  the v5 work item, and it collides with any other schema change, so it is
  coordinated before it is written.
- If a sync backend later lands, Tier 2 travels with the record by construction.
  That is intended, and it is why Tier 1 was defined as a separate store rather
  than as a query over records: a future sync must not turn monitoring into
  transmission as a side effect.
