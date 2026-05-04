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
| 18 | 2026-05-03 | TASK-025+ | patch | 1 arquivo — ml/src/evaluate.py | labels explícitos em confusion_matrix/classification_report | Previne mismatch com classes ausentes |
| 19 | 2026-05-03 | TASK-033+ | patch | 3 arquivos — dataset.py, train.py, evaluate.py | Persistir e validar val_split/test_split no manifest | Previne reuso com frações alteradas |
| 20 | 2026-05-03 | TASK-032+ | patch | 1 arquivo — ml/src/dataset.py | Validação de ≥3 grupos por classe antes do split | Previne falha silenciosa do stratify |
| 21 | 2026-05-03 | TASK-034 | patch | 2 diretórios — ml/models/v1/, ml/models/v2/ | Limpeza de artefatos obsoletos (v1+v2). .gitkeep adicionado | Prepara retreino limpo como v3 |
| 22 | 2026-05-03 | TASK-035 | patch | 2 arquivos — ml/config.yaml, ml/tests/test_model_output.py | fine_tune_learning_rate 1e-5→1e-4 | Previne catastrophic forgetting no Phase 2 |
| 23 | 2026-05-03 | TASK-036 | patch | 2 arquivos — ml/config.yaml, ml/tests/test_preprocess.py | Augmentation conservador para textura | rotation 40→15, vertical_flip removido |
| 24 | 2026-05-03 | TASK-037 | patch | 3 arquivos — ml/src/dataset.py, train.py, evaluate.py | validate_splits_against_config extraída para dataset.py | Elimina duplicação de 33 linhas |
| 25 | 2026-05-03 | TASK-038 | patch | 1 arquivo — ml/src/preprocess.py | Zoom calcula ambos os limites da config | Fix: zoom assimétrico agora correto |
| 26 | 2026-05-03 | TASK-039 | minor | 6 arquivos — lib/core/theme/ + pubspec.yaml | Design tokens v2: Manrope+Inter, soil texture colors, AppRadius, warning colors | Checklist agêntico: aplicado |
| 27 | 2026-05-03 | TASK-040 | major | 1 arquivo — lib/core/features/home/home_page.dart | HomeScreen v2: hero, stats grid, last analysis card, lot map placeholder | Checklist agêntico: aplicado |
| 28 | 2026-05-03 | TASK-043 | patch | 2 arquivos — processing_screen.dart + app_router.dart | Tela de processamento: animação pulsante, progress bar, texto contextual | Checklist agêntico: aplicado |
| 29 | 2026-05-03 | TASK-047 | minor | 2 arquivos — onboarding_screen.dart + app_router.dart | Onboarding 3 passos: enquadramento, iluminação, ângulo. Flag SharedPreferences adiada | Checklist agêntico: aplicado |
| 30 | 2026-05-03 | TASK-048 | minor | 2 arquivos — details.dart + app_router.dart | DetailsScreen v2: SliverAppBar hero, confidence badges, info tiles, action buttons | Checklist agêntico: aplicado |
| 31 | 2026-05-03 | TASK-049 | patch | 1 arquivo — ml/README.md | README ML: v2→v1, LR Phase 2 corrigido, seção Versioning | Checklist agêntico: N/A |
| 32 | 2026-05-03 | TASK-050 | patch | 5 arquivos — router, home, details, main, onboarding | Codex review: 7 fixes (guarded casts, NaN, null id, PopScope, overflow) | Review cruzado (Codex): aplicado |
| 33 | 2026-05-03 | TASK-009 | patch | 2 arquivos — details.dart + confidence_level.dart | ConfidenceLevel enum, banners baixa/moderada na DetailsScreen | Checklist agentico: aplicado |
| 34 | 2026-05-03 | TASK-014 | minor | 2 arquivos — history_screen.dart + error_state.dart | ErrorState widget, LoadingIndicator padronizado | Checklist agentico: aplicado |
| 35 | 2026-05-03 | TASK-015 | minor | 3 arquivos — settings_screen.dart, app_router.dart, pubspec.yaml | Tela de configuracoes com versao, onboarding link, apagar dados | Checklist agentico: aplicado |
| 36 | 2026-05-03 | TASK-044 | minor | 2 arquivos — result_screen.dart + app_router.dart | ResultScreen com classe textural, badge confianca, banners | Checklist agentico: aplicado |
| 37 | 2026-05-03 | TASK-016 | patch | 3 arquivos — home_stats.dart, repository_provider.dart, home_page.dart | homeStatsProvider derivado do stream, HomeScreen consome | Checklist agentico: aplicado |

