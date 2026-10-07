# Relatório de TCC do VisioSoil

Este diretório é a seção dedicada à construção e à redação do artigo de
Trabalho de Conclusão de Curso que tem o VisioSoil como tema.

**Idioma.** Tudo aqui é escrito em português (pt-BR). É a única exceção à regra
do repositório de que a documentação é em inglês, registrada na
[SPEC 0145](../specs/0145-write-the-thesis-article-from-checked-sources.md) e em
`docs/agents/project.md`. A exceção vale só para este diretório: specs, ADRs,
commits, pull requests e issues sobre o relatório continuam em inglês.

## Onde está o artigo

O artigo é um Google Doc com abas, no Drive dos autores, e segue o modelo da
instituição (`modelo_artigo_original.docx`, artigo original segundo a ABNT NBR
6023 e 10520). A aba TCC é a cópia de trabalho, do Resumo às Referências. O
documento e a pasta com o modelo e as versões anteriores estão no
[guia de redação](guia-de-redacao.md#1-fontes-no-drive). Este diretório não
guarda cópia do artigo: o texto é dos autores, e a direção dele é definida lá.

## Antes de qualquer trabalho no artigo

A conferência das fontes é obrigatória em toda sessão: a pasta do Drive, as abas
e os comentários do documento, e o aplicativo no `main` do dia. O procedimento
está no [guia de redação](guia-de-redacao.md#2-conferência-obrigatória), e cada
conferência fica registrada em [`conferencias.md`](conferencias.md).

## Conteúdo

| Arquivo | O que é |
| --- | --- |
| [`guia-de-redacao.md`](guia-de-redacao.md) | Procedimento: fontes no Drive, conferência obrigatória, regras de redação e onde conferir cada afirmação sobre o aplicativo. É mantido atual. |
| [`conferencias.md`](conferencias.md) | Registro das conferências, cada uma com o que foi lido e as divergências encontradas. |
| [`revisao-do-rascunho.md`](revisao-do-rascunho.md) | Revisão do rascunho de 2026-10-01 contra o modelo e as anotações do orientador. Retrato datado. |
| [`revisao-do-projeto.md`](revisao-do-projeto.md) | Levantamento do que foi construído até o commit `64a3333`, com a fonte de cada afirmação. Retrato datado; o que mudou depois está nas conferências. |

## Como usar o levantamento

- Cada parágrafo cita a spec, o ADR, o veredito ou o arquivo de onde vem. Uma
  frase do artigo que resuma um trecho deve ser conferida contra essa fonte no
  `main` do dia, não contra o levantamento.
- Lacunas aparecem como **[LACUNA: …]**. São dados que o repositório não tem e
  não devem ser preenchidas com valores plausíveis.
- O que está planejado ou em pull request aberto aparece como tal e não como
  feito.
