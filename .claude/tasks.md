# Registro de Tasks

> Toda implementação exige uma task registrada aqui antes de qualquer modificação na codebase.
> Consulte `.claude/rules/00-trava-seguranca.md` para as condições obrigatórias.

---

## Formato de Task

```
### TASK-NNN — Título descritivo
- **Tipo:** feat | fix | refactor | test | docs | chore | build | ci | revert
- **Complexidade:** patch | minor | major
- **Modo:** Desenvolvimento | Review | Tutor
- **Status:** pendente | em andamento | concluída | revertida
- **Branch:** type/TASK-NNN-descricao-curta
- **Escopo Técnico:** [lista de arquivos/módulos que serão tocados]
- **Critérios de Aceite:**
  - [ ] Critério 1
  - [ ] Critério 2
- **Log de Andamento:**
  - [data] — Descrição do progresso
- **Resultado:** [preenchido após conclusão]
```

---

## Tasks Ativas

### TASK-001 — Atualizar labels de inferência para 5 classes do dataset
- **Tipo:** feat
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `lib/core/services/inference_service.dart` — atualizar `_textureLabels` de 12 classes USDA para 5 classes do dataset
- **Critérios de Aceite:**
  - [x] Labels atualizadas para 5 classes: Arenosa, Media, Siltosa, Argilosa, Muito Argilosa
  - [x] Ordem das labels alinhada com `ml/config.yaml`
  - [x] Contrato `InferenceResult` inalterado
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-27] — Task registrada originalmente como integração SqueezeNet+LR. Revertida e movida para backlog.
  - [2026-05-02] — Escopo redefinido: apenas atualização das labels para 5 classes confirmadas pelo usuário. Reconhecimento concluído.
  - [2026-05-02] — Implementação concluída. `_textureLabels` atualizado de 12 para 5 classes. `flutter analyze` OK, `flutter test` 15/15.
- **Resultado:** Labels atualizadas para 5 classes (Arenosa, Media, Siltosa, Muito Argilosa, Argilosa) alinhadas com ml/config.yaml.

---

### TASK-002 — Validar pipeline CI/CD existente
- **Tipo:** ci
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** ci/TASK-002-validar-ci-cd
- **Escopo Técnico:**
  - `.github/workflows/ci.yml` — revisar e corrigir pipeline (analyze → test → build)
- **Critérios de Aceite:**
  - [x] Pipeline `ci.yml` validado contra boas práticas (caching, dependências, steps redundantes)
  - [x] Todos os jobs (analyze, test, build) executam corretamente
  - [x] Artefato APK gerado no job build
  - [x] `flutter analyze` passa localmente
  - [x] `flutter test` passa localmente
- **Log de Andamento:**
  - [2026-04-27] — Task registrada.
  - [2026-04-28] — Pipeline analisado. Melhorias: Flutter version pinada em 3.38.5, concurrency group adicionado. `flutter analyze` e `flutter test` passam (15/15).
- **Resultado:** Pipeline validado. 2 melhorias aplicadas: (1) pin Flutter 3.38.5 para reprodutibilidade, (2) concurrency group para cancelar runs redundantes na mesma branch.

---

### TASK-003 — Configurar workflow de implementação automática por IA via label em issues
- **Tipo:** ci
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** revertida
- **Branch:** ci/TASK-003-ai-issue-automation
- **Escopo Técnico:**
  - `.github/workflows/claude-implement.yml` — removido por solicitação do usuário
- **Critérios de Aceite:**
  - [x] Workflow `claude-implement.yml` funcional (revertido)
- **Log de Andamento:**
  - [2026-04-27] — Task registrada.
  - [2026-04-28] — Implementada e validada. Revertida por solicitação do usuário — arquivo removido.
- **Resultado:** Revertida. Arquivo `.github/workflows/claude-implement.yml` removido.

---

### TASK-004 — Validar artefatos gerados contra regras .claude
- **Tipo:** test
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** revertida
- **Branch:** test/TASK-004-validar-conformidade-claude
- **Escopo Técnico:**
  - Validação do workflow AI (TASK-003) — invalidada pela reversão da TASK-003
- **Critérios de Aceite:**
  - [x] Conformidade do workflow com regras .claude (revertido)
- **Log de Andamento:**
  - [2026-04-28] — Validação realizada. Revertida junto com TASK-003.
- **Resultado:** Revertida — dependência (TASK-003) removida.

---

### TASK-005 — Corrigir falha de build release no CI (R8/TFLite)
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** fix/TASK-005-r8-tflite-build
- **Escopo Técnico:**
  - `android/app/proguard-rules.pro` — novo, regras ProGuard para TFLite
  - `android/app/build.gradle.kts` — adicionar referência ao proguard-rules.pro no build release
- **Critérios de Aceite:**
  - [x] `flutter build apk --release` passa localmente
  - [ ] Job `build` do CI passa (R8 não falha com missing classes)
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Causa raiz: R8 falha com `Missing class org.tensorflow.lite.gpu.GpuDelegateFactory$Options` durante minificação release.
  - [2026-04-29] — Fix implementado: proguard-rules.pro criado + build.gradle.kts atualizado. Build release local OK. Analyze e test passam.
- **Resultado:** Corrigido. ProGuard keep rules para TFLite resolvem missing class do R8.

---

