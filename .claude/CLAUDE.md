# VisioSoil — Diretrizes para Agentes de IA

> **Este projeto opera sob um fluxo mandatório.** Nenhum agente de IA pode modificar a codebase sem task registrada em `.claude/tasks.md`. Consulte `.claude/rules/` para as regras completas.

## Projeto

- **Nome:** VisioSoil
- **Stack:** Flutter 3.x / Dart 3.10.4+ (Riverpod, GoRouter, Drift+SQLite, TFLite)
- **Repositório:** LukeSantossz/visiosoil-app
- **Estrutura:** Mobile app — lib/core/ (theme, routes, widgets, utils, services, database, data, features), lib/models/, lib/providers/

## Comandos

```bash
# Instalar dependências
flutter pub get

# Gerar adapters Drift (obrigatório após alterações em tabelas/schema)
dart run build_runner build --delete-conflicting-outputs

# Análise estática (lint)
flutter analyze

# Testes
flutter test

# Build APK release
flutter build apk --release

# Rodar no emulador/dispositivo
flutter run
```

## Estrutura do Sistema de Regras

```
projeto/
├── CLAUDE.md                          ← arquivo raiz (guia técnico para Claude Code)
├── .claude/
│   ├── CLAUDE.md                      ← este arquivo (regras de governança para agentes)
│   ├── rules/
│   │   ├── 00-trava-seguranca.md      ← condições obrigatórias de operação
│   │   ├── 01-principios.md           ← pense antes de codar, simplicidade, cirúrgico
│   │   ├── 02-reconhecimento.md       ← inventário técnico pré-implementação
│   │   ├── 03-modos-operacao.md       ← desenvolvimento, review, tutor
│   │   ├── 04-avaliacao-pos.md        ← protocolo pós-implementação
│   │   ├── 05-convencoes.md           ← VAR Method, Conventional Commits, branches
│   │   ├── 06-crura.md               ← fluxo CRURA + checklist + reversão + templates
│   │   ├── 07-integridade.md          ← 12 regras invioláveis
│   │   ├── 08-registro-projeto.md     ← regras de atualização do registry
│   │   └── 09-enforcement.md          ← hooks git automatizados
│   ├── registry.md                    ← estado do projeto + histórico (mutável)
│   ├── registry-archive.md            ← criado automaticamente quando histórico > 30 entradas
│   ├── tasks.md                       ← registro de tasks (obrigatório)
│   ├── pr-template.md                 ← template de Pull Request
│   ├── issue-template.md              ← template de Issue
│   ├── hooks/                         ← scripts de enforcement git
│   └── enforcement.conf               ← padrões de debug log por linguagem
```

## Fluxo Resumido

1. **Task registrada** em `tasks.md` → obrigatório antes de qualquer código
2. **Modo declarado** (Desenvolvimento / Review / Tutor)
3. **Reconhecimento** da codebase
4. **Implementação** seguindo princípios e convenções
5. **Avaliação pós-implementação** (automática pelo agente)
6. **Atualização** do `registry.md`
7. **CRURA** — Change → Review → Upload → Review Again → Auto-Revisão

## Convenções Rápidas

- **Commits:** `type(scope): subject` — sem body, sem co-authored-by
- **Branches:** `type/TASK-NNN-descricao-curta`
- **Tasks:** uma por implementação, complexidade obrigatória (patch/minor/major)
- **Nomenclatura:** VAR Method (Data, Info, Manager, Handler, Service, Repository...)
