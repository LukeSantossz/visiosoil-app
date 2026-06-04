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
| 1 | 2026-04-28 | TASK-002 | minor | 1 arquivo — CI/CD | Pipeline validado, Flutter pinado 3.38.5, concurrency group adicionado | — |
| 2 | 2026-04-28 | TASK-003 | major | revertida | Workflow claude-implement.yml criado e removido por solicitação do usuário | — |
| 3 | 2026-04-28 | TASK-004 | minor | revertida | Validação invalidada pela reversão da TASK-003 | — |
| 4 | 2026-04-29 | TASK-006 | major | 23 arquivos — ml/ (novo) + .gitignore raiz | Pipeline ML: SqueezeNet Keras, TFLite export, spec.json, testes, Makefile | Nenhum arquivo Flutter alterado |
| 5 | 2026-05-02 | TASK-001 | patch | 1 arquivo — inference_service.dart | Labels atualizadas de 12 USDA para 5 classes do dataset | Alinhado com ml/config.yaml |
| 6 | 2026-05-02 | TASK-018 | patch | 1 arquivo — ml/requirements.txt | Deps ML pinadas: TF 2.21, tf-keras 2.21, keras 3.14, ml-dtypes 0.5.4, protobuf 7.34.1 | Versões confirmadas pelo usuário |
| 6b | 2026-05-02 | TASK-018 | patch | 3 arquivos — .claude/rules/ + .claude/ | Adicionados rules 10, 11 e guia Codex ao repositório | Checklist agêntico: N/A |
| 7 | 2026-05-02 | TASK-019 | minor | 3 arquivos — ml/ (README, .gitattributes, train_and_export.sh) | README cross-platform, .gitattributes LF para .sh, encoding fix | Auditoria identificou 8 problemas |
| 8 | 2026-05-02 | TASK-020 | minor | 3 arquivos — pubspec.yaml, ml/config.yaml, ml/models/v1/config.json + re-export modelo | Fix TFLite runtime: tflite_flutter 0.12.1 + quantization none | Modelo 197KB→2.8MB (sem quantização) |
| 9 | 2026-05-02 | TASK-021 | major | 12 arquivos — ml/ (config, src, tests, README) | Pipeline ML reestruturado: MobileNetV2 transfer learning, 2-phase training, class weights | SqueezeNet removido, 47 testes ML passam |
| 10 | 2026-05-02 | TASK-024 | minor | 2 arquivos — ml/src/dataset.py, ml/tests/test_dataset.py (novo) | Fix sorted()→list() em create_splits(). Testes de label ordering adicionados | Causa raiz da acurácia ~27% |
| 11 | 2026-05-02 | TASK-025 | minor | 1 arquivo — ml/src/evaluate.py | evaluate.py usa manifest["classes"] em vez de cfg["classes"] | Redundante após TASK-024, mas garante fonte autoritativa |
| 12 | 2026-05-02 | TASK-029 | patch | 2 arquivos — ml/src/model.py, ml/tests/test_model_output.py | Heurística unfreeze: busca por nome em vez de contagem de layers | — |
| 13 | 2026-05-02 | TASK-030 | minor | 2 arquivos — ml/src/preprocess.py, ml/tests/test_preprocess.py | RandomBrightness value_range=(0.0, 1.0) para imagens normalizadas | Severidade HIGH confirmada por Codex |
| 14 | 2026-05-02 | TASK-031 | patch | 1 arquivo — lib/core/services/inference_service.dart | Logging em 3 blocos catch silenciosos | developer.log + debugPrint |
| 15 | 2026-05-02 | TASK-032 | minor | 2 arquivos — ml/src/dataset.py, ml/tests/test_dataset.py | Group-aware splitting elimina data leakage entre splits | 116 sample groups afetados |
| 16 | 2026-05-02 | TASK-033 | patch | 2 arquivos — ml/src/train.py, ml/src/evaluate.py | Validação splits.json vs config ativo | Previne reuso de splits stale |
| 17 | 2026-05-03 | TASK-030+ | patch | 1 arquivo — ml/src/preprocess.py | RandomContrast value_range=(0.0, 1.0) | Mesmo bug do brightness, encontrado pelo Codex |
| 18 | 2026-05-03 | TASK-025+ | patch | 1 arquivo — ml/src/evaluate.py | labels explícitos em confusion_matrix/classification_report | Previne mismatch com classes ausentes |
| 19 | 2026-05-03 | TASK-033+ | patch | 3 arquivos — dataset.py, train.py, evaluate.py | Persistir e validar val_split/test_split no manifest | Previne reuso com frações alteradas |
| 20 | 2026-05-03 | TASK-032+ | patch | 1 arquivo — ml/src/dataset.py | Validação de ≥3 grupos por classe antes do split | Previne falha silenciosa do stratify |
| 21 | 2026-05-03 | TASK-034 | patch | 2 diretórios — ml/models/v1/, ml/models/v2/ | Limpeza de artefatos obsoletos (v1+v2). .gitkeep adicionado | Prepara retreino limpo como v3 |
| 22 | 2026-05-03 | TASK-035 | patch | 2 arquivos — ml/config.yaml, ml/tests/test_model_output.py | fine_tune_learning_rate 1e-5→1e-4 | Previne catastrophic forgetting no Phase 2 |
| 23 | 2026-05-03 | TASK-036 | patch | 2 arquivos — ml/config.yaml, ml/tests/test_preprocess.py | Augmentation conservador para textura | rotation 40→15, vertical_flip removido |
| 24 | 2026-05-03 | TASK-037 | patch | 3 arquivos — ml/src/dataset.py, train.py, evaluate.py | validate_splits_against_config extraída para dataset.py | Elimina duplicação de 33 linhas |
| 25 | 2026-05-03 | TASK-038 | patch | 1 arquivo — ml/src/preprocess.py | Zoom calcula ambos os limites da config | Fix: zoom assimétrico agora correto |
| 26 | 2026-06-02 | TASK-039 (README) | minor | 1 arquivo — README.md (raiz) | README reescrito no padrão de portfólio (readme_model.md) | Checklist agêntico: aplicado. Classes corrigidas 12→5. NOTA: id TASK-039 também usado na branch UI (design tokens) — ver #27 |
| 27 | 2026-05-03 | TASK-039 (UI) | minor | 6 arquivos — lib/core/theme/ + pubspec.yaml | Design tokens v2: Manrope+Inter, soil texture colors, AppRadius, warning colors | Checklist agêntico: aplicado |
| 28 | 2026-05-03 | TASK-040 | major | 1 arquivo — lib/core/features/home/home_page.dart | HomeScreen v2: hero, stats grid, last analysis card, lot map placeholder | Checklist agêntico: aplicado |
| 29 | 2026-05-03 | TASK-043 | patch | 2 arquivos — processing_screen.dart + app_router.dart | Tela de processamento: animação pulsante, progress bar, texto contextual | Checklist agêntico: aplicado |
| 30 | 2026-05-03 | TASK-047 | minor | 2 arquivos — onboarding_screen.dart + app_router.dart | Onboarding 3 passos: enquadramento, iluminação, ângulo. Flag SharedPreferences adiada | Checklist agêntico: aplicado |
| 31 | 2026-05-03 | TASK-048 | minor | 2 arquivos — details.dart + app_router.dart | DetailsScreen v2: SliverAppBar hero, confidence badges, info tiles, action buttons | Checklist agêntico: aplicado |
| 32 | 2026-05-03 | TASK-049 | patch | 1 arquivo — ml/README.md | README ML: v2→v1, LR Phase 2 corrigido, seção Versioning | Checklist agêntico: N/A |
| 33 | 2026-05-03 | TASK-050 | patch | 5 arquivos — router, home, details, main, onboarding | Codex review: 7 fixes (guarded casts, NaN, null id, PopScope, overflow) | Review cruzado (Codex): aplicado |
| 34 | 2026-05-03 | TASK-009 | patch | 2 arquivos — details.dart + confidence_level.dart | ConfidenceLevel enum, banners baixa/moderada na DetailsScreen | Checklist agêntico: aplicado |
| 35 | 2026-05-03 | TASK-014 | minor | 2 arquivos — history_screen.dart + error_state.dart | ErrorState widget, LoadingIndicator padronizado | Checklist agêntico: aplicado |
| 36 | 2026-05-03 | TASK-015 | minor | 3 arquivos — settings_screen.dart, app_router.dart, pubspec.yaml | Tela de configurações com versão, onboarding link, apagar dados | Checklist agêntico: aplicado |
| 37 | 2026-05-03 | TASK-044 | minor | 2 arquivos — result_screen.dart + app_router.dart | ResultScreen com classe textural, badge confiança, banners | Checklist agêntico: aplicado |
| 38 | 2026-05-03 | TASK-016 | patch | 3 arquivos — home_stats.dart, repository_provider.dart, home_page.dart | homeStatsProvider derivado do stream, HomeScreen consome | Checklist agêntico: aplicado |
| 39 | 2026-05-04 | TASK-051 | patch | 3 arquivos — main.dart, pubspec.yaml, assets/fonts/ (5 TTFs) | Google Fonts bundled localmente, runtime fetching desabilitado | Checklist agêntico: aplicado |
| 40 | 2026-05-05 | TASK-052 | patch | 1 arquivo — capture_screen.dart | Chips sobrepostos na preview: localização + classificação sobre gradient | Checklist agêntico: aplicado |
| 41 | 2026-05-05 | TASK-010 | minor | 4 arquivos — permission_service.dart, permission_denied_view.dart, capture_screen.dart, pubspec.yaml | Tratamento de permissão negada: PermissionService, PermissionDeniedView, integração na CaptureScreen | Checklist agêntico: aplicado |
| 42 | 2026-05-05 | TASK-012 | minor | 4 arquivos — history_screen.dart, soil_record_repository.dart, drift_repo.dart, providers.dart | Filtros e busca no histórico: chips por classe textural, busca por endereço com debounce | Checklist agêntico: aplicado |
| 43 | 2026-05-07 | TASK-053 | patch | 1 arquivo — .claude/CLAUDE.md | Estrutura documentada atualizada com regras 10-12 | Checklist agêntico: N/A |
| 44 | 2026-05-07 | TASK-041 | minor | 3 arquivos — setup_screen.dart, capture_context.dart, app_router.dart | Tela de setup pré-captura: wizard 3 passos (lote/cultura/profundidade) | Checklist agêntico: aplicado |
| 45 | 2026-05-07 | TASK-045 | major | 5 arquivos — recommendations_screen.dart, management_plan.dart, app_router.dart, details.dart, result_screen.dart | Tela de recomendações: 3 abas, loading, FAB chat, dados mock por textura | Checklist agêntico: aplicado |
| 46 | 2026-05-07 | TASK-046 | minor | 3 arquivos — lot_detail_screen.dart, app_router.dart, home_page.dart | Tela de detalhes do lote: stats, comparação A/B, timeline, lotes na home | Checklist agêntico: aplicado |
| 47 | 2026-05-07 | TASK-054 | minor | 2 arquivos — splash_screen.dart, app_router.dart | Splash screen com logo animado e solicitação de permissões | Checklist agêntico: aplicado |
| 48 | 2026-05-07 | TASK-055 | patch | 3 arquivos — lot_detail_screen.dart, setup_screen.dart, capture_context.dart | Remoção de comparação temporal, emojis substituídos por Material Icons | Checklist agêntico: aplicado |
| 49 | 2026-05-07 | TASK-056 | patch | 4 arquivos — capture_screen.dart, settings_screen.dart, repository (2) | Guard _isSaving, deleteAll() no repository, sintaxe ?trailing validada | Checklist agêntico: aplicado |
| 50 | 2026-05-07 | TASK-057 | minor | 2 arquivos — main_screen.dart, recommendations_screen.dart | Navegação inferior com 3 abas, seletor de classe textural, chat removido | Checklist agêntico: aplicado |
| 51 | 2026-06-03 | TASK-058 | patch | 1 arquivo — android/build.gradle.kts | Alinhamento de JVM target (Java/Kotlin 17) nos plugins; corrige build Android | Causa: tflite_flutter fixa Java 11; resolvido via afterEvaluate + state.executed |
| 52 | 2026-06-03 | TASK-059 | minor | 3 arquivos — README.md, .claude/registry.md, .claude/tasks.md | Reconciliação do merge main→dev: conflitos resolvidos. README mantido no template da main com info atualizada; registry com base de histórico da main + entradas da dev; framework v1.1.0 da dev preservado (rules 10/11 consolidadas) | Merge acidental da branch UI na dev; conflitos só em docs/governança |