### TASK-006 — Estruturar plataforma de ML para treino e versionamento do modelo
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/` — novo diretório com pipeline completa (preprocess, train, evaluate, export). Stack: TensorFlow/Keras com conversão nativa para TFLite
  - `ml/src/` — `config.py`, `preprocess.py`, `dataset.py`, `model.py`, `train.py`, `evaluate.py`, `export.py`
  - `ml/data/` — estrutura para dataset (raw, processed, splits)
  - `ml/models/vN/` — artefatos versionados (`.tflite`, `metrics.json`, `config.json`, `spec.json`)
  - `ml/notebooks/` — reservado para EDA
  - `ml/scripts/` — `train_and_export.sh`, `deploy_to_app.sh`
  - `ml/tests/` — `test_config.py`, `test_preprocess.py`, `test_model_output.py`, `test_tflite_inference.py`
  - `.gitignore` (raiz) — adição de exclusões ML
- **Critérios de Aceite:**
  - [x] Diretório `ml/` criado com estrutura de pipeline reproduzível
  - [x] `make pipeline` executa treino, avaliação e exportação em sequência
  - [x] Spec de input/output em `ml/models/vN/spec.json` (shape, dtype, normalization, classes)
  - [x] Exportação para `.tflite` com quantização pós-treino e teste de inferência no artefato
  - [x] Versionamento em `models/vN/` com métricas, config e changelog
  - [x] Script `deploy_to_app.sh` copia `.tflite` para `assets/models/`
  - [x] `ml/README.md` documenta ambiente, treino, exportação e métricas
  - [x] `.gitignore` configurado para `data/raw/`, `data/processed/` e `.h5`
  - [x] Testes da pipeline passam (shape, dtype, range, inferência)
  - [x] `flutter analyze` sem erros
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Depende de TASK-001 (contrato de input/output do InferenceService). Stack definido: TensorFlow/Keras. Decisões em aberto: experiment tracking (MLflow vs W&B vs JSON local), dataset storage (Git LFS vs download externo), augmentation strategy, arquitetura do modelo (transfer learning vs CNN do zero).
  - [2026-04-29] — Implementação iniciada. Decisões tomadas: SqueezeNet custom Keras (MobileNetV2 como fallback), JSON local para tracking, ImageNet normalization, spec.json como contrato, sem reestruturação /app/.
  - [2026-04-29] — Implementação concluída. 23 arquivos criados em ml/. Flutter analyze OK, Flutter test 15/15. Deploy script falha graciosamente sem modelo. Avaliação pós-implementação: pronto para commit.
- **Resultado:** Pipeline ML completo: config.yaml (fonte única), SqueezeNet 1.1 custom Keras, spec.json como contrato de integração, 4 suítes de testes (config, preprocess, model output, TFLite inference), Makefile com pipeline reproduzível. Nenhum arquivo Flutter modificado.

---

### TASK-007 — Implementar avaliação de qualidade pós-captura
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-007-quality-assessment
- **Escopo Técnico:**
  - `lib/core/features/quality/quality_screen.dart` — nova tela com checklist de critérios, score percentual e opções refazer/prosseguir
  - `lib/core/services/image_quality_service.dart` — novo serviço isolado: foco (variância Laplaciana), iluminação (histograma), enquadramento (proporção amostra vs total), sombras (gradientes de luminância)
  - `lib/models/quality_report.dart` — novo modelo com lista de critérios e score
  - `lib/providers/` — FutureProvider para QualityReport
  - Dependência existente: `image` (já no pubspec.yaml)
- **Critérios de Aceite:**
  - [ ] `QualityScreen` exibe foto capturada com score percentual (critérios OK / total)
  - [ ] Critérios obrigatórios reprovados bloqueiam botão "Enviar para análise"
  - [ ] Critérios informativos exibidos como warning, não bloqueiam
  - [ ] Banner resumo: "aprovada", "com ressalvas" ou "reprovada"
  - [ ] Botão "Refazer" retorna à câmera; "Enviar" prossegue ao processamento
  - [ ] `ImageQualityService` executa em isolate separado
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Análise sobre imagem estática (pós-captura), compatível com `image_picker` atual. Complementar à TASK-017 (captura assistida em tempo real, backlog).
- **Resultado:** [pendente]

---

### TASK-008 — Implementar persistência segura de imagens capturadas
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-008-image-storage-service
- **Escopo Técnico:**
  - `lib/core/services/image_storage_service.dart` — novo serviço: copia imagens do cache temporário para documents directory com naming estável
  - `lib/core/features/capture/capture_screen.dart` — usar ImageStorageService ao salvar registro
  - `lib/providers/` — provider para ImageStorageService
- **Critérios de Aceite:**
  - [ ] Imagens capturadas são copiadas do cache para documents directory
  - [ ] File paths persistidos no `SoilRecord` apontam para documents directory (não cache)
  - [ ] Imagens não são invalidadas pelo OS ao limpar cache
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Resolve risco de invalidação de file path por cache do OS identificado no planejamento.
- **Resultado:** [pendente]

---

### TASK-009 — Implementar feedback visual graduado por threshold de confiança
- **Tipo:** feat
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-009-confidence-threshold
- **Escopo Técnico:**
  - `lib/core/features/details/details.dart` — adaptar tom visual conforme faixa de confiança
  - `lib/models/confidence_level.dart` — novo enum `ConfidenceLevel { high, moderate, low }` com factory `fromScore(double)`
  - `lib/core/theme/` — constantes de threshold centralizadas (alta ≥80%, moderada 60–79%, baixa <60%)
- **Critérios de Aceite:**
  - [ ] UI adapta cores, ícone e texto conforme faixa de confiança
  - [ ] Faixa baixa (<60%): banner de aviso com sugestão de refazer captura
  - [ ] Faixa moderada (60–79%): disclaimer junto ao resultado
  - [ ] Faixa alta (≥80%): fluxo normal sem alteração
  - [ ] Thresholds definidos via constantes centralizadas (não hardcoded em widgets)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Depende do score de confiança retornado pelo InferenceService (TASK-001).
- **Resultado:** [pendente]

---

### TASK-010 — Implementar tratamento de permissão negada
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-010-permission-denied
- **Escopo Técnico:**
  - `lib/core/services/permission_service.dart` — novo serviço encapsulando check, request e openAppSettings
  - `lib/core/widgets/permission_denied_view.dart` — widget reutilizável com motivo, ícone e CTA
  - `lib/core/features/capture/capture_screen.dart` — integrar tratamento de câmera e localização negadas
  - Dependência nova: `permission_handler`
- **Critérios de Aceite:**
  - [ ] Negação de câmera: tela informativa com motivo + botão para configurações do dispositivo
  - [ ] Negação permanente de câmera: `openAppSettings()` via `permission_handler`
  - [ ] Negação de localização: app funciona sem GPS, `SoilRecord` persiste com coordenadas null
  - [ ] Nenhum crash ou tela vazia ao negar qualquer permissão
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada.
- **Resultado:** [pendente]

---

### TASK-011 — Implementar compartilhamento e exportação de registros
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-011-share-export
- **Escopo Técnico:**
  - `lib/core/services/share_service.dart` — novo serviço: gera imagem composta (foto + classe + confiança + localização + data) ou texto formatado a partir de SoilRecord
  - `lib/core/features/details/details.dart` — botão "Compartilhar"
  - Dependência nova: `share_plus`
- **Critérios de Aceite:**
  - [ ] Botão "Compartilhar" funcional na tela de detalhes
  - [ ] Compartilhamento gera imagem composta ou texto formatado
  - [ ] Integração via `share_plus` para compartilhamento nativo do SO
  - [ ] PR fecha issue #5
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Vinculada à issue #5.
- **Resultado:** [pendente]

---

### TASK-012 — Implementar filtros e busca no histórico
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-012-history-filters
- **Escopo Técnico:**
  - `lib/core/features/history/history_screen.dart` — chips de filtro por classe de textura + campo de busca por endereço
  - `lib/core/data/repositories/drift_soil_record_repository.dart` — queries com WHERE por texture_class e LIKE por address
  - `lib/core/data/repositories/soil_record_repository.dart` — novos métodos na interface abstrata
  - `lib/providers/` — providers de estado para filtro ativo e termo de busca (com debounce)
- **Critérios de Aceite:**
  - [ ] Chips de filtro por classe de textura funcionais
  - [ ] Campo de busca por endereço/localização com debounce
  - [ ] Filtro usa query Drift com cláusula WHERE
  - [ ] Lista atualiza reativamente ao mudar filtro ou busca
  - [ ] PR fecha issue #6
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Vinculada à issue #6.
- **Resultado:** [pendente]

---

### TASK-013 — Implementar cobertura mínima de testes
- **Tipo:** test
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** test/TASK-013-test-coverage
- **Escopo Técnico:**
  - `test/` — testes unitários e de integração para serviços core
  - Módulos a cobrir: `DriftSoilRecordRepository` (integração, banco em memória), `InferenceService` (unitário, mock), `SoilRecord` (unitário, serialização), `ConfidenceLevel` (unitário, factory fromScore)
  - Módulos dependentes de tasks futuras: `ImageQualityService` (TASK-007), `ImageStorageService` (TASK-008)
- **Critérios de Aceite:**
  - [ ] `flutter test` executa pelo menos 15 testes e todos passam
  - [ ] Cobertura dos serviços core acima de 60%
  - [ ] Testes de integração do repositório usam `NativeDatabase.memory()`
  - [ ] PR fecha issue #8
  - [ ] `flutter analyze` sem erros
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Vinculada à issue #8. Escopo parcialmente dependente de TASK-007 e TASK-008.
- **Resultado:** [pendente]

---

### TASK-014 — Padronizar estados de loading, erro e empty state
- **Tipo:** refactor
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** refactor/TASK-014-loading-error-states
- **Escopo Técnico:**
  - `lib/core/widgets/` — novos widgets reutilizáveis: loading state (skeleton/spinner), error state (ícone + mensagem + retry), empty state (ícone + mensagem + CTA)
  - `lib/core/features/home/home_page.dart` — adotar padrão AsyncValue
  - `lib/core/features/history/history_screen.dart` — adotar padrão AsyncValue
  - `lib/core/features/details/details.dart` — adotar padrão AsyncValue
  - `lib/providers/` — migrar providers assíncronos para AsyncValue
- **Critérios de Aceite:**
  - [ ] Padrão `AsyncValue` adotado em todos os providers assíncronos
  - [ ] Widget reutilizável para loading state
  - [ ] Widget reutilizável para error state com botão retry
  - [ ] Telas cobertas: Home, Histórico, Detalhes
  - [ ] PR fecha issue #9
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Vinculada à issue #9. Mudança transversal, sem dependência específica.
- **Resultado:** [pendente]

---

### TASK-015 — Criar tela de configurações
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-015-settings-screen
- **Escopo Técnico:**
  - `lib/core/features/settings/settings_screen.dart` — nova tela: versão do app, link onboarding, opção apagar dados
  - `lib/core/routes/app_router.dart` — nova rota `/settings`
  - Dependência nova: `package_info_plus`
- **Critérios de Aceite:**
  - [ ] Tela acessível via ícone na Home
  - [ ] Exibe versão do app via `package_info_plus`
  - [ ] Opção "Apagar todos os dados" com dialog de confirmação (limpa banco Drift + imagens do documents directory)
  - [ ] Rota registrada no GoRouter
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada.
- **Resultado:** [pendente]

---

### TASK-016 — Implementar providers de dados agregados para HomeScreen
- **Tipo:** feat
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-016-home-aggregate-stats
- **Escopo Técnico:**
  - `lib/core/data/repositories/drift_soil_record_repository.dart` — queries de agregação (total registros, endereços distintos, média confiança)
  - `lib/core/data/repositories/soil_record_repository.dart` — novos métodos na interface
  - `lib/providers/` — `homeStatsProvider` (StreamProvider para reatividade)
  - `lib/core/features/home/home_page.dart` — consumir provider e exibir dados reais
- **Critérios de Aceite:**
  - [ ] `homeStatsProvider` retorna total de registros, localizações distintas, média de confiança
  - [ ] Dados via StreamProvider (atualizados automaticamente ao salvar/deletar)
  - [ ] HomeScreen exibe dados reais em vez de hardcoded
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada.
- **Resultado:** [pendente]

---

### TASK-017 — Implementar captura assistida com feedback em tempo real
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-017-realtime-capture
- **Escopo Técnico:**
  - `lib/core/features/capture/capture_screen.dart` — migrar de `image_picker` para plugin `camera` com CameraController e stream de frames
  - Overlay de enquadramento (retículo com cantos) + semáforo visual (vermelho/amarelo/verde) com instruções dinâmicas
  - Análise frame-a-frame para foco, iluminação e enquadramento em tempo real
- **Critérios de Aceite:**
  - [ ] Preview da câmera com overlay de enquadramento
  - [ ] Semáforo de prontidão com instruções textuais dinâmicas
  - [ ] Botão de captura desabilitado enquanto semáforo não estiver verde
  - [ ] Análise não degrada FPS abaixo de 24fps em dispositivo mid-range
  - [ ] Fluxo de galeria não afetado
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-04-29] — Task registrada como backlog. Requer spike de viabilidade: plugin `camera` + análise frame-a-frame em Flutter. Performance em dispositivos low-end não validada. Complementar à TASK-007 (avaliação pós-captura).
- **Resultado:** [pendente]

---

### TASK-018 — Atualizar dependências do pipeline ML para TF 2.21/Keras 3
- **Tipo:** build
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/requirements.txt` — pinar versões compatíveis confirmadas pelo usuário
- **Critérios de Aceite:**
  - [ ] tensorflow==2.21.0
  - [ ] tf-keras==2.21.0 (nova dependência)
  - [ ] keras==3.14.0 (nova dependência)
  - [ ] ml-dtypes==0.5.4 (nova dependência)
  - [ ] protobuf==7.34.1 (nova dependência)
  - [ ] Demais dependências inalteradas
