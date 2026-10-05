# ADR 0027: A photograph is classified from four patches, and its spread needs nine

## Status

Withdrawn — SPEC 0141's archive study found that classifying from the centred
five patches or the half-stride four loses quality, 0.047 and 0.059 of
photograph macro-F1 below the full grid against a margin of 0.02, so ADR 0018's
floor of nine stands ([the study](../ml/small-disc-study.md)).

## Decision

**The floor on classification and the floor on dispersion are two floors.**

- **A photograph is classified when its soil disc holds at least four patches.**
  The patches are unchanged: 20.7 mm of soil each, at the canonical scale, half a
  patch apart, inset by a half-diagonal from the disc's edge. Their distributions
  are averaged, as ADR 0018 decided.
- **The spread across patches is computed only over nine or more.** ADR 0018's
  reason for nine is about the entropy that measures the spread, not about the
  mean: over four values, a normalised entropy is too coarse to raise a warning
  with. Below nine, a photograph is classified with no dispersion warning.
- **When the centred grid falls short of the floor, the grid moves by half a
  stride.** The centred grid puts a patch on the disc's centre. The half-stride
  grid puts the centre between four patches, and on a disc of 43.9 to 49.9 mm it
  holds those four, where the centred grid holds one. At a floor of nine it never
  wins, so the archive's grids and the training are unchanged.

## Why

**Nine refused photographs for a measure nobody takes.** On the first session of
real photographs, the reader found the sheet on 24 of 31, and every one of the
24 stopped at the floor: their soil discs measure 46.5 to 51.4 mm, and nine
patches need 58.5 mm. Nothing in the app computes the dispersion that nine was
set for. The refusal turned usable photographs into retakes and protected
nothing.

**The mean was always the reading, and its cost can be measured.** ADR 0018
already says that patches of one photograph are repeated samples of one surface
statistic, not independent votes. Fewer samples make the mean noisier, and that
noise is what SPEC 0141's study measures on the archive's 25 folds. A floor
lowered on that evidence costs a measured amount of quality. A floor lowered on
a guess would not be known to cost anything.

**Rigid where it matters.** The patch is still fixed in millimetres, the scale is
still read from the sheet, and a disc too small for four is still refused by
name. What adapts is which patches a small disc carries, never what a patch is.

## Considered Options

- **Keep nine and ask for a bigger soil patch.** Rejected as the whole answer.
  The onboarding already asks for 8 to 10 cm, and the first session still
  produced 5 cm. The guide stays, because more patches are still better.
- **A stride of a quarter patch, so a 50 mm disc holds thirteen.** Rejected. The
  extra patches cover soil the five already cover. The floor would pass with no
  new evidence, and the dispersion measure would read overlap as agreement.
- **Always use the grid with more patches.** Rejected. On the archive's 90 mm
  dish, the half-stride grid holds 32 against the centred grid's 25. Training
  would move.
- **One floor for both purposes, at four.** Rejected. An entropy over four
  values cannot carry a warning, and ADR 0018's argument for nine still holds
  for the spread.

## Consequences

- `geometry.min_patches` in the contract drops to the floor the study allows,
  and the contract is re-released as model version `1.1.0` with the same
  weights. A saved record carries the version that scored it (SPEC 0097), so
  readings made under the lower floor can be found.
- A reading from four patches and one from twenty-five show the same kind of
  confidence on the screen. Nothing tells them apart until the dispersion
  measure is wired, and even then only above nine.
- Whoever wires the dispersion measure must gate it on nine patches. The floor
  is not in the contract today, because no code reads it.
- The capture protocol does not change. A soil patch of 8 to 10 cm is still what
  the onboarding asks for.

## What would reopen it

- Labelled real photographs on which readings from four or five patches are
  measurably worse than readings from nine or more.
- A dispersion measure that works over fewer than nine patches. The two floors
  could then be one again.
