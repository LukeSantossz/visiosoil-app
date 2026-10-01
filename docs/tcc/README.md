# Relatório de TCC — VisioSoil

Este diretório guarda o material de apoio ao artigo de Trabalho de Conclusão
de Curso sobre o VisioSoil.

**Idioma.** Tudo aqui é escrito em português (pt-BR). É a única exceção à regra
do repositório de que a documentação é em inglês, registrada na
[SPEC 0100](../specs/0100-keep-the-thesis-report-in-pt-br-under-docs-tcc.md) e em
`docs/agents/project.md`. A exceção vale só para este diretório: specs, ADRs,
commits, pull requests e issues sobre o relatório continuam em inglês.

## Onde está o artigo

O rascunho é um Google Doc com abas, no Drive dos autores, e segue o modelo da
instituição (`modelo_artigo_original.docx`, artigo original segundo a ABNT NBR
6023 e 10520). A aba "Revisão - Métodos e Resultados" reúne a Introdução
corrigida, Material e Métodos e Resultados e Discussão reconstruídos e a lista de
referências unificada. Este diretório não guarda cópia do artigo: o texto é dos
autores, e a direção dele é definida lá.

## Conteúdo

| Arquivo | O que é |
| --- | --- |
| [`revisao-do-rascunho.md`](revisao-do-rascunho.md) | Revisão do rascunho de 2026-10-01 contra o modelo e as anotações do orientador: estrutura, Introdução, Material e Métodos, citações e referências, o que falta em Resultados, Resumo e Considerações Finais, e as afirmações sobre o aplicativo que o código não confirma. |
| [`revisao-do-projeto.md`](revisao-do-projeto.md) | Levantamento do que foi construído até o commit `64a3333`, organizado pelas seções do modelo, com a fonte de cada afirmação. É material de consulta para o rascunho, não o define. |

## Como usar o levantamento

- Cada parágrafo cita a spec, o ADR, o veredito ou o arquivo de onde vem. Uma
  frase do artigo que resuma um trecho deve ser conferida contra essa fonte,
  não contra o levantamento.
- Lacunas aparecem como **[LACUNA: …]**. São dados que o repositório não tem e
  não devem ser preenchidas com valores plausíveis.
- O que está planejado ou em pull request aberto aparece como tal e não como
  feito.