## Estado da Codebase

> Atualizado a cada implementação ou verificação pós-pull. Reflete o snapshot mais recente do projeto.

- **Última atualização:** 2026-06-03
- **Último responsável:** Claude Code (Opus 4.8)
- **Branch ativa:** dev (merge de main reconciliado, pronta para PR dev→main)
- **Versão:** 2.0.0 (bump pendente antes do merge — múltiplas tasks patch/minor desde v2.0.0)
- **Dependências alteradas recentemente:** pubspec.yaml — permission_handler ^11.3.1 adicionado; tflite_flutter ^0.12.1
- **Testes passando:** sim (Flutter 15/15 — unit + repository)
- **Análise estática:** flutter analyze — No issues found
- **Build Android:** OK — assembleDebug compila e instala no emulador (corrigido em TASK-058; toolchain Flutter 3.44.1 / AGP 8.11.1 / Kotlin 2.2.20 / JDK 21)
- **Divergências externas pendentes:** splits.json deletado — deve ser regenerado no venv ML antes do próximo treino
- **Última task concluída:** TASK-059 — reconciliação do merge dev→main
- **Review cruzado (Codex):** aplicado — auditoria 2026-05-07 com 1 CRITICAL (sintaxe validada como Dart 3), 2 HIGH (rotas desconectadas — intencional para demo), 4 MEDIUM (3 corrigidos: _isSaving guard, deleteAll, sintaxe), 1 LOW (corrigido)
- **Schema DB:** v2 (soil_records com texture_class, confidence_score)

