# Registro de Projeto — Estado e Histórico

> Este arquivo contém o estado atual e histórico do projeto. É atualizado pelo agente ao final de cada implementação.
> As **regras** sobre como atualizar este registro estão em `.claude/rules/08-registro-projeto.md`.

---

## Informações do Projeto

- **Nome:** VisioSoil
- **Stack:** Flutter 3.x / Dart 3.10.4+ (Riverpod, GoRouter, Drift+SQLite, TFLite)
- **Repositório:** LukeSantossz/visiosoil-app
- **Estrutura:** Mobile app — lib/core/ (theme, routes, widgets, utils, services, database, data, features), lib/models/, lib/providers/

## Histórico de Implementações

> Registro de conclusões. Cada entrada representa uma task finalizada — não o progresso intermediário (que vive no Log de Andamento de cada task em `tasks.md`). O agente adiciona uma nova linha após cada task concluída. Nunca remova entradas anteriores.

| # | Data | Task | Complexidade | Escopo Alterado | Resultado | Observações |
|---|------|------|--------------|-----------------|-----------|-------------|
| — | — | — | — | — | — | Histórico pré-governance não rastreado. Projeto iniciou governança a partir desta data. |
| 1 | 2026-04-29 | TASK-005 | patch | 2 arquivos — Android build | Fix R8/TFLite: proguard-rules.pro + build.gradle.kts | — |

## Estado da Codebase

> Atualizado a cada implementação ou verificação pós-pull. Reflete o snapshot mais recente do projeto.

- **Última atualização:** 2026-04-29
- **Último responsável:** Claude Code (Opus 4)
- **Branch ativa:** fix/TASK-005-r8-tflite-build
- **Versão:** 1.1.0 (próxima: 1.1.1 após merge)
- **Dependências alteradas recentemente:** nenhuma
- **Testes passando:** sim (15/15 — unit + repository)
- **Divergências externas pendentes:** nenhuma
- **Última task concluída:** TASK-005 (fix R8/TFLite build)
- **Schema DB:** v2 (soil_records com texture_class, confidence_score)

## Pendências Conhecidas

- TFLite model placeholder (assets/models/soil_classifier.tflite) — modelo de produção ainda não treinado
- Gallery source desabilitada (camera-only, `TODO(v2)`)
- Remote sync não implementado (repository interface preparada)

## Decisões Técnicas Relevantes

> Decisões tomadas durante implementações que afetam futuras tasks. Inclua justificativa breve.

- **Repository pattern (Drift abstraction):** UI nunca importa tipos Drift diretamente. Facilita troca futura de implementação (API remota, cache, etc.)
- **Isolate-based inference:** TFLite roda em Isolate separado. Model bytes passados como Uint8List porque rootBundle não funciona em isolates.
- **GoRouter state.extra para IDs:** Record ids passados via extra (não URL params) — evita slugificação e mantém rotas limpas.
- **Schema v2 migration:** Colunas texture_class e confidence_score adicionadas via migration strategy com version check.

## Política de Versionamento

> Tags git e `pubspec.yaml` devem estar sempre alinhados. O agente sugere o bump ao final de cada task concluída.

- **Formato:** Semantic Versioning — `vMAJOR.MINOR.PATCH` (tag git) / `MAJOR.MINOR.PATCH+BUILD` (pubspec.yaml)
- **Tag atual:** `v1.1.0`
- **pubspec.yaml atual:** `1.0.0+1` (desalinhado — alinhar na próxima release)
- **Regra de incremento por complexidade de task:**
  - `patch` (fix, chore, docs, style, ci) → incrementa PATCH (ex: 1.1.0 → 1.1.1)
  - `minor` (feat, refactor, perf, test) → incrementa MINOR (ex: 1.1.0 → 1.2.0)
  - `major` (breaking changes, migrações estruturais) → incrementa MAJOR (ex: 1.1.0 → 2.0.0)
- **BUILD number:** Incrementa +1 a cada release no pubspec.yaml, independente do tipo
- **Fluxo:** Ao concluir uma task e antes do merge para main, o agente sugere o novo número de versão seguindo esta política. O desenvolvedor confirma e o agente atualiza `pubspec.yaml` e sugere a tag.

## Padrões Recorrentes Observados

| Padrão | Frequência | Impacto | Ação Corretiva |
|--------|------------|---------|----------------|
| [nenhum padrão registrado] | — | — | — |

---

## Notas de Sessão

> Espaço para anotações pontuais sobre contextos que influenciam futuras sessões.

- **2026-04-27:** Estrutura `.claude/` reorganizada. Rules movidas para `.claude/rules/`, hooks criados, templates criados, enforcement.conf configurado para Dart/Flutter. Registry resetado para VisioSoil (anteriormente continha dados do projeto SmartB100).
