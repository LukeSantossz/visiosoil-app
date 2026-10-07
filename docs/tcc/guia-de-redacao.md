# Construção e redação do TCC

Este guia é o procedimento para escrever, revisar ou responder qualquer pergunta
sobre o artigo de TCC que tem o VisioSoil como tema. O artigo é dos autores.
Este repositório fornece os fatos sobre o aplicativo e guarda o material de
trabalho. A regra que torna o guia obrigatório está em `docs/agents/project.md`,
seção "Writing the thesis article (TCC)", e a decisão está na
[SPEC 0145](../specs/0145-write-the-thesis-article-from-checked-sources.md).

## 1. Fontes no Drive

Inventário feito em 2026-10-07. Quando a pasta mudar, a conferência registra a
mudança em [`conferencias.md`](conferencias.md) e este inventário é atualizado.

**Pasta do TCC**, ID `197jCAHu2wdrc2nd8VUkJ7ijSmFe55Fl_`, compartilhada só entre
os dois autores.

| Arquivo | Papel |
| --- | --- |
| `Aplicativo móvel para identificação da textura do solo como ferramenta de apoio na tomada de decisão agrícola.docx` (raiz) | Exportação do artigo enviada em 2026-10-07. Não é a cópia de trabalho. |
| `modelo original Fatec/modelo_artigo_original.docx` | Modelo de artigo original da instituição, que o TCC segue. Em dúvida de formatação, vale o modelo. |
| `modelo original Fatec/modelo_artigo_de_revisao.docx` | Modelo de artigo de revisão. Não se aplica a este TCC. |
| `Versões anteriores/` | O `.docx` de 2026-10-01 e os PDFs (2), (3) e (4) de 11 e 14 de setembro de 2026. Servem para saber o que mudou, não como fonte de texto atual. |

**Cópia de trabalho**: o Google Doc "Aplicativo móvel para identificação da
textura do solo como ferramenta de apoio na tomada de decisão agrícola", no
Drive da coautora e compartilhado com o Developer. Ele fica fora da pasta e é
encontrado pela busca do Drive, pelo título e pelo tipo Google Docs. O
identificador e o link dele não entram neste repositório, que é público: o
compartilhamento do documento é decisão dos autores.

| Aba | Conteúdo |
| --- | --- |
| TCC | O artigo inteiro, do Resumo às Referências. É o texto que vale. |
| Introdução | Versões antigas da Introdução, onde estão os comentários dos orientadores. |
| INTRODUÇÃO, Material e Métodos, Referências | Rascunhos anteriores à aba TCC. |
| Dicas - Eloiza | Regras de redação passadas pela orientação (seção 3.2 deste guia). |

## 2. Conferência obrigatória

Antes de qualquer trabalho no artigo, em toda sessão, sem exceção:

1. **Listar a pasta** e comparar a data de modificação de cada arquivo com a
   última entrada de [`conferencias.md`](conferencias.md). Arquivo novo ou
   modificado é lido inteiro.
2. **Ler a aba TCC**, as demais abas e os comentários abertos do documento.
   Quando a exportação `.docx` da pasta e a aba divergirem, dizer qual é a mais
   recente e perguntar aos autores antes de editar qualquer uma.
3. **Conferir no `main` do dia** cada afirmação do artigo sobre o aplicativo,
   pela tabela da seção 4. O levantamento
   [`revisao-do-projeto.md`](revisao-do-projeto.md) descreve o commit `64a3333`
   e não é atualizado.
4. **Conferir as referências**: toda citação no texto tem sua referência, toda
   referência é citada, e uma afirmação atribuída a uma fonte está na fonte.
5. **Registrar** em [`conferencias.md`](conferencias.md) a data, os arquivos, a
   revisão do documento e o commit lidos, e cada divergência com a fonte que a
   mostra.

Uma divergência é relatada aos autores com a fonte e fica com eles. O guia não
autoriza corrigir o texto deles por conta própria.

## 3. Regras de redação

### 3.1 Decisões dos autores

- O foco é o que os autores escreveram; o código serve para conferir o que o
  texto afirma sobre o aplicativo, e não muda a direção do texto.
- O artigo é uma visão geral da construção do aplicativo. O modelo de
  classificação aparece de forma breve, sem o detalhe das técnicas.
- A funcionalidade de recomendações de manejo fica como os autores a
  escreveram.
- Só o modelo atual é apresentado (o de medidas de textura com regressão
  logística).
- Na Introdução, a granulometria vem antes da textura, como pediu o orientador.

### 3.2 Dicas - Eloiza (resumo da aba)