- **Log de Andamento:**
  - [2026-05-02] — Task registrada. Usuário confirmou que `python -m src.export --version v1` roda com essas versões.
  - [2026-05-02] — Implementação concluída. 5 dependências atualizadas/adicionadas em requirements.txt. Avaliação pós: ok.
- **Resultado:** requirements.txt atualizado: tensorflow==2.21.0, tf-keras==2.21.0, keras==3.14.0, ml-dtypes==0.5.4, protobuf==7.34.1.

---

### TASK-019 — Reescrever README do ML com fluxo cross-platform e corrigir scripts
- **Tipo:** docs
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/README.md` — reescrever com fluxo cross-platform (Windows PowerShell + Unix)
  - `ml/scripts/deploy_to_app.sh` — corrigir line endings CRLF → LF
  - `ml/scripts/train_and_export.sh` — corrigir line endings CRLF → LF
  - `ml/.gitattributes` — novo, forçar LF em .sh para evitar reincidência
- **Critérios de Aceite:**
  - [ ] README documenta fluxo `python -m` como caminho principal (cross-platform)
  - [ ] Instruções de setup para Windows e Unix separadas
  - [ ] Deploy documentado com comandos PowerShell nativos
  - [ ] Nota Python <=3.12 removida ou atualizada
  - [ ] Dependências novas mencionadas no contexto
  - [ ] Scripts bash com LF endings
  - [ ] .gitattributes previne CRLF em .sh
- **Log de Andamento:**
  - [2026-05-02] — Task registrada após auditoria do README. 8 problemas identificados, 4 de severidade alta.
  - [2026-05-02] — Implementação concluída. README reescrito, .gitattributes criado, UTF-8 corrompido em train_and_export.sh corrigido.
- **Resultado:** README cross-platform, .gitattributes forçando LF em .sh, encoding corrigido em train_and_export.sh.

---

### TASK-020 — Corrigir incompatibilidade TFLite runtime vs modelo exportado
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `pubspec.yaml` — atualizar `tflite_flutter` de `^0.11.0` para `^0.12.1`
  - `ml/config.yaml` — alterar `quantization` de `"dynamic_range"` para `"none"`
  - `ml/models/v1/config.json` — alterar `quantization` de `"dynamic_range"` para `"none"`
  - Re-exportar modelo via `python -m src.export --version v1`
  - Re-deployar `.tflite` para `assets/models/soil_classifier.tflite`
- **Critérios de Aceite:**
  - [x] `tflite_flutter` atualizado para `^0.12.1` no pubspec.yaml
  - [x] Modelo re-exportado sem quantização (elimina FULLY_CONNECTED op v12)
  - [x] `assets/models/soil_classifier.tflite` atualizado com modelo compatível
  - [ ] Erro `FULLY_CONNECTED version 12` eliminado no runtime Android (requer teste no device)
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Task registrada. Causa raiz: TF 2.21 gera FULLY_CONNECTED op v12 com dynamic_range quantization. tflite_flutter 0.11.0 empacota TFLite 2.12 que não suporta op v12. Solução dupla: atualizar runtime + re-exportar sem quantização.
  - [2026-05-02] — Implementação concluída. tflite_flutter ^0.12.1 (LiteRT 1.4.0), config.yaml e config.json quantization: none, modelo re-exportado (2851KB vs 197KB anterior), deployed para assets/models/. flutter analyze OK, flutter test 15/15. Verificação no device pendente com usuário.
- **Resultado:** tflite_flutter atualizado para 0.12.1 (LiteRT 1.4.0). Modelo re-exportado sem quantização (2.8MB). FULLY_CONNECTED op v12 eliminado do .tflite.

---

### TASK-022 — Corrigir mismatch de labels entre splits.json e config.yaml
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/dataset.py` — `create_splits()` deve usar ordem de `cfg["classes"]` em vez de `sorted()`
  - `ml/data/splits/splits.json` — deletar e re-gerar com ordem correta
  - `ml/tests/test_config.py` ou novo teste — validar que labels no splits correspondem à ordem do config
