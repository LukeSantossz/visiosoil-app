# Evaluation is repeated stratified group k-fold with nested selection, and uncertainty is never the spread across folds

Every reported number for the classifier comes from repeated (R = 5), stratified,
group-aware k-fold cross-validation (k = 5) over the splittable sample groups,
with every selection — checkpoint, hyper-parameter, encoder, threshold — nested
inside the fold's own training side. The unit of every interval and every paired
contrast is the physical sample group. Uncertainty is reported as the spread
across repeats together with a parametric reference (Wilson interval; exact
McNemar with its minimum detectable effect), and the standard error across folds
is not reported as uncertainty anywhere.

This **reverses the split design recorded in
[SPEC 0033](../specs/0033-dataset-protocol-manifest-and-splits.md)** — one
seeded `train`/`val`/`test` partition — which was fixed before any image existed
and before the sample count was known. SPEC 0033 keeps every other decision it
took; only the evaluation design moves.

## Status

Accepted 2026-09-01, promoted from
[SPEC 0042](../specs/0042-repeated-group-k-fold-evaluation-protocol.md) at the
Spec Gate.

## Context

The archive holds 105 sample groups over 221 photographs; four classes and the
train-only rule of SPEC 0040 D6 leave 77 groups that can be tested. At
`test_split = 0.15` that is about twelve groups — a 95 % interval near ±28 pp on
accuracy and a paired minimum detectable effect near 40 pp (planning estimates,
issue #203). No experiment the roadmap plans can return a verdict under that
resolution, and E0, the programme's go/no-go, is one of them.

Two published results fix the shape of the answer. Varoquaux (2018, *NeuroImage*
180:68–77) shows that at N ≈ 100 the interval on a cross-validated accuracy is
about ±10 pp and that the spread across folds understates it badly. Vabalas et
al. (2019, *PLOS ONE* 14:e0224365) show that k-fold with selection inside the
loop is optimistically biased at small N, that nested cross-validation is not,
and that nesting the choice of features or representation matters more than
nesting hyper-parameters — which is precisely the choice E0 makes between arms.

The dataset is closed (ADR 0016, amended 2026-09-01): more groups will not
arrive. The only lever on the evaluation set is to test every eligible group,
which k-fold does and a single split cannot.

## Decided

- **k = 5, R = 5.** Roughly 15 test groups per fold; Argilosa, the binding class
  at 16 splittable groups, keeps 3–4 per fold. Every repeat re-draws the folds
  from a seed derived from `data.seed`, so the spread across repeats measures
  training and fold-assignment variance.
- **Nested selection, audited.** Anything chosen for outer fold *i* is chosen on
  inner folds of *i*'s training side, the group ids read during selection are
  logged, and a test asserts the log never touches *i*'s test groups. The model
  scored on fold *i* is refitted on all of *i*'s training groups with the chosen
  setting.
- **The group is the unit.** Photograph-level macro-F1 is the deployment-faithful
  primary number; group-level predictions (mean of a group's photograph
  distributions, argmaxed) carry every interval and every paired contrast,
  because photographs of one sample are not independent.
- **Contrasts are pre-registered** in configuration before a run: each arm
  against the shuffled-label control as the primary family, one named
  secondary, Holm-corrected. A contrast not registered is refused.
- **The minimum detectable effect is a recorded output**, computed from the
  observed discordance of each contrast, so every difference is read beside
  what the data could have shown.
- **Group B stays train-only in every fold**, at the Developer's direction of
  2026-09-01, so the evaluation pool is 77 groups and not 102.
- **The single-split path is removed**, not kept beside the new one.

## Considered Options

- **Single split with an interval** — rejected; the interval is the finding, and
  it says no measurement was made.
- **Leave-one-group-out** — rejected as the default (77 trainings per arm per
  repeat, no stratification, higher-variance estimator); permitted per arm for
  descriptor arms if every arm in a contrast shares the folds.
- **k = 10** — rejected; one or two Argilosa groups per fold and double the
  cost for the same 77-group pool.
- **Standard error across folds as the uncertainty** — rejected on Varoquaux
  (2018); this is the error the decision exists to remove.
- **Cluster bootstrap over pooled predictions as the sole interval** — rejected
  as sole; it sees one model per fold and nothing of training variance.
- **Un-nested selection** — rejected on Vabalas et al. (2019).
- **Group B in the test sides** — rejected by the Developer; it is 68 %
  Argilosa and 0 % Muito Argilosa, and a test set holding it scores compression.
- **Two code paths** — rejected on SPEC 0034's precedent.

## Consequences

- Every number produced before this decision — there are none on real data —
  and every number produced after it are comparable only under this protocol.
  A result reported from a single split is not a VisioSoil result.
- A deep-learning arm costs 25 refits plus inner selection per experiment, on
  CPU. That cost is recorded in `metrics.json`; R is reduced before k if it must
  be, and the reduction is recorded.
- The paired MDE at 77 groups is expected near 15–20 pp (estimate). The
  protocol makes that visible and cannot make it small: an arm that wins by less
  has not been shown to win, and the E0 decision rule in SPEC 0044 is written on
  that basis.
- #203's acceptance criteria are met by SPEC 0042; #183's estimated MDE table is
  superseded by the recorded value.
- Calibration and conformal bands (#187, #193) consume this protocol's inner
  folds; they are specified after it, not inside it.
- This record is superseded, not amended, if a populated site axis ever makes a
  site-held-out protocol the honest default.