- **Resumo**: de 230 a 250 palavras, em um bloco só, com as frases em
  sequência. A ordem é contexto (1 a 3 frases), objetivo, metodologia (1 a 2
  frases), o que foi feito e os resultados, conclusão e próximos passos. Não
  copia frases do texto. Conferir o sentido por tradução reversa.
- **Palavras-chave**: de 3 a 5, diferentes das palavras do título, em ordem de
  importância.
- **Resultados e Discussão** é o capítulo mais importante: relata o passo a
  passo do desenvolvimento, com prints. Toda figura tem título e é explicada no
  texto, e print de código tem fundo branco.
- **Referências**: alinhadas à esquerda, sem justificar, com uma linha entre
  elas.

### 3.3 Comentários dos orientadores

Em 2026-10-07 havia cinco comentários abertos, todos ancorados em versões antigas
da aba Introdução, e dois resolvidos. A conferência verifica se cada comentário
aberto ainda se aplica ao texto da aba TCC e registra a resposta.

### 3.4 Estilo

- Português do Brasil, números no padrão brasileiro (vírgula decimal, ponto de
  milhar).
- Formatação do modelo: legenda acima da figura ou tabela no formato
  "Figura N – título", linha "Fonte:" abaixo, citações autor-data (ABNT NBR
  10520) e referências pela ABNT NBR 6023.
- Sem travessão nem meia-risca no texto corrido; o "–" das legendas é do modelo
  e fica.
- Sem vocabulário inflado ("crucial", "robusto", "inovador", "notável", "vale
  ressaltar", "destaca-se"), sem contraste encenado ("não é X, é Y") e sem frase
  que só anuncia o que vem a seguir. Figura e tabela são citadas no próprio
  período, como "(Tabela 1)".
- Nada que a fonte não diga. O que não se confirma fica marcado como tal, e
  nunca é preenchido com um valor plausível.

## 4. Onde conferir cada afirmação sobre o aplicativo

| No artigo | Onde conferir no `main` |
| --- | --- |
| Quadro 1 (tecnologias) | `pubspec.yaml`, `ml/requirements.txt`, `.github/workflows/ci.yml` |
| Rotas e telas | `lib/core/routes/app_router.dart`, `lib/core/features/` |
| Primeira abertura e permissões | `lib/core/features/onboarding/onboarding_screen.dart`; SPEC 0099 e SPEC 0115 |
| Captura e salvamento | `lib/core/features/capture/`; SPEC 0116, SPEC 0117 e SPEC 0132 |
| Histórico e detalhes | `lib/core/features/history/`, `lib/core/features/details/`; SPEC 0125 |
| Configurações | `lib/core/features/settings/settings_screen.dart` |
| Campos do registro e versão do banco | `lib/core/database/tables/`, `schemaVersion` em `lib/core/database/app_database.dart` |
| Privacidade | `lib/core/services/image_storage_service.dart` (EXIF), `android:allowBackup` em `android/app/src/main/AndroidManifest.xml`, `lib/core/services/share_content_builder.dart`; SPEC 0093 |
| Acervo, classes e Siltosa | ADR 0016, `ml/config.yaml` |
| Modelo (medidas, regressão logística, arquivo de números) | ADR 0024, `assets/models/spec.json` |
| Acurácia e controle | `docs/ml/e0-verdict.md` |
| Tempo de classificação | `docs/ml/descriptor-path-cost.md` |
| Protocolo da folha A4 | ADR 0017 |
| Leitor da folha | SPEC 0091, SPEC 0092, SPEC 0140; `docs/ml/sheet-reader-real-photographs.md` para fotografias reais |
| Commits e pull requests | `git rev-list --count origin/main`; `git log --oneline origin/main \| grep -c 'Merge pull request #'` |
| Testes em Dart | `git ls-tree -r --name-only origin/main test integration_test \| grep -c '_test.dart$'` (arquivos) e `git grep -hE "^\s*(test\|testWidgets)\(" origin/main -- test/ integration_test/ \| wc -l` (casos) |
| Testes em Python | `git grep -hE "^\s*def test_" origin/main -- 'ml/tests/*.py' \| wc -l` e o mesmo em `corpus/tests/` |
| Etapas do desenvolvimento | `git log --merges --format='%ad %s' --date=short origin/main` |

Trabalho em pull request aberto não é descrito como feito.

## 5. Onde registrar

- [`conferencias.md`](conferencias.md): uma entrada por conferência, a mais
  recente no topo.
- [`revisao-do-rascunho.md`](revisao-do-rascunho.md) e
  [`revisao-do-projeto.md`](revisao-do-projeto.md) são retratos datados (o
  rascunho de 2026-10-01 e o commit `64a3333`) e não são reescritos. O que mudou
  depois deles fica nas conferências.
