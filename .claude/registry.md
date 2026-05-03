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

## Estado da Codebase

> Atualizado a cada implementação ou verificação pós-pull. Reflete o snapshot mais recente do projeto.

- **Última atualização:** 2026-05-03
- **Último responsável:** Claude Code (Opus 4)
- **Branch ativa:** feat/TASK-006-ml-platform
- **Versão:** 1.1.0 (próxima: 2.0.0 após merge — task major)
- **Dependências alteradas recentemente:** pubspec.yaml — tflite_flutter ^0.12.1 (era ^0.11.0); ml/config.yaml — architecture: mobilenetv2, normalization: mobilenet_v2
- **Testes passando:** sim (Flutter 15/15 — unit + repository; ML — sintaxe validada, TF indisponível no Python 3.14 local)
- **Divergências externas pendentes:** splits.json deletado — deve ser regenerado no venv ML antes do próximo treino
- **Última task concluída:** TASK-038 — Fix zoom_factor no preprocess.py
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
- **2026-04-29:** TASK-006 concluída — diretório ml/ criado com pipeline ML reproduzível. Decisão de não reestruturar para /app/ tomada durante planejamento (Flutter permanece na raiz). 23 arquivos criados, 1 editado (.gitignore raiz).
