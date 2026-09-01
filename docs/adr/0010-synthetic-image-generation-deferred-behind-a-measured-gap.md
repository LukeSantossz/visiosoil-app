# Synthetic image generation is deferred behind a measured gap: collection, corrected augmentation and compositing come first, and generative models only if an ablation proves a downstream gain

VisioSoil does not train or use a generative model (GAN, VAE, or diffusion) to
expand the soil texture dataset at this time. The dataset gap is addressed, in
order, by targeted collection, corrected traditional augmentation, and
compositing onto real backgrounds. A generative branch opens only when five
named conditions hold simultaneously, and closes unless an ablation on a
real-only test set shows a gain exceeding run-to-run variance.

## Status

Accepted, and re-checked on 2026-08-25 with a sixth condition added. Recorded
during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §6 to §11).

### Amended 2026-09-01: collection is gone, and the decision survives it on a different argument

The decision stands: no generator is trained. Two of the reasons it rests on do
not, because both assumed collection was available and it no longer is. The
project owner closed that route on 2026-09-01 — the delivered archive is the
whole dataset, and the laboratory takes no part in the project in any aspect.

**"Targeted collection first" is not a first step any more; it is not a step.**
It is listed below as the chosen option with the highest value per unit of
effort, and the Consequences say that if field collection stalls this record
must be revisited. Collection has not stalled — it is impossible. The ordering
this record imposes therefore has one fewer stage, and the first stage becomes
corrected augmentation over the photographs that exist.

**Condition 3 changes meaning rather than being satisfied.** It asks for a named
residual gap with a documented shortage of physical samples *and no near-term
collection path*. There is now no collection path at all, for any class, so the
clause is satisfied permanently and by circumstance rather than by evidence — a
condition that can never fail is not a gate. It is withdrawn as a discriminator,
and the weight it carried moves to condition 5.

**What now does the work is the arithmetic in #183.** Condition 5 requires a
downstream gain on a real-only test set that exceeds run-to-run variance, and
the binding constraint is not that variance but the test set's minimum
detectable effect. With the archive's real inventory — 105 sample groups, 77 of
them splittable across four classes — a single three-way split leaves two to
three groups per class, and no generative ablation can clear an effect floor
that large. The condition is arithmetically unsatisfiable, and that is a
stronger reason to defer than any of the five it was written beside. It also
does not go away if #203 replaces the split with cross-validation: k-fold
raises the effective evaluation set to 77 groups, which improves the floor
without coming close to what an ablation of this kind needs.

So generation stays deferred, on a reason that survives the loss of collection
rather than on one that depended on it.

**One figure in the body below is stale and is left standing.** The cGAN option
is rejected against "roughly 1400 declared images", which was the count
`ml/README.md` asserted when this record was written and which the archive audit
later found unverifiable. The real inventory is 105 sample groups over 221
photographs. The body is not edited, because an approved record's value is that
it holds what was decided at the time; the correction is here, where a reader
meets it first, and it makes that rejection stronger rather than weaker.

### Re-checked 2026-08-25: zero of five conditions hold

Not one of the five conditions below is satisfied. The first three are
sequential and the first of them now has data available, so the check is worth
recording rather than assuming: a real baseline has not been trained, corrected
augmentation and compositing have not been measured, and no residual gap has
been named because nothing has been run.

**Two developments could have reopened this and do not.**

The dry-to-wet gap has no collection remedy — re-wetting archive samples was
ruled out on 2026-08-25 — which makes it the kind of named, unclosable gap
condition 3 asks for. It is nevertheless not a case for generation. In greyscale
the dominant dry-to-wet difference is luminance, and brightness variation in
augmentation addresses it deterministically, without a generator and without any
risk to the label. Simulating wet soil from dry with a learned transform would
need paired dry-and-wet photographs of the same sample to fit, which is exactly
what cannot be produced.

The gaps this programme can now name are scale, background, illumination, the
camera pipeline and one thin class. **Four of the five are geometric or
photometric transformations of a photograph that exists**, which is the
territory where deterministic operations win outright — cheaper, exactly
label-preserving, and auditable in effect. The fifth is a sample-count
deficiency, and a generator trained on three images of a class memorises those
three, which the acceptance test in *Decided* forbids.

### Added 2026-08-25: a sixth condition

**The real-only test set must be large enough that the ablation's minimum
detectable effect falls below a delta declared in advance.**

Condition 5 requires a downstream gain "exceeding run-to-run variance". That is
the wrong denominator, and the error is worth naming because it makes the
condition read as satisfiable when it is not. Run-to-run variance is the
seed-reducible part and is the smaller of the two; the binding constraint is the
test set's detectable-effect floor. At the measured archive size — 191 samples
across four classes, roughly 29 in test — no augmentation change, loss swap,
backbone substitution or synthetic ratio moves a result by enough to be
distinguished from noise.

So condition 5 is not merely unmet today. **It is arithmetically unsatisfiable at
every dataset size this programme currently plans for**, which is a stronger
argument for deferral than any of the five reasons originally listed. Recorded
in #183, which carries the power arithmetic.