## Estado da Codebase

> Atualizado a cada implementação ou verificação pós-pull. Reflete o snapshot mais recente do projeto.

- **Última atualização:** 2026-05-03
- **Último responsável:** Claude Code (Opus 4)
- **Branch ativa:** feat/TASK-039-048-ui-redesign-v2
- **Versão:** 2.0.0
- **Dependências alteradas recentemente:** pubspec.yaml — package_info_plus ^8.0.0 adicionado
- **Testes passando:** sim (Flutter 15/15)
- **Divergências externas pendentes:** splits.json deletado — deve ser regenerado no venv ML antes do próximo treino
- **Última task concluída:** TASK-016 — Home aggregate stats providers
- **Review cruzado (Codex):** aplicado — 8 findings, 1 CRITICAL false positive (Dart 3.10 null-aware elements), 1 HIGH (rota /result nao integrada ao capture — by design), 4 MEDIUM (guards ja existentes), 2 LOW aceitos
- **Schema DB:** v2 (soil_records com texture_class, confidence_score)

## Pendências Conhecidas

- TFLite model (assets/models/soil_classifier.tflite) — modelo v1 (SqueezeNet) deployado. Treinar v2 (MobileNetV2) e re-deployar (TASK-027)
- splits.json deletado — re-gerar antes do próximo treino no venv ML
- Gallery source desabilitada (camera-only, `TODO(v2)`)
- Remote sync não implementado (repository interface preparada)

## Decisões Técnicas Relevantes

> Decisões tomadas durante implementações que afetam futuras tasks. Inclua justificativa breve.

- **Repository pattern (Drift abstraction):** UI nunca importa tipos Drift diretamente. Facilita troca futura de implementação (API remota, cache, etc.)
- **Isolate-based inference:** TFLite roda em Isolate separado. Model bytes passados como Uint8List porque rootBundle não funciona em isolates.
- **GoRouter state.extra para IDs:** Record ids passados via extra (não URL params) — evita slugificação e mantém rotas limpas.
- **Schema v2 migration:** Colunas texture_class e confidence_score adicionadas via migration strategy com version check.
- **ML pipeline isolado (ml/):** Pipeline TF/Keras em diretório separado, sem impacto no Flutter app. spec.json é o contrato de integração entre ml/ e InferenceService. deploy_to_app.sh copia artefatos para assets/models/. MobileNetV2 com transfer learning (ImageNet weights), Rescaling layer embutido no modelo converte [0,1]→[-1,1]. Treino em 2 fases: head-only + fine-tuning.
- **JSON local para experiment tracking:** Sem MLflow/W&B — overhead desproporcional. Cada versão gera metrics.json + config.json em models/vN/.

## Política de Versionamento

> Tags git e `pubspec.yaml` devem estar sempre alinhados. O agente sugere o bump ao final de cada task concluída.

- **Formato:** Semantic Versioning — `vMAJOR.MINOR.PATCH` (tag git) / `MAJOR.MINOR.PATCH+BUILD` (pubspec.yaml)
- **Tag atual:** `v2.0.0`
- **pubspec.yaml atual:** `2.0.0+2`
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
- **2026-04-29:** TASK-006 concluída — diretório ml/ criado com pipeline ML reproduzível. Decisão de não reestruturar para /app/ tomada durante planejamento (Flutter permanece na raiz). 23 arquivos criados, 1 editado (.gitignore raiz).