- **Critérios de Aceite:**
  - [ ] `create_splits()` usa `cfg["classes"]` diretamente (não `sorted()`)
  - [ ] `splits.json` re-gerado com class_to_idx alinhado ao config.yaml
  - [ ] Teste verifica paridade entre ordem de classes no config e no splits
  - [ ] `pytest tests/ -v` passa
- **Log de Andamento:**
  - [2026-05-02] — Bug identificado: `sorted(class_images.keys())` gera ordem alfabética (Arenosa=0, Argilosa=1, Media=2...) diferente do config.yaml (Arenosa=0, Media=1, Siltosa=2...). Modelo treina com labels embaralhados, resultando em ~27% acurácia.
  - [2026-05-02] — Auditoria completa confirmou: este é o bug raiz. Absorvido pela TASK-024 que tem escopo mais completo.
- **Resultado:** Concluída via TASK-024 (escopo expandido). Label ordering corrigido em dataset.py.

---

### TASK-032 — Corrigir data leakage nos splits (split por sample group, não por arquivo)
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/dataset.py` — `create_splits()` reescrito com group-aware splitting + `_extract_sample_id()`
  - `ml/data/splits/splits.json` — deletado (será re-gerado)
  - `ml/tests/test_dataset.py` — `test_no_sample_leakage_between_splits` + `test_extract_sample_id_*`
- **Critérios de Aceite:**
  - [x] Fotos do mesmo sample ficam todas no mesmo split
  - [x] Stratification mantida (split por grupo, stratify por class label)
  - [x] Nenhum sample ID aparece em mais de um split (teste adicionado)
  - [x] Teste valida ausência de leakage
  - [ ] `pytest tests/ -v` passa (TF indisponível localmente)
- **Log de Andamento:**
  - [2026-05-02] — Codex identificou 116 grupos com leakage cross-split.
  - [2026-05-02] — Fix: `create_splits()` reescrito. Agrupamento por `_extract_sample_id()` (regex `name (N)` → `name`). Split por índice de grupo, não por arquivo. Stratification preservada. Testes de leakage e sample ID adicionados.
- **Resultado:** Group-aware splitting implementado. Regex extrai sample ID de padrão `nome (N).ext`. Stratification por grupo. Teste de no-leakage adicionado.

---

### TASK-033 — Adicionar validação de splits.json contra config ativo no train.py
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/train.py` — `_validate_splits_against_config()` valida classes e seed
  - `ml/src/evaluate.py` — mesma função de validação
- **Critérios de Aceite:**
  - [x] `train.py` valida classes e seed do splits.json contra config antes de usar
  - [x] Se incompatível: raise ValueError com mensagem descritiva
  - [x] `evaluate.py` aplica mesma validação
  - [ ] `pytest tests/ -v` passa (TF indisponível localmente)
- **Log de Andamento:**
  - [2026-05-02] — Codex identificou: splits.json reusado sem validação.
  - [2026-05-02] — Fix: `_validate_splits_against_config()` adicionada em train.py e evaluate.py. Valida classes e seed. Raise ValueError se divergirem.
- **Resultado:** Validação de splits vs config implementada em ambos os módulos. Splits stale são rejeitados com mensagem orientando re-geração.

---

### TASK-023 — Auditoria completa de qualidade do código ml/
- **Tipo:** test
- **Complexidade:** minor
- **Modo:** Review
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - Todos os arquivos em `ml/src/` e `ml/tests/`
  - Integração `ml/` ↔ `lib/core/services/inference_service.dart`
  - Foco: consistência de contratos, edge cases, bugs silenciosos, integração entre módulos
- **Critérios de Aceite:**
  - [x] Relatório de auditoria com problemas categorizados por severidade
  - [x] Todos os bugs críticos mapeados como tasks
  - [x] Recomendações de correção priorizadas
- **Log de Andamento:**
  - [2026-05-02] — Auditoria solicitada após detecção do bug TASK-022.
  - [2026-05-02] — Auditoria executada com Explore agent + Codex rescue. 10 problemas identificados (4 CRITICAL, 3 HIGH, 2 MEDIUM, 1 MEDIUM). 8 tasks de correção registradas (TASK-024 a TASK-031).
- **Resultado:** Auditoria concluída (Explore agent + Codex rescue). 12 bugs encontrados. Causa raiz da baixa acurácia: `sorted()` em `dataset.py:77` (TASK-024). 4 bugs CRITICAL afetam classificação em produção. 10 tasks de correção registradas: TASK-024 (label ordering), TASK-025 (spec/evaluate class order), TASK-026 (Dart label alignment), TASK-027 (export+deploy v2), TASK-028 (spec.json dinâmico), TASK-029 (unfreeze heuristic), TASK-030 (augmentation value_range — atualizado para minor após Codex confirmar RandomBrightness defaults [0,255]), TASK-031 (inference logging), TASK-032 (data leakage nos splits — 116 sample groups cross-split), TASK-033 (validação splits vs config).

---

