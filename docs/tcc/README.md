# Relatório de TCC — VisioSoil

Este diretório guarda o relatório de Trabalho de Conclusão de Curso sobre o
VisioSoil e o material de apoio usado para escrevê-lo.

**Idioma.** Tudo aqui é escrito em português (pt-BR). É a única exceção à regra
do repositório de que a documentação é em inglês, registrada na
[SPEC 0100](../specs/0100-keep-the-thesis-report-in-pt-br-under-docs-tcc.md) e em
`docs/agents/project.md`. A exceção vale só para este diretório: specs, ADRs,
commits, pull requests e issues sobre o relatório continuam em inglês.

## Conteúdo

| Arquivo | O que é |
| --- | --- |
| [`revisao-do-projeto.md`](revisao-do-projeto.md) | Levantamento do que foi construído até o commit `64a3333` (2026-10-01), organizado pelas seções de um relatório — problema, contexto, solução, métodos, resultados e limitações — com a fonte de cada afirmação. É a base factual do relatório, não o relatório. |

## Template da instituição

O relatório segue o template fornecido pela instituição. Quando ele for
adicionado, entra neste diretório (por exemplo, `docs/tcc/template/`) junto com
os capítulos, e esta tabela passa a listá-los.

O levantamento não fixa a estrutura de capítulos: cada seção dele indica para
qual parte de um relatório típico serve, e o mapeamento final segue o que o
template exigir.

## Como usar o levantamento

- Cada parágrafo cita a spec, o ADR, o veredito ou o arquivo de onde vem. Uma
  frase do relatório que resuma um trecho deve ser conferida contra essa fonte,
  não contra o levantamento.
- Lacunas aparecem como **[LACUNA: …]**. São dados que o repositório não tem —
  instituição, orientação, referências bibliográficas externas — e não devem
  ser preenchidas com valores plausíveis.
- O que está planejado ou em pull request aberto aparece como tal e não como
  feito.
