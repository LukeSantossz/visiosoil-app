# Results and Uncertainty

This is the document the rest of the dossier exists to support. Everything else
improves the experience; this one determines whether the experience is honest.

## 1. The defect

`InferenceResult` carries two fields: the argmax label and its probability. The
full softmax vector is computed inside the isolate and discarded at the moment
of return.

With five classes, chance is twenty percent. Consider three real possibilities:

| Distribution | Today's rendering |
| --- | --- |
| Argilosa 0.94, rest ≤ 0.03 | "Argilosa", badge "94% · Alta", green |
| Argilosa 0.44, Muito Argilosa 0.39, rest ≤ 0.07 | "Argilosa", badge "44% · Baixa", red |
| Argilosa 0.25, Media 0.24, Siltosa 0.22, rest | "Argilosa", badge "25% · Baixa", red |

Rows two and three render identically apart from a two-point change in a
percentage. In row two the model has narrowed the answer to two adjacent
textures, which is useful. In row three the model has told us nothing at all.
Both are presented as *the class is Argilosa*, in `headlineMedium`, painted with
Argilosa's colour from the soil scale.

There is no state in which the app declines to name a class.

## 2. Contract change

```dart
/// One class and its probability.
class ClassScore {
  final String textureClass;
  final double probability;
}

class InferenceResult {
  final String textureClass;            // top-1 label — unchanged
  final double confidenceScore;         // top-1 probability — unchanged
  final List<ClassScore> distribution;  // NEW: all classes, descending
}
```

The two existing fields keep their meaning and their types, so every current
consumer — the repository, the persisted columns, the share builder, the home
row — continues to work untouched. The distribution is additive.

This is an app-side change to `inference_service.dart`. It does not touch model
training, model export, or the `ml/` pipeline. The vector is already in hand at
`_runInference`; the change is to stop throwing it away.

**Dependency on the ML terminal:** the label order must match the model's output
order. `InferenceService._textureLabels` already encodes it and already rejects
models whose class count disagrees. `SoilTextureColors.all` contradicts that
order and must be corrected in the same spec (P2-5).

## 3. Verdict bands

One threshold cannot distinguish row two from row three above, because both have
a similar top-1. The distinguishing quantity is the **margin** between the first
and second candidates. Two axes are required.

| Verdict | Rule | Meaning |
| --- | --- | --- |
| **Conclusivo** | `top1 ≥ 0.70` **and** `top1 − top2 ≥ 0.15` | One class, clearly separated |
| **Ambíguo** | `top1 ≥ 0.45` **and** `top1 − top2 < 0.15` | Two adjacent candidates; the sample is between them |
| **Evidência insuficiente** | `top1 < 0.45` | Nothing can be asserted |
| **Não analisado** | no score present | Distinct state — no attempt was made or none was possible |

A case with `top1 ≥ 0.70` and a small margin falls to **ambíguo**, which is
correct: high absolute confidence with a near-tie is still a near-tie.

**Every number above is a hypothesis.** None was derived from validation data,
because none is published. The implementing spec must calibrate them against the
ML terminal's per-class validation metrics and record the procedure. The
*structure* — two axes, four states — is the design decision; the constants are
placeholders.

### 3.1 Replacing `ConfidenceLevel`

The current enum has a defect beyond its thresholds:

```dart
factory ConfidenceLevel.fromScore(double? score) {
  if (score == null || score.isNaN) return ConfidenceLevel.low;   // ← here
```

A record with no classification and a record with a terrible classification
return the same value. "No data" and "bad data" are different states with
different remedies, and conflating them means the interface can never tell the
user which one they are looking at.

The replacement carries **não analisado** as a first-class member.

## 4. Presentation

### 4.1 Colour, icon and copy, with justification

| Verdict | Container | Icon | Justification |
| --- | --- | --- | --- |
| **Conclusivo** | `primaryContainer` | `verified` | The design system reserves `primary` for primary actions, links and success. A settled reading is the success case. `verified` states that the result met the bar |
| **Ambíguo** | `warningContainer` | `compare_arrows` | Amber, not red: two candidates are useful information, not a fault. `compare_arrows` describes the actual state — a comparison between two options — where the current `info_outline` describes nothing in particular |
| **Evidência insuficiente** | **neutral** (`surfaceVariant`) | `help_outline` | **Deliberate break with today's `errorContainer`.** Nothing failed. The model does not know. Red reads as *something is broken*, blames the user for the model's limits, and — used for the most common uncertain outcome — trains users to disregard red everywhere else. `error` is reserved for genuine failures: unreadable file, failed write, timeout |
| **Não analisado** | neutral | `eco_outlined` | Absence, not judgement |

### 4.2 Three presentation rules

**Rule 1 — the percentage is never the headline.** The band label carries the
meaning; the number is secondary detail. A bare "25%" invites the user to
supply their own interpretation of what twenty-five percent means across five
classes, and most interpretations will be wrong. Format follows the design
system: rounded in badges, one decimal in detail views.

