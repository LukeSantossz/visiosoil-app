# Synthetic image generation is deferred behind a measured gap: collection, corrected augmentation and compositing come first, and generative models only if an ablation proves a downstream gain

VisioSoil does not train or use a generative model (GAN, VAE, or diffusion) to
expand the soil texture dataset at this time. The dataset gap is addressed, in
order, by targeted collection, corrected traditional augmentation, and
compositing onto real backgrounds. A generative branch opens only when five
named conditions hold simultaneously, and closes unless an ablation on a
real-only test set shows a gain exceeding run-to-run variance.

## Status

Accepted. Recorded during the 2026-07-30 ML architecture study
(`docs/architecture/soil-classification.md`, §6 to §11).

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
- Deferring generation makes collection a hard dependency rather than an
  optional one. If field collection stalls, this ADR is what must be revisited.
