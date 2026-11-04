# Documentation

What each directory under `docs/` holds. A new document goes under one of
these, and `test/standards/docs_layout_test.dart` fails on anything placed
beside them (SPEC 0253, SPEC 0254).

| Directory | What it holds |
|---|---|
| [`adr/`](adr/) | Architecture Decision Records: one decision each, with its status. The README's ADR index lists them |
| [`specs/`](specs/) | Approved specs, numbered durably. A durable archive: a spec keeps the text it was approved with, so its paths are not updated when a file moves |
| [`agents/`](agents/) | `project.md`, the source `mf agents sync` generates `CLAUDE.md` and `AGENTS.md` from. Edit it, never the generated files |
| [`guides/`](guides/) | Guides for the people who take the photographs: the [capture protocol](guides/capture-protocol.md) and its [pt-BR copy](guides/capture-protocol.pt-BR.md) |
| [`plans/`](plans/) | Implementation maps: the ordered backlogs of the [ML](plans/ml-implementation-map.md) and [research agent](plans/research-agent-implementation-map.md) workstreams. Each says the date it was last revised |
| [`studies/architecture/`](studies/architecture/) | Design studies: the [research agent](studies/architecture/research-agent.md) and the [corpus assets](studies/architecture/corpus-assets.md) |
| [`studies/ml/`](studies/ml/) | Run verdicts and ML studies, listed with their status in its [README](studies/ml/README.md). A durable archive like `specs/`, and exempt from the Spec Gate because a verdict lands after the spec that orders it (`.framework.toml`, SPEC 0058) |
| [`design/`](design/) | The design of record for redesign v11 ([`design/v11/`](design/v11/)) |

## Where moved and deleted documents went

Specs written before SPEC 0253 or SPEC 0254 name the old paths. A moved document is at its
new path; a deleted one stays readable at commit
[`10f4909`](https://github.com/LukeSantossz/visiosoil-app/tree/10f490937fc4787423e1b90889303a8a597be479/docs),
the last `main` that held it, and through `git show 10f4909:<path>`.

| Old path | Now |
|---|---|
| `docs/capture-protocol.md` | [`docs/guides/capture-protocol.md`](guides/capture-protocol.md) |
| `docs/capture-protocol.pt-BR.md` | [`docs/guides/capture-protocol.pt-BR.md`](guides/capture-protocol.pt-BR.md) |
| `docs/architecture/<file>` | [`docs/studies/architecture/<file>`](studies/architecture/) |
| `docs/ml/<file>` | [`docs/studies/ml/<file>`](studies/ml/) |
| `docs/architecture/ml-handoff.md` | Deleted: [at `10f4909`](https://github.com/LukeSantossz/visiosoil-app/blob/10f490937fc4787423e1b90889303a8a597be479/docs/architecture/ml-handoff.md) |
| `docs/architecture/soil-classification.md` | Deleted: [at `10f4909`](https://github.com/LukeSantossz/visiosoil-app/blob/10f490937fc4787423e1b90889303a8a597be479/docs/architecture/soil-classification.md) |
| `docs/design/ux-2026/` | Deleted: [at `10f4909`](https://github.com/LukeSantossz/visiosoil-app/tree/10f490937fc4787423e1b90889303a8a597be479/docs/design/ux-2026) |
| `docs/design/prototipo-v11/` | Deleted: [at `10f4909`](https://github.com/LukeSantossz/visiosoil-app/tree/10f490937fc4787423e1b90889303a8a597be479/docs/design/prototipo-v11) |
| `docs/reverse-engineering/` | Deleted: [at `10f4909`](https://github.com/LukeSantossz/visiosoil-app/tree/10f490937fc4787423e1b90889303a8a597be479/docs/reverse-engineering) |
| `docs/studies/architecture/ml-implementation-map.md` | [`docs/plans/ml-implementation-map.md`](plans/ml-implementation-map.md) (SPEC 0254) |
| `docs/studies/architecture/research-agent-implementation-map.md` | [`docs/plans/research-agent-implementation-map.md`](plans/research-agent-implementation-map.md) (SPEC 0254) |
| `docs/design/spec/SPEC.md` | [`docs/design/v11/redesign.md`](design/v11/redesign.md) (SPEC 0254) |
| `docs/design/spec/haptics.md` | [`docs/design/v11/haptics.md`](design/v11/haptics.md) (SPEC 0254) |
| `docs/design/spec/telas/NN-<name>.png` | [`docs/design/v11/screens/NN-<English name>.png`](design/v11/screens/), same number (SPEC 0254) |
