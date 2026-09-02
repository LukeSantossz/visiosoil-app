# SPEC: chore(ml): decide whether textural class is visually determinable, by a four-arm pre-registered gate

## Problem

Nothing in this programme has ever measured whether Embrapa textural class is recoverable at all from a smartphone photograph of a soil dish, so every scheduled item after it — patch tuning, calibration, quantization, the release path — is being built on a premise no number has tested.

## Design Decision

E0 is a **pre-registered four-arm comparison run under the protocol of [SPEC 0042](0042-repeated-group-k-fold-evaluation-protocol.md) and [ADR 0020](../adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md)**: a shuffled-label control, the incumbent MobileNetV2 whole-frame baseline, classical texture descriptors on the physical-size greyscale patches of [ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md), and a frozen public encoder with a linear probe. All four are evaluated on the **same folds**, at k = 5 and R = 5, with selection nested inside each fold's training side, and every contrast is registered in `ml/config.yaml` **before the first run**.

The gate answers two questions in one experiment, and they are separate. **Was signal demonstrated?** — every arm is compared against the shuffled-label control, as the primary family. If no arm clears the control, the honest statement is that **signal was not demonstrated at this experiment's pre-registered resolution**, not that no signal exists: at 77 groups the resolution is coarse, and failing to reject a null is not evidence for it. The operational consequence is unchanged and deliberate — **Lane C stops** — because a programme cannot be built on an effect its own best measurement could not find; what changes is what the record is allowed to claim. **Which method ships?** — the frozen encoder is the challenger and the descriptor path is the default, decided by one named secondary contrast under a rule fixed here rather than after the numbers are seen.

**The decision rule, pre-registered as a predicate rather than a sentiment.** The frozen-encoder path ships only if **all four** conditions hold, each recorded as met or not met by name:

