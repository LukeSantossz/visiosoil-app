# SPEC: fix(ui): say what a classification needs and why it failed

## Problem

Since SPEC 0092, a photograph is classified only when it follows ADR 0017's A4-sheet protocol, and is refused by a named cause otherwise (#281). Yet the screens still tell the user otherwise:
- **Home** promises "Aponte para o solo e descubra a textura em segundos".
- **Capture** answers every failure with "Classificação falhou · tocar para repetir", which names no cause. The retry runs the same file again, and that never fixes a photograph-dependent refusal.
- **A record saved without a class** says "Classifique o solo deste registro", an action no screen offers.

## Design Decision

**Each failure cause gets a chip that says what happened and what helps.** ADR 0015 leaves to the interface which causes get a retry and what each one says. This spec settles it by splitting ADR 0015's "retry, or retake" column, on what the causes do with the same file:

| Group | Causes | Chip | Tap |
| --- | --- | --- | --- |
| Run again ("tentar de novo") | `timeout`, `isolateFailure`, `computationError` | "Análise não terminou · tocar para tentar de novo" | runs the same file again |
| Take another photograph ("tire outra foto") | `sheetNotFound` | "Folha A4 não encontrada · tire outra foto" | none |
| | `sheetCropped` | "Folha cortada no quadro · tire outra foto" | none |
| | `soilRegionTooSmall` | "Pouco solo na folha · tire outra foto" | none |
| | `soilRegionOutsideFrame` | "Amostra fora da área lida · tire outra foto" | none |
| | `photographTooCoarse` | "Foto sem detalhe suficiente · tire outra foto" | none |
| | `imageMissing`, `imageUndecodable` | "Foto ilegível · tire outra foto" | none |
| | `outputInvalid` | "Não foi possível analisar esta foto · tire outra foto" | none |
| The build is wrong | `contractMissing`, `contractMalformed`, `contractUnsupported` | "Análise indisponível nesta versão" | none |

The second group is a pure function of the decoded file, so running the same file again returns the same cause.

`computationError` sits in the first group. It also catches memory exhaustion, which a second run may not hit, and the chip promises an attempt, not a result.

`outputInvalid` is ADR 0015's "re-release the contract", but one of its two producers is a non-finite score from this photograph's patches. A new photograph can help there. A retry of the same file cannot.

**The mapping lives in one exhaustive `switch`**, in `classification_failure_chip.dart`. A cause added to the enum fails to compile until it gets copy.

**Home** reads "ANÁLISE NO APARELHO" and "Fotografe o solo sobre uma folha A4 e descubra a textura". That is the protocol, and claims no time.

**An unclassified record's tips message** says why there are no tips and how to get them: "Este registro foi salvo sem a classe de textura, e as dicas dependem dela. Para obtê-las, capture a amostra de novo seguindo o passo a passo."

## Alternatives Considered

- **Leave the chip and the copy to the UI/UX roadmap's capture and phase specs** (items 5 and 7). Rejected by the Developer for the release: the chip misleads today. Those specs can still replace this chip with named phases and a fuller retake flow.
- **One generic "tire outra foto" for every non-transient cause.** Rejected: ADR 0015 records that the sheet messages "can say which, because the remedies differ: bring a sheet, or step back". A generic chip throws that away.
- **Make the retake chip tappable, discarding and reopening the camera.** Rejected: "Descartar" and "Câmera" already do that, one tap apart. A chip that discards the photograph on tap would also destroy work on a mis-tap.

## Scope

- Includes:
  - `lib/core/features/capture/widgets/classification_failure_chip.dart`: the cause-to-chip mapping.
  - `CaptureImagePreview` takes the failure cause and shows its chip. Only a retryable cause is tappable.
  - `CaptureScreen` passes `_state.classificationFailureCause` to the preview.
  - `lib/core/features/home/widgets/hero_capture_card.dart`: the eyebrow and headline.
  - `lib/core/features/details/management_tips_section.dart`: the unclassified record's description.
  - Tests:
    - the mapping, over every cause;
    - the chip's tap, in both groups;
    - the home copy, updating `home_widgets_test.dart`'s pin;
    - the tips copy.
- Does NOT include:
  - A guide screen, named processing phases, a cancel action, or a reclassify action for saved records (the UI/UX roadmap's items).
  - `ClassificationFailureCause` and ADR 0015's table, which this spec reads and does not change.
  - The onboarding, which SPEC 0104 rewrote.
  - Persisting the cause on a saved record.

## Acceptance Criteria

- `every_cause_has_a_chip`: for every value of `ClassificationFailureCause`, the chip has a non-empty label.
  - It is retryable exactly for `timeout`, `isolateFailure` and `computationError`.
  - A retryable label says "tentar de novo".
  - A photograph-dependent label says "tire outra foto".
  - A build label says neither.
- `a_retake_cause_offers_no_retry`: with `sheetNotFound`, the preview shows its chip, and tapping it does not call the retry.
- `a_transient_cause_offers_a_retry`: with `timeout`, the preview shows its chip, and tapping it calls the retry once.
- `the_capture_screen_names_the_cause`: a capture whose classification fails with `sheetCropped` shows that cause's chip.
- `home_teaches_the_sheet_not_point_and_shoot`: the hero card shows the new eyebrow and headline, and no "Aponte", "INSTANTÂNEA" or "segundos".
- `an_unclassified_record_says_how_to_get_tips`: the tips section on an unclassified record shows the new description, and no "Classifique o solo deste registro".

## Reproducibility

`flutter test test/features/capture/ test/features/home/ test/features/details/`

Flutter 3.44.1, Dart 3.12.1.

## Risks and Assumptions

- Assumes each photograph-dependent cause is a pure function of the decoded file. The ML session checked `inference_service.dart` and `a4_sheet.dart` on main, and that holds.
- The chips are short by design and do not teach the full protocol. The onboarding, reachable again from Settings, does that (SPEC 0104).
- A record saved after a failed classification keeps no cause, so the details screen cannot say which one it was.
