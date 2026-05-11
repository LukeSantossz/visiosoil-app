# CLAUDE.md — Ponto de Entrada do Framework de Desenvolvimento

> **Versao:** 1.1.0 | **Localizacao das regras:** `.claude/rules/` | **Estado:** `.claude/tasks.md` + `.claude/registry.md`

---

## Trava de Seguranca (Regra 00 — Incondicional)

Nenhuma implementacao, modificacao, criacao ou exclusao de codigo e permitida sem:

1. **Task registrada** em `.claude/tasks.md`
2. **Modo declarado** pelo usuario (Desenvolvimento, Review ou Tutor)
3. **Codebase reconhecida** (regra 02 executada)
4. **Registry verificado** (`.claude/registry.md` lido)

Excecoes: Modo Tutor e Review podem iniciar sem task, mas qualquer modificacao de codigo exige registro previo. Detalhes completos: `.claude/rules/00-trava-seguranca.md`.

## Principios Core (Regra 01)

- Pense antes de codar. Declare premissas, exponha trade-offs, pergunte se ambiguo.
- Simplicidade primeiro. Codigo minimo, sem features especulativas, sem abstracao prematura.
- Mudancas cirurgicas. Toque apenas o necessario. Limpe apenas a propria sujeira.
- Todo codigo gerado por agente e rascunho ate ser revisado e compreendido pelo desenvolvedor.

## Inicio de Sessao — O Que Ler

### Sempre (toda sessao):

1. Este arquivo (`CLAUDE.md`)
2. `.claude/registry.md` → estado atual, ultima implementacao, pendencias
3. `.claude/tasks.md` → **apenas a secao "Tasks Ativas"**, nao carregar Tasks Concluidas

### Sob demanda (quando a condicao ativar):

| Condicao | Ler |
|----------|-----|
| Projeto novo ou primeira sessao | `.claude/prd.md` (se existir) |
| Task `minor` ou `major` | Regras 04 (avaliacao) + 06 (CRURA) + 08 (registro) |
| Task `patch` | Apenas regra 05 (convencoes) para commit |
| Modo Review ativado | Regra 03 completa (protocolo de review) |
| Modo Tutor ativado | Regra 03 completa (metodo de dicas progressivas) |
| Publicar no GitHub / curar portfolio | `.claude/guides/guia-portfolio.md` |
| Usar integracao Codex | `.claude/guides/guia-codex.md` |
| Setup de hooks ou enforcement | Regra 09 |
| Duvida sobre nomenclatura ou commits | Regra 05 |
| Task requer referencia a padroes anteriores | Consultar base de conhecimento externa (ver secao abaixo) |

### Regras detalhadas (referencia completa):

```
.claude/rules/
├── 00-trava-seguranca.md     ← condicoes obrigatorias
├── 01-principios.md          ← como pensar e codar
├── 02-reconhecimento.md      ← mapeamento pre-implementacao
├── 03-modos-operacao.md      ← desenvolvimento / review / tutor
├── 04-avaliacao-pos.md       ← verificacao pos-implementacao + testes
├── 05-convencoes.md          ← nomenclatura, commits, branches
├── 06-crura.md               ← fluxo CRURA + checklist unificado
├── 07-integridade.md         ← regras inviolaveis
├── 08-registro-projeto.md    ← registry + recuperacao de sessao
└── 09-enforcement.md         ← hooks git automatizados
```

## Recuperacao de Sessao

Se a sessao anterior foi interrompida (timeout, limite de contexto, crash):

1. Ler `registry.md` → ultima implementacao e estado registrado
2. Ler `tasks.md` → task ativa e ultimo Log de Andamento
3. Verificar branch atual (`git branch --show-current`) e ultimo commit (`git log -1 --oneline`)
4. Comparar estado real vs registrado. Reportar divergencias ao usuario.
5. Retomar do ponto documentado no Log de Andamento.

## Base de Conhecimento Externa

Caminho: C:\Users\lucas\OneDrive\Desktop\llm-wiki\wiki\
Indice: wiki/index.md

**Regras de uso:**
- APENAS CONSULTA — nao modificar, criar ou atualizar arquivos nesta pasta
- Consultar antes de: decidir stack, investigar bugs recorrentes, tomar decisoes arquiteturais
- O indice `index.md` e o ponto de entrada para navegacao

## Informacoes do Projeto

- **Nome:** VisioSoil
- **Stack:** Flutter 3.x / Dart 3.10.4+ (Riverpod, GoRouter, Drift+SQLite, TFLite)
- **Repositorio:** LukeSantossz/visiosoil-app
