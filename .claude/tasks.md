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

### TASK-001 — Integrar modelo SqueezeNet+LR para classificação de solo
- **Tipo:** feat
- **Complexidade:** minor
- **Modo:** Desenvolvimento
- **Status:** pendente
- **Branch:** feat/TASK-001-squeezenet-lr-integration
- **Escopo Técnico:**
  - `lib/core/services/inference_service.dart` — atualizar labels, preprocessing (ImageNet normalization), output shape
  - `scripts/convert_model.py` — script de conversão SqueezeNet+LR → TFLite (novo, ferramenta auxiliar)
  - `assets/models/soil_classifier.tflite` — substituído pelo modelo combinado
- **Critérios de Aceite:**
  - [ ] Labels atualizadas para 5 classes (3 ativas + 2 futuras)
  - [ ] Preprocessing com normalização ImageNet (mean/std por canal)
  - [ ] Output shape dinâmico (lê do modelo, suporta 3 ou 5 classes)
  - [ ] Script Python de conversão funcional
  - [ ] `flutter analyze` sem erros
  - [ ] Contrato `InferenceResult` inalterado
- **Log de Andamento:**
  - [2026-04-27] — Task registrada. Reconhecimento concluído. Implementação parcial iniciada e revertida — prioridade alterada pelo usuário.
- **Resultado:** [backlog — aguardando dataset e definição de classes pelo usuário]

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
- **Status:** pendente
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `ml/` — novo diretório com pipeline completa (preprocess, train, evaluate, export). Stack: TensorFlow/Keras com conversão nativa para TFLite
  - `ml/src/` — `preprocess.py`, `dataset.py`, `model.py`, `train.py`, `evaluate.py`, `export.py`, `config.py`
  - `ml/data/` — estrutura para dataset (raw, processed, splits)
  - `ml/models/vN/` — artefatos versionados (`.tflite`, `metrics.json`, `config.json`, `spec.json`)
  - `ml/notebooks/` — EDA, treino interativo, avaliação
  - `ml/scripts/` — `train_and_export.sh`, `deploy_to_app.sh`
  - `ml/tests/` — `test_preprocess.py`, `test_model_output.py`, `test_tflite_inference.py`
  - Reestruturação do repositório: mover código Flutter de `/` para `/app/` — impacta CI (GitHub Actions paths), imports e referências absolutas
- **Critérios de Aceite:**
  - [ ] Diretório `ml/` criado com estrutura de pipeline reproduzível
  - [ ] `make train` executa pré-processamento, treino, avaliação e exportação em sequência
  - [ ] Spec de input/output em `ml/models/vN/spec.json` (shape, dtype, normalization, classes)
  - [ ] Exportação para `.tflite` com quantização pós-treino e teste de inferência no artefato
  - [ ] Versionamento em `models/vN/` com métricas, config e changelog
  - [ ] Script `deploy_to_app.sh` copia `.tflite` para `app/assets/models/`
  - [ ] `ml/README.md` documenta ambiente, treino, exportação e métricas
  - [ ] `.gitignore` configurado para `data/raw/`, `data/processed/` e `.h5`
  - [ ] Testes da pipeline passam (shape, dtype, range, inferência)
  - [ ] `flutter analyze` sem erros após reestruturação
- **Log de Andamento:**
  - [2026-04-29] — Task registrada. Depende de TASK-001 (contrato de input/output do InferenceService). Stack definido: TensorFlow/Keras. Decisões em aberto: experiment tracking (MLflow vs W&B vs JSON local), dataset storage (Git LFS vs download externo), augmentation strategy, arquitetura do modelo (transfer learning vs CNN do zero).
- **Resultado:** [pendente]

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

### TASK-018 — Adicionar arquivos de instrução .md ao repositório
- **Tipo:** docs
- **Complexidade:** patch
- **Modo:** Desenvolvimento
- **Status:** concluída
- **Branch:** feat/TASK-006-ml-platform
- **Escopo Técnico:**
  - `.claude/rules/10-engenharia-agentica.md` — já existente, não rastreado
  - `.claude/rules/11-integracao-codex.md` — já existente, não rastreado
  - `.claude/guia-configuracao-codex.md` — já existente, não rastreado
- **Critérios de Aceite:**
  - [ ] 3 arquivos adicionados ao git tracking
  - [ ] Commit segue Conventional Commits
- **Log de Andamento:**
  - [2026-05-02] — Task registrada. 3 arquivos .md de governança não rastreados pelo git.
  - [2026-05-02] — Concluída. 3 arquivos staged e commitados.
- **Resultado:** 3 arquivos de governança adicionados ao repositório: regras 10 (engenharia agêntica), 11 (integração Codex) e guia de configuração Codex.

---

## Tasks Concluídas

[nenhuma task concluída neste repositório]