## Pendências Conhecidas

- TFLite model (assets/models/soil_classifier.tflite) — modelo v3 (MobileNetV2) deployado via TASK-027. Próximo retreino deve gerar nova versão a partir do pipeline corrigido
- Recomendações de manejo são dados mock — `ManagementPlan.forTextureClass` retorna ações/fontes/alertas hardcoded por classe; preview de UI pendente de fonte de dados real (planejado: research agent)
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
- **2026-06-03:** Merge acidental da branch `feat/TASK-039-048-ui-redesign-v2` (PR #32) na `dev`. Reconciliação do merge `main`→`dev` (TASK-059): conflitos apenas em `README.md`, `.claude/registry.md` e `.claude/tasks.md` — nenhum conflito de código. **Framework de governança:** a `dev` carrega a v1.1.0 (commit a25d5bc), que consolidou o conteúdo de `rules/10` e `rules/11` dentro das rules 00-08 e removeu os arquivos standalone; a `main` permanecia na estrutura antiga (rules 10/11 separadas). O merge preserva corretamente a v1.1.0 da `dev` — ao mergear na `main`, os arquivos `rules/10` e `rules/11` serão removidos (conteúdo já consolidado nas rules core), e os templates voltam a `.claude/templates/`. Conteúdo de regras preservado, sem perda. Para registry/tasks: base de histórico da `main` (registry) + entradas e organização da `dev`. Colisão de id TASK-039 preservada como #26 (README) e #27 (design tokens UI). CI verde: analyze sem issues, 15/15 testes.
