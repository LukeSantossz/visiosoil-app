# Registro de Projeto — Arquivo de Histórico

> Entradas movidas automaticamente do `registry.md` quando o histórico ultrapassou 30 entradas.
> Este arquivo é cumulativo e nunca editado após a inserção.

## Histórico Arquivado

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