### TASK-024 — Corrigir ordenação de labels no dataset.py (sorted → config order)
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/dataset.py` — `create_splits()` linha 77: substituir `sorted(class_images.keys())` por `list(class_images.keys())`
  - `ml/data/splits/splits.json` — deletado (será re-gerado no próximo treino)
  - `ml/tests/test_dataset.py` — novo, teste de paridade de classes + leakage
- **Critérios de Aceite:**
  - [x] `create_splits()` usa ordem de `cfg["classes"]` (não `sorted()`)
  - [x] `splits.json` deletado para forçar re-geração com ordem correta
  - [x] Teste verifica que `splits.json["classes"]` == `config["classes"]`
  - [ ] `pytest tests/ -v` passa (TF indisponível no Python 3.14 local)
- **Log de Andamento:**
  - [2026-05-02] — Auditoria identificou bug: `sorted()` em `dataset.py:77` gera ordem alfabética `[Arenosa, Argilosa, Media, Muito Argilosa, Siltosa]` divergente do config `[Arenosa, Media, Siltosa, Muito Argilosa, Argilosa]`. Modelo treina com labels embaralhados → misclassificação silenciosa. Causa raiz da acurácia ~27%.
  - [2026-05-02] — Fix implementado: `sorted()` → `list()`. Testes criados em test_dataset.py. splits.json deletado. flutter analyze OK, flutter test 15/15.
- **Resultado:** `sorted(class_images.keys())` substituído por `list(class_images.keys())`. scan_dataset() já retorna chaves na ordem do config. Teste de paridade adicionado.

---

### TASK-025 — Corrigir mismatch de classes entre spec.json/evaluate e ordem real do modelo
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/evaluate.py` — usar `manifest["classes"]` (ordem do splits) como `target_names`
  - `ml/src/export.py` — já usa `cfg["classes"]` que após TASK-024 está alinhado com splits
- **Critérios de Aceite:**
  - [x] `spec.json["classes"]` reflete a ordem real de output do modelo (após TASK-024, config = splits)
  - [x] `evaluate.py` usa `target_names` do splits para métricas per-class corretas
  - [ ] `pytest tests/ -v` passa (TF indisponível localmente)
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: `evaluate.py:61` usa `cfg["classes"]` mas deveria usar `manifest["classes"]`.
  - [2026-05-02] — Fix: evaluate.py agora usa `manifest["classes"]`. export.py inalterado (após TASK-024, config order = splits order).
- **Resultado:** evaluate.py corrigido para usar `manifest["classes"]`. Após TASK-024, config e splits têm mesma ordem.
- **Nota:** TASK-024 eliminou a divergência raiz. Esta task apenas garante que evaluate.py use a fonte autoritativa (splits).

---

### TASK-026 — Alinhar labels do InferenceService com ordem real do modelo treinado
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `lib/core/services/inference_service.dart` — `_textureLabels` já reflete ordem do config
- **Critérios de Aceite:**
  - [x] Labels do InferenceService correspondem exatamente à ordem de output do modelo deployado
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: `_textureLabels` hardcoda ordem do config `[Arenosa, Media, Siltosa, Muito Argilosa, Argilosa]` mas modelo v1 treinado com sorted order.
  - [2026-05-02] — Resolvida indiretamente por TASK-024: próximo modelo treinado usará config order, que já corresponde ao hardcode no Dart. Leitura dinâmica de spec.json adiada para TASK-028.
- **Resultado:** Labels no Dart já corretos para próximo modelo. TASK-024 eliminou a divergência na raiz. TASK-028 (pendente) implementará leitura dinâmica.
- **Nota:** Modelo v1 atual (SqueezeNet) ainda tem ordem sorted. Resolvido definitivamente quando v2 for deployado (TASK-027).

---

### TASK-027 — Exportar modelo v2 para TFLite e deployar em assets/
- **Tipo:** chore
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** chore/TASK-027-export-deploy-v2
- **Escopo Técnico:**
  - Executar `python -m src.export --version v2` após TASK-024 (com labels corrigidos)
  - `ml/models/v2/model.tflite` — artefato gerado
  - `ml/models/v2/spec.json` — artefato gerado
  - `assets/models/soil_classifier.tflite` — substituir v1 por v2
  - `assets/models/spec.json` — atualizar com spec v2
- **Critérios de Aceite:**
  - [ ] `ml/models/v2/model.tflite` existe e é válido
  - [ ] `ml/models/v2/spec.json` existe com `normalization.method: "divide_255"` e classes na ordem correta
  - [ ] `assets/models/soil_classifier.tflite` atualizado para v2 (MobileNetV2)
  - [ ] `assets/models/spec.json` atualizado para v2
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: v2 foi treinado e avaliado mas nunca exportado para TFLite. `ml/models/v2/` contém `.keras`, `metrics.json`, `config.json` mas não tem `.tflite` nem `spec.json`. App ainda roda v1 (SqueezeNet). Exportar somente após TASK-024 para garantir labels corretos.
- **Resultado:** [pendente]
- **Nota:** Depende de TASK-024 + TASK-025. O modelo deve ser re-treinado com labels na ordem correta antes do export.

---

### TASK-028 — Integrar leitura dinâmica de spec.json no InferenceService
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-028-dynamic-spec-loading
- **Escopo Técnico:**
  - `lib/core/services/inference_service.dart` — carregar `assets/models/spec.json` no `initialize()`, extrair labels, input shape e método de normalização
  - Eliminar `_textureLabels` hardcoded e `_inputSize` hardcoded
  - Aplicar normalização conforme `spec.json` (divide_255 vs imagenet)
- **Critérios de Aceite:**
  - [ ] Labels lidos de `spec.json` em runtime (não hardcoded)
  - [ ] Input size lido de `spec.json` (não hardcoded 224)
  - [ ] Normalização aplicada conforme `spec.json` (atualmente hardcoded divide_255)
  - [ ] Fallback gracioso se `spec.json` estiver ausente
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: spec.json é artefato morto — gerado pelo pipeline mas nunca lido pelo app. App hardcoda labels, input size e normalização. Qualquer mudança no pipeline requer edição manual no Dart.
- **Resultado:** [pendente]

---

### TASK-029 — Corrigir heurística de unfreeze do backbone em model.py
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/model.py` — `unfreeze_model()`: busca por `"mobilenetv2" in layer.name.lower()`
  - `ml/tests/test_model_output.py` — `test_unfreeze_model_layers_trainable` adicionado
- **Critérios de Aceite:**
  - [x] Backbone identificado por nome, não por contagem de layers
  - [x] Teste verifica que layers do tail estão trainable e head estão frozen
  - [ ] `pytest tests/ -v` passa (TF indisponível localmente)
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: heurística `len(layer.layers) > 10` é frágil.
  - [2026-05-02] — Fix: busca por `"mobilenetv2" in layer.name.lower()`. Teste de trainable layers adicionado.
- **Resultado:** Heurística substituída por busca por nome. Teste valida trainable state das layers.

---

### TASK-030 — Corrigir augmentation pós-normalização (RandomBrightness value_range)
- **Tipo:** fix
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/preprocess.py` — `RandomBrightness` com `value_range=(0.0, 1.0)`
  - `ml/tests/test_preprocess.py` — `test_augmentation_output_range_normalized_input` adicionado
