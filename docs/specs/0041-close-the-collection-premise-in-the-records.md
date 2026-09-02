# SPEC: docs(adr): close the collection premise in the records

## Problem

Three records still describe collection as available — ADR 0010 orders targeted
collection first and makes it a hard dependency, ADR 0016 presents the dataset
as rig time over material that already exists, and the collection protocol
describes a procedure to perform — and on 2026-09-01 the project owner closed
that route entirely, so each of them now argues from a premise that is false.

## Scope

- **Includes:** an amendment in ADR 0010's Status recording that collection is
  gone, that its condition 3 is withdrawn as a discriminator because a clause
  that can never fail is not a gate, and that the deferral now rests on the
  detectable-effect arithmetic in #183 instead; an amendment in ADR 0016's
  Status recording that the dataset is closed at 105 sample groups, that the
  samples cannot be re-photographed, and that soil collected elsewhere cannot be
  labelled; a withdrawal notice at the head of `docs/ml/collection-protocol.md`
  keeping the file for the three rules that outlived it and are cited from
  elsewhere.
- **Does NOT include:** any change to what the three records decide — the
  archive is still the dataset, generation is still deferred, Siltosa is still
  out of the first model; any new decision about what replaces collection, which
  belongs to #203, #204 and #183; any change under `ml/` or `lib/`; deleting the
  collection protocol, because a deleted document is one whose citations stop
  resolving; correcting the sample counts inside the protocol's body, which
  stays as approved with the correction stated in the notice at its head.

## Acceptance Criteria

- `adr_0010_status_records_that_collection_is_closed` — its Status names the
  date, says which of its own reasons no longer hold, and names the argument the
  decision now rests on instead.
- `adr_0010_consequence_no_longer_waits_for_a_trigger_that_cannot_fire` — the
  consequence reading "if field collection stalls, this ADR is what must be
  revisited" is marked superseded in place rather than deleted.
- `adr_0016_status_records_the_three_closed_options` — no further rig time, no
  re-photography, no labels for new soil, each with the reason it is closed.
- `adr_0016_decisions_are_unchanged` — the archive, the dish-rim scale and the
  Siltosa exclusion read exactly as they did.
- `collection_protocol_opens_with_a_withdrawal_notice` — it names what is
  withdrawn, what is kept and why, and states that its 194-sample figure predates
  the corrected inventory of 105.
- `mf_check_records_passes` — every amendment is in a Status section and no
  record's body is rewritten, so the archive still holds what was approved.
