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
- **Status:** backlog
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
- **Log de Andamento:**
  - [2026-04-28] — Validação realizada. Revertida junto com TASK-003.
- **Resultado:** Revertida — dependência (TASK-003) removida.

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

## Tasks Concluídas

[nenhuma task concluída neste repositório]