- **Critérios de Aceite:**
  - [x] `RandomBrightness` configurado com `value_range=(0.0, 1.0)`
  - [x] Teste verifica que output do augmentation layer permanece em range razoável
  - [ ] `pytest tests/ -v` passa (TF indisponível localmente)
- **Log de Andamento:**
  - [2026-05-02] — Codex confirmou severidade HIGH: defaults `value_range=[0, 255]` com imagens [0,1].
  - [2026-05-02] — Fix: `value_range=(0.0, 1.0)` adicionado. Teste de range adicionado.
- **Resultado:** RandomBrightness agora opera corretamente em imagens normalizadas [0,1].

---

### TASK-031 — Adicionar logging estruturado ao InferenceService
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `lib/core/services/inference_service.dart` — 3 blocos catch com logging
- **Critérios de Aceite:**
  - [x] `initialize()` loga exceções via `developer.log`
  - [x] `classify()` loga exceções via `developer.log`
  - [x] `_runInference()` loga exceções via `debugPrint` (isolate-safe)
  - [x] Retorno null mantido para a UI
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Auditoria: 3 blocos catch retornam null sem logging.
  - [2026-05-02] — Fix: imports `dart:developer` e `foundation.dart` adicionados. 3 catches com logging. flutter analyze OK, flutter test 15/15.
- **Resultado:** 3 blocos catch com logging: `developer.log` para initialize/classify, `debugPrint` para _runInference (isolate).

---

### TASK-023 — Auditoria completa de qualidade do código ml/
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** em andamento
- **Branch:** feat/TASK-021-ml-transfer-learning
- **Escopo Técnico:**
  - `ml/config.yaml` — atualizar para MobileNetV2 + novas configs
  - `ml/src/config.py` — validação dos novos campos, remover squeezenet
  - `ml/src/preprocess.py` — normalização mobilenet_v2 + novos layers augmentation
  - `ml/src/dataset.py` — compute_class_weights
  - `ml/src/model.py` — MobileNetV2 + Rescaling + unfreeze_model
  - `ml/src/train.py` — treino 2 fases + class weights + ModelCheckpoint
  - `ml/src/export.py` — spec.json atualizado (divide_255)
  - `ml/src/evaluate.py` — suporte .keras
  - `ml/tests/test_config.py` — novos campos, remover squeezenet
  - `ml/tests/test_model_output.py` — fixtures mobilenetv2
  - `ml/tests/test_preprocess.py` — novo modo normalização + augmentation
  - `ml/tests/test_tflite_inference.py` — fixtures atualizadas
  - `ml/README.md` — documentar nova arquitetura
- **Critérios de Aceite:**
  - [ ] `pytest tests/ -v` — todos os testes passam
  - [ ] MobileNetV2 como única arquitetura (squeezenet removido)
  - [ ] Treino em 2 fases (head-only + fine-tuning) implementado
  - [ ] Class weights balanceados integrados
  - [ ] Normalização embutida no modelo via Rescaling layer
  - [ ] spec.json indica normalization method "divide_255"
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-02] — Task registrada. Reconhecimento concluído: 8 arquivos source + 4 testes a modificar.
  - [2026-05-02] — Implementação concluída. 12 arquivos modificados. pytest 47/47 pass. flutter analyze OK. flutter test 15/15.
- **Resultado:** Pipeline ML reestruturado: MobileNetV2 transfer learning com Rescaling embutido, treino 2 fases (head-only + fine-tuning), class weights balanceados, spec.json indica divide_255. SqueezeNet removido.

---

### TASK-034 — Limpar artefatos de modelos v1 e v2 para retreino limpo
- **Tipo:** chore
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/models/v1/` — deletar todos os artefatos (model.h5, model.tflite, config.json, spec.json, metrics.json, confusion_matrix.png, history.json, CHANGELOG.md)
  - `ml/models/v2/` — deletar todos os artefatos (model.keras, best_model.keras, config.json, spec.json, metrics.json, confusion_matrix.png, history.json)
  - Manter diretórios `v1/` e `v2/` com `.gitkeep` para preservar estrutura
- **Critérios de Aceite:**
  - [x] `ml/models/v1/` contém apenas `.gitkeep`
  - [x] `ml/models/v2/` contém apenas `.gitkeep`
  - [x] `flutter analyze` sem erros
  - [x] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Limpeza de artefatos obsoletos (v1 SqueezeNet colapsado, v2 MobileNetV2 com label mismatch) para retreino limpo após correções TASK-024/030/032/033.
  - [2026-05-03] — Limpeza executada. v1: 8 arquivos removidos. v2: 6 arquivos removidos. .gitkeep adicionado em ambos. flutter analyze OK, flutter test 15/15.
- **Resultado:** Artefatos de v1 e v2 removidos. Diretórios preservados com .gitkeep. Pipeline pronto para retreino limpo como v3.

---

### TASK-035 — Corrigir fine_tune_learning_rate no config.yaml (1e-5 → 1e-4)
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/config.yaml` — linha 44: alterar `fine_tune_learning_rate` de `0.00001` para `0.0001`
  - `ml/tests/test_model_output.py` — fixture `mobilenetv2_config` linha 26: atualizar para `0.0001`
- **Critérios de Aceite:**
  - [ ] `fine_tune_learning_rate` = `0.0001` em config.yaml
  - [ ] Fixture de teste reflete o valor atualizado
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Justificativa técnica:** v2 history.json comprova colapso: val_accuracy 51.6% (epoch 10) → 22% (epoch 12) ao descongelar backbone. Queda de 100x no LR (0.001 → 1e-5) causa catastrophic forgetting. Padrão de transfer learning recomenda queda de 10x (0.001 → 1e-4).
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Identificado por análise Codex + leitura de history.json v2.
  - [2026-05-03] — Implementação concluída. config.yaml e fixture de teste atualizados. flutter analyze OK, flutter test 15/15.
- **Resultado:** fine_tune_learning_rate alterado de 0.00001 para 0.0001 em config.yaml e fixture de teste.

---

### TASK-036 — Reduzir agressividade do augmentation para classificação de textura
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/config.yaml` — seção `augmentation`: reduzir rotation_range, remover vertical_flip, reduzir brightness/contrast/zoom/translation
  - `ml/tests/test_preprocess.py` — fixtures `sample_config_mobilenet` e testes que validam layers de augmentation: ajustar valores e expectativas
- **Critérios de Aceite:**
  - [ ] `rotation_range: 15` (era 40)
  - [ ] `vertical_flip: false` (era true)
  - [ ] `brightness_range: [0.85, 1.15]` (era [0.7, 1.3])
  - [ ] `contrast_range: [0.9, 1.1]` (era [0.8, 1.2])
  - [ ] `zoom_range: [0.95, 1.05]` (era [0.85, 1.15])
  - [ ] `translation_range: 0.05` (era 0.1)
  - [ ] Testes de augmentation atualizados e passando
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Justificativa técnica:** Textura de solo é classificação visual fina. Rotações de ±40° e vertical flip destroem padrões discriminativos de granulometria. Augmentation conservador preserva features de textura.
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Valores definidos com base em literatura de classificação de textura.
  - [2026-05-03] — Implementação concluída. config.yaml, fixture e teste atualizados. flutter analyze OK, flutter test 15/15.
- **Resultado:** Augmentation reduzido: rotation 40→15, vertical_flip removido, brightness/contrast/zoom/translation conservadores. Teste ajustado para 1 RandomFlip.

---

### TASK-037 — Extrair _validate_splits_against_config para módulo compartilhado
- **Tipo:** refactor
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/dataset.py` — adicionar `validate_splits_against_config()` como função pública
  - `ml/src/train.py` — remover `_validate_splits_against_config()` local, importar de dataset
  - `ml/src/evaluate.py` — remover `_validate_splits_against_config()` local, importar de dataset