1. **Executed.** The encoder arm ran to completion over all 5 repeats and 5 folds, on the same fold manifest as every other arm. An arm that could not be run is *not executed*, which is its own recorded outcome and is never reported as having lost a comparison.
2. **Won the secondary contrast.** On the registered secondary contrast `encoder_probe` against `descriptors`, computed on **group-level** predictions per ADR 0020: the exact McNemar test is significant at `evaluation.alpha` after Holm correction **within the secondary family**, the sign favours `encoder_probe`, **and** the observed group-level accuracy difference is at least the minimum detectable effect that same contrast records in `metrics.json`. All three clauses, so a significant result smaller than the measurement's own resolution does not count as a win.
3. **Fast enough.** It passes the on-device latency gate on the reference device — mid-range Android, at least 4 GB of RAM (#215) — against the budget that gate declares.
4. **Amendments accepted.** The Developer accepts the record amendments adoption forces: SPEC 0037's MobileNetV2 input-size acceptance criterion, ADR 0018's input-size rationale, and [ADR 0012](../adr/0012-released-model-artifact-tracked-in-git.md)'s artifact-size consequence.

**If any of the four fails, the descriptor path ships.** The four are kept apart because they fail for different reasons and must be auditable separately: an encoder that no available hardware can run fails condition 1, and recording that as a lost comparison or as a refused amendment would put a conclusion in the record that the experiment never reached.

At 77 splittable groups the planning estimate for the paired minimum detectable effect is about 16 percentage points, so this rule is written expecting condition 2 to fail and the default to stand. That is the point of fixing it now: the same numbers must yield the same ship decision whoever reads them.

This spec specifies and runs the gate. It does **not** adopt a method: the adoption decision is an ADR written after the verdict, against the numbers, because an ADR written now would be recording a conclusion the experiment has not reached.

## Alternatives Considered

- **Run only the incumbent MobileNetV2 arm against the control.** Rejected. That answers "is there signal" and nothing else, and leaves the method choice — the expensive, hard-to-reverse decision — to be made later on no evidence. The marginal cost of the descriptor arm is small: it needs no GPU and trains in seconds per fold, which is why it can afford the full 5 by 5.
- **Run the frozen encoder alone, as the recommended method.** Rejected, and this reverses the study's first recommendation. Adopting the encoder amends three approved records, and at this N the secondary contrast most likely cannot rank it against the descriptors, so the amendments would be paid for a difference that was never demonstrated. It stays as a challenger that must earn adoption.
- **Drop the shuffled-label control and read the arms against chance (0.25).** Rejected. Chance is not the floor here: the folds are stratified but unbalanced, the groups are few, and a model can exploit class priors and capture artefacts without seeing texture at all. The control holds all of that constant and permutes only the label, which is the only comparison that isolates the question.
- **Decide the method on whichever arm has the higher pooled macro-F1.** Rejected. It reads a difference smaller than the measurement's resolution as a result, which is the failure the recorded minimum detectable effect exists to prevent.
- **Add #204's sample-identity contrastive pretraining as a fifth arm.** Rejected for this gate, and deferred rather than refused. It is a fifth training pipeline at 5 by 5 folds with a cost nobody has estimated, and registering it now would spend the correction budget of the primary family on an arm that is not ready. It is registrable in a later spec once its cost is measured.
- **Report per-class accuracy so the weak classes are visible.** Rejected as a headline. The pooled test count per class is small enough that a per-class figure moves by tens of points on one group, so per-class numbers are computed and written with `"headline": false` — the key `src.evaluate` actually writes, which SPEC 0042's prose calls `not_headline` — and never quoted as the result.
- **Wait for more data before running the gate.** Rejected: there is no more data. [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md) closed the dataset at the delivered archive, and the collection premise was withdrawn in SPEC 0041. The gate runs on what exists or it does not run.

## Scope

- Includes:
  - `ml/config.yaml` — register the four arm names and the contrasts under `evaluation.contrasts`: three `primary` entries, each arm against `shuffled_control`, and exactly one `secondary`, `encoder_probe` against `descriptors`.
  - `ml/src/` — the two arms that do not exist: a classical-descriptor arm over the SPEC 0037 patches, and a frozen-encoder-plus-linear-probe arm. Both consume the same fold manifest and write the same per-fold artifacts as the incumbent arm.
  - An ablation over the descriptor arm's components, reported as part of the verdict, because "what carries the signal" is the diagnostic this arm exists to give.
  - `docs/ml/e0-verdict.md` (new) — the committed verdict, naming the numbers, the seeds, the dataset version, the manifest digest and the library versions, written whichever way the gate returns.
  - `ml/tests/` — one test per acceptance criterion below.
- Does NOT include:
  - Adopting a method. The adoption ADR is written after the verdict and is not this spec.
  - Implementing the prerequisites: A8 (#211), A0 (#212), A1 (#214), A4 (SPEC 0037's patch pipeline), A9 (#215), or #179. Each is its own change, and this gate cannot run until they land.
  - #204's contrastive-pretraining arm.
  - Calibration, conformal bands, or verdict thresholds (#187, #193).
  - Any change under `lib/`. Nothing in the app changes on the strength of this gate.
  - Quantization or export of any arm's model.

## Acceptance Criteria

- contrasts_are_registered_before_the_first_run: `ml/config.yaml` carries four arm names and four contrasts — three `primary` against `shuffled_control` and exactly one `secondary` — and `load_config` accepts them.
- unregistered_contrast_is_refused_by_name: a comparison between two arms with no registered entry fails, naming the pair, rather than being computed on request.
- every_arm_reads_the_same_fold_manifest: all four arms load the fold manifest through `load_folds_for_config`, so an arm run against another dataset version or another manifest digest is refused rather than pooled.
- descriptor_arm_trains_without_a_gpu: the descriptor arm completes one fold on CPU, and its recorded per-fold cost is written to the fold's `cost.json` like every other arm's.
- descriptor_ablation_names_each_component_contribution: the verdict reports the descriptor arm with each component group removed in turn, over the same folds.
- encoder_arm_probe_is_selected_inside_the_fold: the probe's hyper-parameters are chosen on the inner folds only, and the selection audit's intersection with the fold's test groups is empty.
- every_arm_is_contrasted_against_the_shuffled_control: `metrics.json` carries, for each of the three real arms, the group-level McNemar statistic against the control, Holm-corrected within the primary family.
- minimum_detectable_effect_is_reported_for_every_contrast: each contrast records the minimum detectable effect computed from its own observed discordance, and no difference below it is described as a difference.
- verdict_states_each_decision_rule_condition_by_name: the verdict document records each of the four encoder-adoption conditions as met or not met, with the evidence for each, and states which path ships.
- an_arm_that_did_not_run_is_not_recorded_as_having_lost: an arm absent from `metrics.json` is reported as not executed, and no contrast is computed for it.
- verdict_is_committed_whichever_way_it_returns: the verdict document is committed with its numbers, the seeds, the dataset version, the manifest digest and the library versions, including when no arm clears the control.
- no_per_class_figure_is_a_headline: per-class metrics are present in `metrics.json` carrying `"headline": false`, and the verdict quotes none of them as the result.
- negative_verdict_blocks_lane_c: if no arm clears the control, the verdict states that signal was not demonstrated at this resolution rather than that none exists, and records that no Lane C item starts before this spec is revisited.

## Reproducibility

```sh
cd ml
python -m src.crossval --shuffled-control
python -m src.crossval --arm cnn
python -m src.crossval --arm descriptors
python -m src.crossval --arm encoder_probe
python -m src.evaluate --contrasts
```

`--shuffled-control` and not `--arm shuffled_control`: the flag is what permutes the labels, and the arm name is derived from it by `default_arm_name`. Naming the arm without the flag produces a directory called `shuffled_control` holding an unpermuted run — a control that is not one, with nothing in the artifacts to say so.

Seeds are `data.seed` derived per repeat by `derive_repeat_seed`, and the shuffled control's permutation seed is offset so it cannot coincide with the fold draw; both are recorded per fold. The dataset version is `v1` and the manifest digest is written into every fold manifest. Library versions are recorded per fold in `runtime.json`, because the fold assignment is a function of the scikit-learn version as well as of the seed. The environment is the pinned `ml/requirements.txt` on Python 3.12 (A1, #214); no result produced under another stack is comparable.

## Risks and Assumptions

- **Assumption: 77 splittable groups is enough to answer "is there signal", and probably not enough to rank two methods.** The planning estimate for the paired minimum detectable effect is about 16 percentage points. This spec is written for that outcome: the primary family is the question the N can answer, and the secondary contrast is expected to be unresolvable, which is why the default is fixed in advance rather than chosen from the result.
- **Assumption: the descriptor arm is cheap enough to run at 5 by 5 and to ablate.** If it is not, the ablation is what gets cut, not the repeats — the variance denominator is what makes every other number readable.
- **Assumption: the frozen encoder can be run at all on the available hardware.** There is no local GPU. If encoder inference over 25 patches per photograph is not feasible in the available environment, the encoder arm is recorded as **not executed** — condition 1 of the decision rule — and the descriptor path ships on that ground and no other. It is not recorded as having lost a comparison it never entered.
- **Risk: the gate returns negative and the programme stops.** That is the gate working. The verdict is committed either way, and a negative result with its numbers is worth more than an unmeasured premise.
- **Risk: the prerequisites move.** This spec cannot run until A8, A0, A1, A4, A9 and #179 land. If any of them changes the patch geometry or the class list, the folds are regenerated and every arm is rerun; a result pooled across two fold manifests is refused by construction, which is what stops that from happening silently.
- **What would invalidate this spec:** a change to the evaluation protocol itself (SPEC 0042 / ADR 0020), a change to the class list beyond A8's four, or the arrival of data — none of which is expected, the last least of all.