**Rule 2 — the soil-scale colour appears only on a conclusive verdict.** The
design system calls the five-brown ramp sacred and restricted to classification.
Painting an unasserted result in a class's colour asserts it by colour, in the
one channel the user reads fastest. Ambiguous results use a neutral swatch and
show both candidates on the `TextureScale`; insufficient results show no swatch
at all.

**Rule 3 — a conclusive result still states its limits.** Today the advisory
banner appears only for low and moderate confidence, so a high-confidence result
carries no statement at all. A standing limit line — that this is an image-based
estimate and does not replace laboratory analysis — belongs on every result,
matching the disclaimer discipline the research agent already applies to its
tips.

### 4.3 Anatomy by verdict

**Conclusivo**

```
Classe textural                          ← eyebrow, uppercase, letter-spaced
Argilosa                        [verified 94% · Alta]
▓▓▓▓▓░░░░░  texture scale, Argilosa highlighted
Estimativa por imagem. Não substitui análise laboratorial.
[ Salvar registro ]  [ Refazer ]
```

**Ambíguo**

```
Resultado entre duas classes             ← states the situation, not a class
Argilosa            44%
Muito Argilosa      39%
▓▓▓▓▓░░░░░  texture scale, both highlighted, adjacent
[compare_arrows] As duas texturas são próximas nesta amostra.
                 Uma nova captura pode separar as duas.
[ Refazer a captura ]  [ Registrar assim mesmo ]
```

Note the primary action inverts: for an ambiguous result the most useful next
step is another photograph, not a save.

**Evidência insuficiente**

```
[help_outline] Evidência insuficiente
Não é possível afirmar uma classe textural para esta imagem.
Uma captura com melhor iluminação e enquadramento pode resolver.
[ Refazer a captura ]  [ Registrar sem classe ]
```

No class name. No percentage. No soil colour. The strongest statement the
interface can make about what the system knows is the absence of all three.

**Não analisado**

```
[eco_outlined] Não analisado
Este registro não passou por classificação.
```

No retry when the model is absent from the build; retry only when a run
genuinely failed.

## 5. Persisting the distribution

The persisted columns are `texture_class` and `confidence_score`. The
distribution is transient.

Without persistence, an ambiguous result shows both candidates on the fresh
analysis screen and shows only the settled top-1 when the same record is opened
a week later — the record silently becomes more certain than it was. That
asymmetry is worse than either consistent option.

**Decision (taken with the product owner): persist it.** One nullable text
column holding the distribution as JSON, migration v4 → v5, following the same
cumulative pattern as the existing three migrations. Sequenced as its own small
spec.

Rejected alternative: recompute on open. The photograph is retained, so it is
technically possible, but it spends fifteen seconds of inference to reproduce a
number the app already had, and produces a different answer if the model version
changes — silently rewriting history.

## 6. What the interface must not claim

- **It must not say "this soil is Argilosa."** It says the estimated class,
  from an image, with a stated confidence.
- **It must not present a probability as a certainty**, including at 94 %.
- **It must not name a class it did not conclude**, which is why insufficient
  evidence shows no class name at all rather than a greyed-out one.
- **It must not attribute a cause it cannot observe.** "Confiança baixa.
  Considere refazer a captura com melhor iluminação e enquadramento" — the
  current copy — asserts that lighting or framing caused the low confidence. The
  model reports no such thing. With the quality gate from
  `06-capture-experience.md` in place, the app *can* say this when the gate
  actually flagged lighting; without a flag it must offer retaking as a
  possibility, not as a diagnosis.

That last point is a real change to shipped copy and is easy to overlook: the
current message reads as an explanation when it is a guess.

## 7. Acceptance criteria

- `distribution_returned` — `classify()` returns all classes with probabilities,
  ordered descending, and the existing two fields are unchanged.
- `label_order_single_source` — `SoilTextureColors` and
  `InferenceService._textureLabels` agree, asserted by a test.
- `verdict_conclusive` — high top-1 with a wide margin renders the class name,
  its scale colour, the badge and the standing limit line.
- `verdict_ambiguous` — a narrow margin renders both candidates, neither
  asserted, both highlighted on the scale, with retake as the primary action.
- `verdict_insufficient_asserts_nothing` — below the floor, the screen shows no
  class name, no soil-scale colour and no headline percentage; it offers retake
  and record-without-class.
- `unclassified_is_not_low_confidence` — a record with no score renders as *não
  analisado*, visually distinct from an insufficient-evidence result.
- `insufficient_is_not_error_coloured` — the insufficient state uses no `error`
  role colour.
- `no_causal_claim_without_signal` — retake guidance names lighting or framing
  only when the quality gate flagged them.
- `distribution_persisted` — reopening a record renders the same verdict it
  showed when it was created.