### Distinguishing simulation from generation

This record governs **generation** — a learned model drawing pixels that were
never photographed, where the label survives only if the generator happened not
to redraw the discriminating structure. It has never governed **simulation** — a
deterministic transformation of a real photograph whose physical effect is known,
where the soil pixels are unmodified or modified by an operation that can be
reasoned about.

Normalising a photograph to a canonical scale (ADR 0017), cutting it into
patches, converting it to greyscale (ADR 0018) and compositing a masked disc
onto a different background are all simulation. **None of them is gated by this
record**, and the distinction is stated here so that no later reader cites it
against a resample.

### Decided

- **No generator can be trained on a dataset that does not exist** —
  `ml/data/raw/` is absent, `data/splits/splits.json` was never generated, and
  `ml/models/v1` and `v2` are empty. A generator learns the distribution it is
  shown; with no real data it would amplify a void.
- **Soil texture is the signal generative models degrade** — textural class is
  carried by high-frequency detail: grain size, aggregate structure, particle
  specularity. VAEs produce characteristically blurred output; that blur is the
  destruction of the discriminating signal, not a cosmetic defect. GANs
  struggle with diversity, and mode collapse is the family's characteristic
  pathology, which negates the one reason to generate data here.
- **A strong enough augmentation destroys the label** — the acceptance test for
  any augmentation is whether the result is still an example of the same class
  and still not trivially memorizable alongside the original. A diffusion pass
  strong enough to add useful variety to a soil photograph is strong enough to
  redraw grain structure, and therefore to change the granulometric class the
  laboratory measured. The synthetic image would look more realistic and be
  labelled wrong.
- **Compute forecloses the expensive options anyway** — the available budget is
  a local machine plus free Kaggle/Colab tiers. Training a GAN or a diffusion
  model from scratch is not viable there. Only a pretrained diffusion model with
  LoRA or low-strength img2img would fit, and that is precisely the option §6.2
  of the study finds most likely to destroy labels.
- **The gate is downstream ablation, never generative metrics** — FID, KID,
  embedding-distance and cluster analysis are filters. A synthetic set can score
  well on all of them and still hurt the classifier.

## Considered Options

- **cGAN conditioned on the textural class** — rejected: unstable training,
  mode collapse shrinking exactly the diversity being sought, and roughly 1400
  declared images is a regime where a GAN memorizes rather than generalizes.
- **CycleGAN for domain translation (controlled sample → field context)** —
  rejected: it is the closest fit to the actual gap, since it needs no paired
  data, but it requires two generators and two discriminators to train stably
  on a dataset that does not exist, and the cycle-consistency constraint
  preserves identity, not granulometry.
- **VAE for minority-class oversampling** — rejected: blurred reconstructions
  remove the high-frequency detail that defines the class. The failure is
  categorical, not a matter of tuning.
- **Diffusion img2img at low strength** — deferred, not rejected. It is the only
  option that is both technically plausible on free-tier compute and capable of
  producing useful variety. It remains behind the five conditions below.
- **Traditional augmentation, corrected (chosen, first)** — `preprocess.py`
  already implements it and currently discards the lower bound of the
  brightness and contrast ranges (#81). Correcting it changes the realized
  distribution before anything more elaborate is considered.
- **Compositing onto real backgrounds (chosen, second)** — cut the soil region
  and paste it onto photographs of real field backgrounds. It attacks the
  background and occlusion gaps directly, trains no generator, and cannot alter
  grain structure because the soil pixels are unmodified.
- **Targeted collection (chosen, first alongside augmentation)** — the highest
  value per unit of effort and the only option that adds genuinely new
  information.

## Consequences

- The experiment plan schedules no GAN and no VAE arm. The original brief asked
  for both; they are omitted with the reasoning above rather than run as a
  formality. They are cheap to add if a later measurement contradicts it.
- The generative branch (E9 to E11 in the study) opens only when all of the
  following hold: a real baseline exists and is recorded; corrected
  augmentation and compositing have both been tried and measured; a *named*
  residual gap survives, such as Siltosa recall below target with a documented
  shortage of physical samples and no near-term collection path; free-tier
  compute suffices for a pretrained model with LoRA; and the ablation shows a
  downstream gain on a real-only test set.
- If the branch ever opens, three constraints are already fixed: the generator
  sees the training split only, so it cannot leak validation or test images
  through its weights; every generated image inherits its source image's sample
  group id, so group-aware splitting keeps synthetic children with their real
  parents; and the test set stays exclusively real.
- Model collapse is not the load-bearing argument here and should not be cited
  as if it were. The mechanism depends on unfiltered chained sampling, and
  filtered synthetic data mixed with fresh real data does not necessarily follow
  that trajectory. It argues for filtering and for a real-only test set, both of
  which this decision already requires.
- Deferring generation made collection a hard dependency rather than an
  optional one. **Superseded by the 2026-09-01 amendment**: collection did not
  stall, it ended, and this record was revisited then rather than left waiting
  for a trigger that can no longer fire.