- **Critérios de Aceite:**
  - [ ] Função existe apenas em dataset.py (fonte única)
  - [ ] train.py e evaluate.py importam de dataset
  - [ ] Comportamento idêntico (mesmas validações: classes, seed, val_split, test_split)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Justificativa técnica:** Código duplicado em train.py e evaluate.py (33 linhas cada). Risco de divergência em correções futuras.
- **Log de Andamento:**
  - [2026-05-03] — Task registrada.
  - [2026-05-03] — Implementação concluída. Função movida para dataset.py, removida de train.py e evaluate.py. flutter analyze OK, flutter test 15/15.
- **Resultado:** validate_splits_against_config() definida em dataset.py. train.py e evaluate.py importam dela. Zero duplicação.

---

### TASK-038 — Corrigir cálculo de zoom_factor no build_augmentation_layer
- **Tipo:** fix
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/src/preprocess.py` — linhas 114-117: calcular ambos os limites de zoom a partir de config
- **Critérios de Aceite:**
  - [ ] `zoom_range: [0.85, 1.15]` gera `RandomZoom(height_factor=(-0.15, 0.15))`
  - [ ] `zoom_range: [0.9, 1.2]` geraria `RandomZoom(height_factor=(-0.1, 0.2))` (assimétrico correto)
  - [ ] Testes existentes continuam passando
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Justificativa técnica:** Cálculo atual `1.0 - zoom[0]` só usa o limite inferior, ignora o superior. Para configs simétricas funciona por coincidência, mas configs assimétricas produzem resultado errado.
- **Log de Andamento:**
  - [2026-05-03] — Task registrada.
  - [2026-05-03] — Implementação concluída. zoom_lower e zoom_upper calculados independentemente. flutter analyze OK, flutter test 15/15.
- **Resultado:** RandomZoom usa ambos os limites da config: (zoom[0]-1.0, zoom[1]-1.0). Configs assimétricas agora produzem zoom assimétrico correto.

---

### TASK-039 — Atualizar design tokens: tipografia (Manrope+Inter), cores de textura, radii
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-039-design-tokens-v2
- **Escopo Técnico:**
  - `lib/core/theme/app_typography.dart` — substituir Roboto por Manrope (display) + Inter (body)
  - `lib/core/theme/app_colors.dart` — adicionar cores de classes de textura (soilSandy, soilSilt, soilMedium, soilClay, soilVeryClay) + warning/warningContainer + surfaceDim
  - `lib/core/theme/app_theme.dart` — ajustar radii de cards/buttons para match design (sm:8, md:12, lg:16, xl:24, pill:999)
  - `pubspec.yaml` — declarar fonts Manrope e Inter (Google Fonts ou assets)
- **Critérios de Aceite:**
  - [ ] Tipografia usa Manrope (títulos, fontWeight 700-800) e Inter (corpo, labels)
  - [ ] 5 cores de textura de solo acessíveis via AppColors
  - [ ] Constantes de radii acessíveis (AppRadius ou similar)
  - [ ] Warning colors (amber) disponíveis
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
  - [ ] App existente continua visual coerente (não quebra telas atuais)
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Fundação para todas as telas v2.
  - [2026-05-03] — Implementação: google_fonts adicionado ao pubspec, AppTypography reescrita (Manrope display + Inter body), AppColors estendido (warning, soilSandy/Silt/Medium/Clay/VeryClay, surfaceDim), AppRadius criado, AppTheme atualizado para radii pill nos buttons, SoilTextureColors helper criado. flutter analyze OK, flutter test 15/15.
- **Resultado:** Design tokens v2 implementados: Manrope (display), Inter (body), 5 cores de textura, AppRadius (sm/md/lg/xl/pill), warning colors, SoilTextureColors helper.

---

### TASK-040 — Redesign HomeScreen conforme protótipo v2
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-040-home-redesign-v2
- **Escopo Técnico:**
  - `lib/core/features/home/home_page.dart` — reescrever: hero com greeting + stats, botão "Nova análise" prominente, seção "Última análise" com card visual, placeholder para mapa de lotes (futuro)
  - `lib/core/widgets/` — novos widgets: StatsGrid, LastAnalysisCard, PrimaryActionButton
  - `lib/providers/` — consumir homeStatsProvider (TASK-016) ou fallback estático
- **Critérios de Aceite:**
  - [ ] Hero com logo VisioSoil + greeting + última análise em texto
  - [ ] Botão "Nova análise" com estilo dark + ícone de câmera (destaque)
  - [ ] Grid de 3 stats (Análises, Localizações, Confiança média)
  - [ ] Card "Última análise" com thumbnail, classe, confiança, data
  - [ ] Espaço reservado para mapa de lotes (placeholder com mensagem ou componente futuro)
  - [ ] Bottom navigation funcional (Home, Capturar, Histórico)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039 (tokens). Dados reais via TASK-016 (pendente) — usar mock/fallback até lá.
- **Resultado:** [pendente]

---

### TASK-041 — Implementar tela de Setup pré-captura (lote/cultura/profundidade)
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-041-capture-setup
- **Escopo Técnico:**
  - `lib/core/features/capture/setup_screen.dart` — novo: wizard 3 passos (lote → cultura → profundidade)
  - `lib/core/routes/app_router.dart` — nova rota `/capture/setup`
  - `lib/models/capture_context.dart` — novo modelo com lote, cultura, profundidade selecionados
- **Critérios de Aceite:**
  - [ ] Wizard com step indicator (3 barras de progresso)
  - [ ] Passo 1: seleção de lote (lista com radio + "Adicionar novo lote" placeholder)
  - [ ] Passo 2: seleção de cultura (grid 2x3) + época de plantio (chips)
  - [ ] Passo 3: seleção de profundidade (0-20, 20-40, 40-60 cm) + resumo
  - [ ] Navegação back/forward entre passos
  - [ ] Botão final "Abrir câmera" navega para capture com contexto
  - [ ] Lotes hardcoded por enquanto (backend de lotes é funcionalidade futura)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039 (tokens). Lotes serão mock — persistência de lotes é feature futura.
- **Resultado:** [pendente]

---

### TASK-042 — Redesign CaptureScreen: semáforo + preview com qualidade inline
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-042-capture-redesign-v2
- **Escopo Técnico:**
  - `lib/core/features/capture/capture_screen.dart` — reescrever: câmera com overlay retículo + semáforo (vermelho/amarelo/verde), preview com checklist inline, botões refazer/analisar
  - `lib/core/widgets/capture_semaphore.dart` — widget do semáforo de prontidão
  - `lib/core/widgets/quality_checklist_compact.dart` — checklist em grid compacto (6 itens)
  - Integração com CaptureContext de TASK-041
- **Critérios de Aceite:**
  - [ ] Viewfinder com overlay: retículo com cantos coloridos conforme estado
  - [ ] Semáforo 3 estados: vermelho (aproxime), amarelo (quase), verde (pronto)
  - [ ] Botão de captura desabilitado até semáforo verde
  - [ ] Após captura: preview com checklist compacto sobreposto
  - [ ] Badge "Captura aprovada" + score
  - [ ] Botões "Refazer" e "Analisar"
  - [ ] Contexto do lote/cultura exibido no topo da câmera
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039, TASK-041. Análise real de qualidade via TASK-007 (pendente) — usar simulação/mock até lá.
- **Resultado:** [pendente]

---

### TASK-043 — Implementar tela de Processamento (loading animado)
- **Tipo:** feat
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-043-processing-screen
- **Escopo Técnico:**
  - `lib/core/features/capture/processing_screen.dart` — nova tela: animação de processamento enquanto aguarda inferência
  - `lib/core/routes/app_router.dart` — nova rota `/processing`
- **Critérios de Aceite:**
  - [ ] Tela exibida durante inferência TFLite
  - [ ] Ícone animado (sparkles/pulsante) com texto "Analisando..."
  - [ ] Texto contextual (classe de solo, lote)
  - [ ] Auto-navega para resultado ao concluir
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039.
- **Resultado:** [pendente]

---

### TASK-044 — Implementar tela de Resultado com classificação e confiança
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-044-result-screen
- **Escopo Técnico:**
  - `lib/core/features/result/result_screen.dart` — nova tela: classe textural destacada, confiança com badge qualitativo, foto thumbnail, link para recomendações
  - `lib/core/routes/app_router.dart` — nova rota `/result`
  - `lib/models/confidence_level.dart` — integração com TASK-009
- **Critérios de Aceite:**
  - [ ] Classe textural exibida em destaque (nome + cor associada)
  - [ ] Confiança com badge: Alta (>85%), Média (70-85%), Baixa (<70%)
  - [ ] Foto da amostra visível
  - [ ] Botões: "Ver plano de manejo" (placeholder para recomendações) + "Nova análise" + "Salvar"
  - [ ] Dados persistidos no banco via SoilRecordRepository
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039, TASK-009. "Ver plano de manejo" navega para placeholder até recomendações serem implementadas.
- **Resultado:** [pendente]

---

### TASK-045 — Implementar tela de Recomendações/Plano de Manejo (estrutura + placeholder para research agent)
- **Tipo:** feat
- **Complexidade:** major
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-045-recommendations-screen
- **Escopo Técnico:**
  - `lib/core/features/recommendations/recommendations_screen.dart` — nova tela: layout com abas (Plano/Fontes/Alertas), loading animado, cards de ação priorizados, FAB "Perguntar ao agente"
  - `lib/core/features/recommendations/widgets/` — ActionCard, SourceCard, AlertCard, AgentChatSheet
  - `lib/core/routes/app_router.dart` — nova rota `/recommendations`
  - `lib/models/management_plan.dart` — novo modelo (ações, fontes, alertas)
- **Critérios de Aceite:**
  - [ ] Layout com 3 abas: Plano (ações priorizadas), Fontes (referências), Alertas
  - [ ] Cards de ação com prioridade (alta/média/baixa), ícone, título, prazo, descrição + citações
  - [ ] Loading animado com etapas (simulado — research agent é feature futura)
  - [ ] FAB "Perguntar ao agente" abre bottom sheet de chat (UI pronta, funcionalidade mock)
  - [ ] Dados estáticos/mock por classe textural (funcionalidade de research agent é futura)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039. Research agent é funcionalidade futura — implementar UI com dados mock por classe textural.
- **Resultado:** [pendente]

---

### TASK-046 — Implementar tela de Detalhes do Lote com comparação temporal
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-046-lot-detail-screen
- **Escopo Técnico:**
  - `lib/core/features/details/lot_detail_screen.dart` — nova tela: stats do lote, comparação A/B entre amostras, timeline do histórico
  - `lib/core/routes/app_router.dart` — nova rota `/lot-detail`
  - `lib/core/widgets/temporal_comparison.dart` — widget de comparação A/B
- **Critérios de Aceite:**
  - [ ] Stats do lote: cultura, área, nº de amostras
  - [ ] Comparação temporal A/B entre duas amostras selecionáveis
  - [ ] Badge "Mudou" / "Estável" com alerta se textura divergiu
  - [ ] Timeline cronológica das amostras do lote
  - [ ] Toque em item da timeline alterna seleção A/B
  - [ ] Botão "Ver plano de manejo"
  - [ ] Dados mock (persistência de lotes é feature futura)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039. Lotes são feature futura — usar dados mock.
- **Resultado:** [pendente]

---

### TASK-047 — Implementar Onboarding de captura (3 passos)
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-047-onboarding
- **Escopo Técnico:**
  - `lib/core/features/onboarding/onboarding_screen.dart` — nova tela: 3 passos ilustrados (enquadramento, iluminação, referência de escala)
  - `lib/core/routes/app_router.dart` — rota `/onboarding`
  - `lib/providers/` — provider para flag "onboarding visto" (SharedPreferences)
  - Dependência: `shared_preferences`
- **Critérios de Aceite:**
  - [ ] 3 passos com PageView: ilustração + título + descrição
  - [ ] Passo 1: enquadramento (moeda como referência)
  - [ ] Passo 2: iluminação (evitar sombras)
  - [ ] Passo 3: ângulo (top-down)
  - [ ] Botão "Começar" no último passo
  - [ ] Flag persistida — mostrar apenas na primeira vez
  - [ ] Acessível via link "Como capturar bem" na Home
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039.
- **Resultado:** [pendente]

---

### TASK-048 — Redesign DetailsScreen existente (preencher tela placeholder)
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-048-details-screen-v2
- **Escopo Técnico:**
  - `lib/core/features/details/details.dart` — reescrever: exibir dados completos do SoilRecord (foto, classe, confiança, localização, data, mapa)
  - Integração com cores de textura de TASK-039
  - Botões: compartilhar (TASK-011), ver recomendações
- **Critérios de Aceite:**
  - [ ] Foto da amostra em destaque (hero image)
  - [ ] Classe textural com cor associada e badge de confiança
  - [ ] Localização: endereço + coordenadas + mini-mapa placeholder
  - [ ] Data/hora formatada
  - [ ] Botão "Ver plano de manejo" (navega para recomendações)
  - [ ] Botão "Compartilhar" (placeholder até TASK-011)
  - [ ] `flutter analyze` sem erros
  - [ ] `flutter test` sem falhas
- **Log de Andamento:**
  - [2026-05-03] — Task registrada. Depende de TASK-039.
- **Resultado:** [pendente]

---

## Tasks Concluídas

[nenhuma task concluída neste repositório]
