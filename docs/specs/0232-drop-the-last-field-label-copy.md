# SPEC: fix(history): drop the last copy that names the field label

## Problem

The history search hint still offers the removed field label, and the privacy policy omits the true class stored since SPEC 0220.

## Design Decision

**Name only the address and sample in the history search hint, and describe the true class in the privacy policy.** The policy also states that field names entered in earlier app versions remain stored in the record.

## Alternatives Considered

- **Keep the search hint.** Rejected because history search no longer matches the field label.
- **Remove every mention of the field name from the policy.** Rejected because older records still retain it.

## Scope

- Includes: the search hint, one privacy-policy list item, and regression tests for both.
- Does NOT include: marking SPEC 0149 superseded or deciding whether `field_name` keeps syncing. Both are open decisions for the Developer, flagged on the Trello card; SPEC 0220 Risks keeps it syncing on purpose.

## Acceptance Criteria

- `search_hint_names_only_what_search_matches`: the visible hint names the address and sample, with no field label.
- `policy_names_the_true_class`: the policy contains `classe real` and omits the old field-and-sample sentence.
- Existing tests pass.

## Reproducibility

Flutter 3.44.1, Dart 3.12.1. Run `flutter test`, `flutter analyze`, and `mf check` from the repository root.

## Risks and Assumptions

- History search continues to match only the address or sample label, as SPEC 0220 defines.
- Legacy field names remain stored; this copy change does not change storage or syncing.
