# ML studies

The classifier's studies and verdicts. Each one answers a question that a spec
fixed before the run, and records the numbers it found. A study is not
maintained after it is written: a later study, spec or ADR that changes its
reading says so itself. What the app does today is in
[`../../agents/project.md`](../../agents/project.md).

| Document | Ordered by | Status | Answer |
|---|---|---|---|
| [calibration-study.md](./calibration-study.md) | SPEC 0098 | Verdict | A temperature does not help, and the study publishes no band constant. |
| [capture-population-probe.md](./capture-population-probe.md) | SPEC 0055 | Verdict | The capture population is recoverable, so SPEC 0040 D6 was re-opened. |
| [collection-protocol.md](./collection-protocol.md) | — | Withdrawn on 2026-09-01 (ADR 0016) | No collection will be made. It is kept for three rules cited elsewhere. |
| [descriptor-distance-guard.md](./descriptor-distance-guard.md) | SPEC 0176 | Verdict | The guard does not catch Siltosa and is not wired. |
| [descriptor-path-cost.md](./descriptor-path-cost.md) | SPEC 0086, re-run by SPEC 0092 | Verdict | One classification fits the 15 s timeout with about 2.5× margin. The JPEG decode is the cost. |
| [e0-verdict.md](./e0-verdict.md) | SPEC 0044 | Verdict | Signal was demonstrated: two of the three real arms clear the shuffled-label control. The descriptor path ships (ADR 0024). |
| [field-photographs-2026-10-19.md](./field-photographs-2026-10-19.md) | — | Baseline for SPEC 0175 | 5 of 5 classified photographs were right and 49 were refused. Upsampled, every soil reads as clay. |
| [sheet-reader-real-photographs.md](./sheet-reader-real-photographs.md) | SPEC 0091, SPEC 0140, SPEC 0144 | Verdict | The reader finds the sheet on 26 of 31 photographs, and none of them is classified yet. |
| [small-disc-study.md](./small-disc-study.md) | SPEC 0141 | Verdict | Five and four patches both lose quality. The floor stays at nine and ADR 0027 is withdrawn. |
| [small-patch-study.md](./small-patch-study.md) | SPEC 0143 | Verdict | A nine-patch grid at 128 px fails the registered margin. |
| [transported-population-sensitivity.md](./transported-population-sensitivity.md) | SPEC 0057 | Verdict | The transported population does not change the answer, so SPEC 0040 D6 stands. |
