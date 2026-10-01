# Revisão do projeto VisioSoil — o que foi construído até aqui

Levantamento do estado do projeto em `main` no commit `64a3333` (2026-10-01),
organizado pelas seções do modelo de artigo original. É material de consulta
para o rascunho de vocês, que é quem define a direção do texto; a revisão do
rascunho está em [`revisao-do-rascunho.md`](revisao-do-rascunho.md).

**Convenções**

- **Fonte:** ao fim de cada bloco indica a spec, o ADR, o veredito ou o arquivo
  de onde a informação vem. O relatório deve citar a fonte, não este
  levantamento.
- **[LACUNA: …]** marca um dado que o repositório não tem e que o relatório
  precisa (instituição, referências externas, medições que não existem).
- Cada afirmação é de um de três tipos, e o texto diz qual: **medido** (há um
  número registrado e onde foi medido), **implementado** (existe em código e
  testes) ou **planejado / em andamento** (decidido ou em pull request aberto,
  mas não em `main`).

---

## 1. Visão geral

O VisioSoil é um aplicativo móvel multiplataforma (Android e iOS), escrito em
Flutter, que transforma a fotografia de uma amostra de solo em um registro
georreferenciado com a classe textural estimada. A classificação roda no
próprio aparelho, sem conexão, a partir de 26 descritores clássicos de textura
calculados em Dart e de um contrato de 160 números (`assets/models/spec.json`)
produzido por um pipeline de treinamento em Python. O modelo distingue quatro
grupos texturais (Arenosa, Média, Argilosa, Muito Argilosa); a Siltosa ficou
fora da primeira versão por ter só três amostras.

O resultado central do trabalho experimental é que **a classe textural é
recuperável de fotografias do acervo**: o caminho de descritores atingiu
acurácia por grupo de 0,6883 contra 0,2727 de um controle com rótulos
embaralhados, diferença significativa e acima do menor efeito que o experimento
conseguia detectar. Esse número foi medido em fotografias de placas de Petri
do acervo do laboratório, não em fotos feitas pelo aplicativo sobre folha A4;
**nenhuma acurácia foi medida ainda nas capturas do app**.

Fonte: [README.md](../../README.md),
[ADR 0024](../adr/0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md),
[docs/ml/e0-verdict.md](../ml/e0-verdict.md),
[ADR 0026](../adr/0026-the-first-play-release-waits-for-classification.md).

---

## 2. Problema e motivação → 1 Introdução

A textura do solo — a proporção de areia, silte e argila — orienta decisões de
manejo, e o produto parte da premissa de que um agrônomo em campo ganha com uma
estimativa imediata dela, registrada com localização, sem esperar um laudo de
laboratório. O repositório define o usuário como o agrônomo ou técnico de campo
e o cenário como trabalho em área com conectividade instável, por isso captura,
inferência e armazenamento acontecem no aparelho.

A dificuldade técnica central está registrada no
[ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md):
classe textural é uma afirmação sobre **tamanho de partícula**, e tamanho em
pixels não significa nada sem escala — grãos grossos fotografados de longe e
grãos finos fotografados de perto produzem os mesmos pixels. A escala é,
portanto, pré-condição para que exista sinal, e não um detalhe.

Uma segunda dificuldade é física. Na escala mediana do acervo (0,100 mm/px) o
limite de Nyquist é 0,20 mm; argila (< 0,002 mm) e silte (0,002–0,05 mm) são
muito menores que isso, e só areia média e grossa é resolvível grão a grão.
**O que separa as classes finas tem de vir da aparência agregada da superfície,
não de enxergar grãos** — e essa era uma ameaça real à premissa do produto, que
o experimento E0 foi construído para testar.

Fonte: [README.md](../../README.md) (*What It Does*, *What It Is*),
[CONTEXT.md](../../CONTEXT.md),
[ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md) (*Context*),
[ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md) (*Context*).

[LACUNA: referências externas sobre a importância agronômica da textura do solo
e sobre o custo e o prazo da análise granulométrica em laboratório; o
repositório afirma a motivação, mas não cita literatura para ela.]

---

## 3. Contexto e fundamentação → 1 Introdução

Os tópicos abaixo são os que o trabalho usa e que o relatório precisa
fundamentar. O repositório explica cada um no nível de engenharia; a
fundamentação bibliográfica é lacuna em todos.

| Tópico | Onde o projeto usa | Fonte no repositório |
| --- | --- | --- |
| Grupos texturais da Embrapa (Arenosa, Média, Siltosa, Argilosa, Muito Argilosa) | rótulos do acervo e classes do modelo | [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md) |
| Frações granulométricas e resolução de imagem (Nyquist) | por que a textura é lida pela superfície | [ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md) |
| Descritores clássicos de textura: momentos de primeira ordem, bandas espectrais, LBP, GLCM | o classificador adotado | [ADR 0024](../adr/0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md) |
| Regressão logística multinomial e padronização | o classificador adotado | ADR 0024 |
| Transferência de aprendizado (MobileNetV2) e codificador congelado | braços `cnn` e `encoder_probe` do E0 | [docs/ml/e0-verdict.md](../ml/e0-verdict.md) |
| Validação cruzada repetida, estratificada e agrupada; seleção aninhada | protocolo de avaliação | [ADR 0020](../adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md) |
| Teste exato de McNemar, correção de Holm, intervalo de Wilson, menor efeito detectável (MDE) | leitura dos contrastes | ADR 0020, e0-verdict |
| Homografia (DLT de 4 pontos), limiar de Otsu, componentes conexos, transformada de distância | leitor da folha A4 | [SPEC 0091](../specs/0091-find-the-a4-sheet-and-rectify-it-at-native-resolution.md), [SPEC 0092](../specs/0092-measure-the-soil-on-the-a4-sheet-and-classify-with-it.md) |
| Reamostragem bilinear (Pillow) e aliasing | paridade Python–Dart | [ADR 0025](../adr/0025-the-dart-resample-reproduces-pillows-bilinear-byte-for-byte.md) |
| Geração aumentada por recuperação (RAG) com revisão humana | dicas de manejo | [ADR 0022](../adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md), [ADR 0023](../adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md) |
| Trabalhos relacionados: classificação de textura do solo por imagem | posicionamento do trabalho | — |

[LACUNA: referências bibliográficas para todos os tópicos acima, em especial o
Sistema Brasileiro de Classificação de Solos (Embrapa) com as faixas de cada
grupo textural, os artigos originais de LBP, GLCM e McNemar, e trabalhos
relacionados de classificação de textura do solo por imagem. O repositório não
mantém bibliografia.]

---

## 4. Dados → 2 Material e Métodos

### 4.1 O acervo

O conjunto de dados é um acervo de amostras de solo do laboratório já
fotografadas em placas de Petri, de cima, sobre fundo claro. As imagens foram
entregues em 2026-08-25. O rótulo de cada amostra é a pasta em que está, isto
é, o grupo textural atribuído pelo laboratório; **não há granulometria** (as
porcentagens de areia, silte e argila) associada às fotos.

A contagem inicial do ADR 0016 (194 amostras) foi corrigida durante a ingestão:
129 fotos em HEIC têm nome de contador de câmera (`IMG_####`) e não número de
laboratório, e contá-las uma a uma separaria fotos da mesma placa em partições
diferentes. A identidade dessas amostras foi recuperada pelo relógio de
captura (fotos com até 60 s de diferença são uma amostra).

| Classe | Grupos de amostra (corrigido) |
| --- | ---: |
| Arenosa | 26 |
| Média | 22 |
| Siltosa | 3 |
| Argilosa | 33 |
| Muito Argilosa | 21 |
| **Total** | **105 grupos, 221 fotografias** |

O acervo é **fechado**: o responsável pelo projeto declarou em 2026-09-01 que
o laboratório não participa do projeto, então não há como fotografar de novo,
coletar mais amostras rotuladas nem verificar os rótulos.

Fonte: [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md)
(*Amended 2026-09-01*, duas emendas),
[SPEC 0040](../specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md).

[LACUNA: nome do laboratório, origem geográfica das amostras e método de
classificação usado pelo laboratório. O repositório não registra nenhum dos
três.]

### 4.2 Populações de captura

Há uma única câmera (iPhone 11), mas três caminhos de exportação, que o
manifesto registra como populações:

| População | Formato | Resolução aproximada | Observação |
| --- | --- | --- | --- |
| A | JPEG exportado, com EXIF | 1536 × 2048 | — |
| B | JPEG "transportado", sem EXIF | ~1600 × 900 | recomprimido com tabela de quantização 3 a 4× mais grossa nas altas frequências; 69 % Argilosa e 0 % Muito Argilosa |
| C | HEIC nativo | 3024 × 4032 | convertido antes da ingestão |

A regra D6 da SPEC 0040 mantém a população B **só no treino**, nunca em
validação ou teste, porque sua degradação não representa o uso real (o app
captura direto da câmera) e poderia inflar a nota. Excluir B por completo foi
rejeitado porque derrubaria Argilosa de 43 para 26 grupos.

Fonte: [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md),
[SPEC 0040](../specs/0040-ingest-the-delivered-archive-as-dataset-version-v1.md) (D6),
[docs/ml/capture-population-probe.md](../ml/capture-population-probe.md).

### 4.3 Decisões e limitações dos dados

- **Siltosa fica fora do primeiro modelo.** Três amostras são o mínimo
  aritmético para uma partição e não sustentam medição. O produto conhece cinco
  classes e o modelo emite quatro; o app declara isso.
- **Os rótulos não são verificáveis.** O responsável decidiu, em 2026-08-25,
  não obter a lista número-da-amostra → classe; nenhum artefato do projeto
  distingue foto mal arquivada de erro do modelo.
- **Material de bancada.** O solo fotografado é seco e peneirado; nenhuma
  acurácia deste acervo descreve solo fresco de campo.
- **Escala variável.** Medida pela borda da placa (90 mm), a escala vai de
  5,73 a 14,93 px/mm (fator 2,6), com mediana de 10,0 px/mm.
- **Matriz de custo das confusões**, aprovada em 2026-08-25: Arenosa ↔ Muito
  Argilosa é a confusão mais grave (extremos opostos); Argilosa ↔ Muito Argilosa
  é a mais branda (vizinhas). É simétrica.
- **A versão do conjunto (`v1`) é produto de build**, gerada de forma
  determinística a partir do acervo e do código; nada sob ela é versionado
  ([ADR 0019](../adr/0019-a-dataset-version-is-a-build-product-and-nothing-under-it-is-versioned.md)).

Fonte: [ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md).

---

## 5. A solução → 3 Resultados e Discussão

### 5.1 Fluxo do usuário (implementado)

1. **Splash** pede as permissões de execução.
2. **Onboarding** de três passos explica a captura, exibido só no primeiro
   acesso.
3. **Início** mostra estatísticas e registros recentes.
4. **Captura** usa somente a câmera (galeria foi removida por decisão de
   produto), registra GPS e endereço por geocodificação reversa e classifica.
5. **Detalhes** mostram foto, classe, confiança, localização e dicas de manejo.
6. **Histórico** em grade, com filtro por textura, busca por endereço, seleção
   múltipla e exclusão em lote.
7. **Visualizador** em tela cheia com zoom.
8. **Configurações**, com login Google opcional.
9. **Compartilhamento** de texto e foto, sem coordenadas a menos que o usuário
   as inclua naquele envio.

São sete rotas no GoRouter (`/splash`, `/`, `/capture`, `/details`, `/preview`,
`/onboarding`, `/settings`) e uma tela de erro de rota.

Fonte: [README.md](../../README.md), `lib/core/routes/app_router.dart`,
`lib/core/features/`.

[LACUNA: capturas de tela do app para as figuras do relatório. O repositório
não guarda screenshots; `docs/design/ux-2026/` descreve as telas em texto.]

### 5.2 Arquitetura do aplicativo (implementado)

```
Telas → providers Riverpod → repositório (interface) → Drift/SQLite | caminho de descritores
```

- **Estado:** Riverpod — 18 providers declarados em `lib/providers/` (14
  `Provider`, 3 `StreamProvider`, 1 `NotifierProvider`), além das famílias.
- **Navegação:** GoRouter.
- **Persistência:** Drift + SQLite, esquema v5, três tabelas: `soil_records`,
  `sync_queue` (fila de saída para sincronização) e `management_tips` (cache
  das dicas). Migrações cumulativas de v1 a v5.
- **Repositório:** a interface `SoilRecordRepository` isola o Drift das telas.
- **Exclusão lógica:** excluir grava uma marca (`deleted`) e enfileira uma
  operação de sincronização; toda leitura ignora registros marcados.
- **Inferência:** em um `Isolate` separado, para não travar a interface.

Fonte: [CLAUDE.md](../../CLAUDE.md) (*Architecture*), [README.md](../../README.md).

### 5.3 O caminho de classificação no aparelho (implementado)

Para cada fotografia, dentro do isolate:

1. **Decodifica** o JPEG e **aplica a orientação EXIF** à imagem.
2. **Mede** a fotografia com o leitor da folha A4 (5.4): obtém milímetros por
   pixel e a região circular do solo.
3. **Corta a grade de patches:** reamostra para a escala canônica de
   0,1292 mm/px com o bilinear do Pillow reproduzido byte a byte em Dart
   ([ADR 0025](../adr/0025-the-dart-resample-reproduces-pillows-bilinear-byte-for-byte.md)),
   em tons de cinza, e corta patches de 160 px (≈ 21 mm) com passo de meio
   patch. Um disco de 90 mm rende 25 patches; menos de 9 é recusado.
4. **Descreve** cada patch com 26 descritores em quatro grupos: 4 momentos de
   primeira ordem, 8 bandas espectrais em escala logarítmica, 10 classes de LBP
   uniforme invariante à rotação (8 vizinhos, raio 1) e 4 estatísticas de
   co-ocorrência (GLCM, 16 níveis, 4 deslocamentos).
5. **Pontua** com o contrato: padroniza os 26 valores (média e escala) e aplica
   uma regressão logística multinomial (4 × 26 coeficientes e 4 interceptos).
   São 160 números ao todo.
6. **Agrega** as distribuições dos patches pela média.

Não há runtime de aprendizado de máquina no app: o TFLite foi removido
([SPEC 0084](../specs/0084-remove-the-tflite-export-that-nothing-ships.md))
porque o modelo adotado é um produto de matrizes que não precisa de
interpretador. O contrato `spec.json` (versão `1.0.0`, conjunto `v1`) é
gerado por `ml/src/release.py` e copiado para o app por
`ml/scripts/deploy_to_app.sh`.

Fonte: [ADR 0024](../adr/0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md),
[ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md),
`assets/models/spec.json`,
[SPEC 0083](../specs/0083-wire-the-descriptor-path-into-the-inference-service.md).

### 5.4 O leitor da folha A4 e o protocolo de captura (implementado)

**Protocolo** decidido em 2026-09-29: folha A4 branca e lisa sobre superfície
mais escura que o papel; solo espalhado em um disco de 8 a 10 cm no centro da
folha (imitando a placa de 90 mm do treino, para que a grade não mude); foto de
cima, com a folha inteira no quadro e margem, luz difusa e sem flash.

**Encontrar a folha** (só operadores clássicos, sem modelo):

1. cópia de detecção com lado maior ≤ 1024 px, em cinza;
2. limiar de Otsu e maior componente claro conexo;
3. envoltória convexa, quadrilátero de maior área e refinamento das quatro
   arestas por mínimos quadrados;
4. recusa como `cropped` quando um canto sai do quadro e como `notFound`
   quando não há folha ou a folha clara está sobre fundo claro.

**Retificar e medir o solo:** os quatro cantos dão uma homografia (DLT de 4
pontos); a folha é retificada grosseiramente a 2 px/mm para achar o disco de
solo (maior componente escuro, centro pelo ponto mais distante do papel via
transformada de distância, raio menos 2 mm de margem); depois só o quadrado em
torno do disco é retificado em resolução nativa. Os 297 mm do lado maior dão a
escala exata.

**Uma foto sem folha legível é recusada com causa nomeada**
(`sheetNotFound`, `sheetCropped`), nunca analisada com escala estimada, porque
uma escala chutada erra em silêncio e com confiança. A classificação relata
sempre um resultado e, em caso de falha, uma de 14 causas nomeadas
([ADR 0015](../adr/0015-classification-reports-a-named-failure-cause.md)).

Fonte: [SPEC 0091](../specs/0091-find-the-a4-sheet-and-rectify-it-at-native-resolution.md),
[SPEC 0092](../specs/0092-measure-the-soil-on-the-a4-sheet-and-classify-with-it.md),
[ADR 0017](../adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)
(*Amended 2026-09-29*).

Figuras disponíveis: as cenas sintéticas usadas para validar o leitor estão em
`test/fixtures/sheet/` (folha frontal, inclinada 15° e 30°, girada 20°,
paisagem, cortada, sem folha, folha clara sobre fundo claro, com marcas).

### 5.5 Como o resultado é apresentado (implementado em parte)

O resultado mostra sempre a classe mais provável e sua porcentagem, com um
aviso graduado de confiança. O
[ADR 0011](../adr/0011-classification-verdict-from-margin-and-mass.md) define
um veredito de quatro estados (`conclusive`, `ambiguous`, `insufficient`,
`notAnalysed`) calculado da margem e da massa da distribuição, e o
[ADR 0018](../adr/0018-model-sees-fixed-size-greyscale-patches-and-their-spread-is-a-quality-signal.md)
trata a discordância entre patches como sinal de qualidade da captura, não de
confiança. **`ClassificationVerdict` e `ImageQualityAnalyzer` estão
implementados e testados, mas nenhuma tela os chama ainda.**

Fonte: ADR 0011, ADR 0018, [CLAUDE.md](../../CLAUDE.md) (*Known Technical Debt*).

### 5.6 Privacidade e segurança (implementado)

| Medida | Decisão |
| --- | --- |
| Metadados EXIF (inclusive GPS) removidos ao gravar a foto; a orientação é mantida | [ADR 0005](../adr/0005-strip-exif-at-image-storage-boundary.md) |
| Backup do sistema Android e transferência entre aparelhos desativados | [ADR 0006](../adr/0006-disable-android-os-backup.md) |
| Compartilhamento sem coordenadas por padrão, com opção por envio | [ADR 0007](../adr/0007-share-location-opt-in.md) |
| Monitoramento do modelo só local: nenhuma imagem, coordenada ou registro sai do aparelho | [ADR 0013](../adr/0013-local-first-model-monitoring.md) |
| Sessão do Google guardada em armazenamento seguro | [README.md](../../README.md) |

### 5.7 Dicas de manejo (implementado no app; corpus ainda não existe)

As dicas são **orientativas, nunca prescritivas**: informam e citam fontes, e
não mandam executar uma ação de campo ([CONTEXT.md](../../CONTEXT.md)).

O desenho passou por três decisões:

1. [ADR 0001](../adr/0001-research-agent-advisory-web-grounded.md) (aposentado):
   pesquisa na web a cada pedido, por um proxy com modelos em camada gratuita.
   O modelo gratuito previsto foi descontinuado em 2026-08-16, e a cadeia de
   dez passos cabia em cerca de quatro pedidos por dia e excedia o tempo-limite
   de 20 s do cliente.
2. [ADR 0022](../adr/0022-research-agent-precompiles-a-reviewed-corpus-and-escalates-under-a-cap.md):
   a pesquisa passa para uma etapa de build que gera um **corpus revisado por
   humanos**, chaveado por classe textural e família de atividade da argila,
   com sobreposições de uso da terra e bioma; o app compõe a resposta no
   aparelho, offline e sem enviar coordenadas.
3. [ADR 0023](../adr/0023-the-corpus-is-built-by-local-open-source-models-and-tier-2-leaves-v1.md):
   como a verba de US$ 50 prevista nunca foi liberada, o corpus é construído
   com modelos abertos locais (Ollama, em uma RTX 3070 de 8 GB), e a pesquisa
   ao vivo sai da v1.

**Estado:** o compositor no app, as grades de região e o cache estão
implementados e testados. A sondagem de calibração (B1) rodou uma vez e
produziu uma célula verdadeira, citada e fundamentada, mas sem valor de
manejo; em 2026-09-18 decidiu-se que as células citam material técnico da
Embrapa. O código da nova sondagem existe
([SPEC 0072](../specs/0072-read-the-passage-a-curated-pdf-names-and-give-the-model-all-of-it.md));
falta rodá-la antes das outras 43 células. **Não há corpus publicado**, então
hoje toda consulta responde "evidência insuficiente", o que é um estado
normal, não um erro.

Fonte: [corpus/README.md](../../corpus/README.md),
[CLAUDE.md](../../CLAUDE.md) (*Current Limitations*).

### 5.8 Sincronização e conta (implementado em parte)

A base de sincronização existe — UUID, `updated_at`, exclusões lógicas, fila
`sync_queue`, `SyncEngine` e o contrato `RemoteSyncBackend` — mas **não há
backend concreto e o `SyncEngine` não está ligado ao app**. Os dados são só
locais. O login Google funciona e é opcional.

Fonte: [CLAUDE.md](../../CLAUDE.md) (*Current Limitations*).

---

## 6. Métodos → 2 Material e Métodos

### 6.1 Metodologia de desenvolvimento

O projeto segue um framework de padrões próprio, vendorizado como submódulo em
`.standards/`, com estas práticas:

- **Especificar antes de construir:** toda mudança não trivial começa com uma
  SPEC (`docs/specs/NNNN-*.md`) com problema, decisão, alternativas
  consideradas, escopo (inclusive o que **não** entra), critérios de aceitação
  verificáveis, reprodutibilidade e riscos. Ela passa por um Spec Gate antes do
  código. Há 92 specs em `main`.
- **Registros de decisão (ADR):** decisões difíceis de reverter são promovidas
  a ADR (`docs/adr/`). Há 26 ADRs; dois foram aposentados (0001 e 0014) e
  continuam no arquivo, marcados, porque um número nunca é reutilizado.
- **Testes antes da implementação** (vermelho → verde → refatorar).
- **Revisão em três camadas:** R1 interna, na sessão do autor; R2 por um
  modelo de **outro fornecedor** (GPT, via Antigravity), duas rodadas por pull
  request; R3 automática no pull request (CodeRabbit). A revisão humana segue o
  método CRURA e decide o merge.
- **Gates automáticos** (`mf check`: spec, commit, branch, docs, records,
  agents, design) nos hooks de git e no CI.
- **Conventional Commits** e nomes de branch `tipo/descrição`.
- **Desenvolvimento assistido por IA:** os arquivos de instrução dos agentes
  (`CLAUDE.md`, `AGENTS.md`) são gerados a partir de
  `docs/agents/project.md`; o autor declara fornecedor e modelo para que a
  revisão R2 seja de fornecedor diferente. O histórico tem 22 commits de
  autoria "Claude".

Fonte: `.standards/docs/standards/INDEX.md`, `spec_method.md`,
`ai_guidelines.md`, `crura_method.md`; [`.framework.toml`](../../.framework.toml).

[LACUNA: se a instituição exige declarar o uso de assistentes de IA na
escrita do relatório e no desenvolvimento, e em que formato.]

### 6.2 Protocolo experimental E0

Experimento de viabilidade com **quatro braços** e regra de decisão
**pré-registrada** ([SPEC 0044](../specs/0044-four-arm-e0-feasibility-gate.md)):

| Braço | O que é |
| --- | --- |
| `shuffled_control` | o treinador da CNN com rótulos embaralhados — o piso |
| `cnn` | MobileNetV2 ajustada (incumbente) |
| `descriptors` | 26 descritores + regressão logística regularizada |
| `encoder_probe` | 1280 dimensões de um codificador ImageNet congelado + classificador linear |

**Avaliação** ([ADR 0020](../adr/0020-evaluation-is-repeated-group-k-fold-with-nested-selection.md),
[SPEC 0042](../specs/0042-repeated-group-k-fold-evaluation-protocol.md)):
validação cruzada estratificada e agrupada por amostra, k = 5, repetida
R = 5 vezes, com seleção aninhada (`inner_k` = 4), totalizando 125
treinamentos por braço. A unidade de todo intervalo e contraste é o grupo de
amostra (77 grupos testáveis). Sementes: 42, 1042, 2042, 3042, 4042.

**Regra de leitura:** um braço só "supera o controle" se o teste exato de
McNemar rejeitar a α = 0,05 após correção de Holm **e** a diferença observada
for pelo menos o menor efeito detectável (MDE) daquele contraste. O codificador
só seria adotado se cumprisse quatro condições (executado, vencer o contraste
secundário, passar no teste de latência, emendas aceitas); caso contrário,
adota-se o caminho de descritores.

**Diagnósticos complementares:**

- **Sonda de população** ([SPEC 0055](../specs/0055-probe-whether-the-capture-population-is-predictable.md)):
  a população de captura é recuperável dos patches?
- **Sensibilidade à população B** ([SPEC 0057](../specs/0057-measure-whether-the-transported-population-changes-the-answer.md)):
  retirar B do treino muda o resultado?
- **Ablação dos descritores** ([SPEC 0065](../specs/0065-the-descriptor-ablation-the-gate-reports.md)):
  qual grupo de descritores carrega o sinal?

**Ambiente:** TensorFlow 2.21.0, Keras 3.14.0, scikit-learn 1.5.2,
numpy 1.26.4; GPU RTX 3070 (WSL2) para `cnn`, controle e codificador, CPU
(Windows) para os descritores.

Fonte: [docs/ml/e0-verdict.md](../ml/e0-verdict.md) (*Provenance*).

### 6.3 Paridade Python → Dart

O classificador foi treinado em Python e reimplementado em Dart. A paridade é
garantida por **goldens entre linguagens**: fixtures de patches com os
descritores e a distribuição que o Python calcula, que o Dart deve reproduzir
dentro de uma tolerância fixada em spec. A reamostragem bilinear do Pillow é
reproduzida **byte a byte**, inclusive o arredondamento "metade para o par" do
Python (13.178 trincas RGB com luma exatamente ,5 mostram por que importa).

Fonte: [ADR 0024](../adr/0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md),
[ADR 0025](../adr/0025-the-dart-resample-reproduces-pillows-bilinear-byte-for-byte.md),
[SPEC 0077](../specs/0077-describe-a-patch-in-dart-under-a-cross-language-golden.md),
[SPEC 0080](../specs/0080-compare-the-regenerated-descriptor-golden-within-tolerance.md).

### 6.4 Validação do leitor da folha A4

Cenas **sintéticas** geradas por `ml/scripts/generate_sheet_fixtures.py`, com
critérios: cada canto detectado a até 0,5 % da diagonal da folha; escala
retificada a até 1 % da escala colocada; a imagem espelhada dá a mesma escala
(até 0,5 %); marcas na folha retificada a até 1 mm da posição real; foto sem
folha, folha clara em fundo claro e folha cortada são recusadas com a causa
certa; o gerador reproduz as fixtures byte a byte.

Fonte: [SPEC 0091](../specs/0091-find-the-a4-sheet-and-rectify-it-at-native-resolution.md)
(*Acceptance Criteria*).

### 6.5 Medição de custo

Teste de integração em modo *profile* (AOT) num emulador Android (x86_64,
API 36, 4 núcleos, 4 GB) sobre um Intel Core i5-1135G7, cinco execuções por
cena, medindo cada fase contra o tempo-limite de 15 s de `classify`.

Fonte: [docs/ml/descriptor-path-cost.md](../ml/descriptor-path-cost.md).

---

## 7. Resultados → 3 Resultados e Discussão

### 7.1 E0: há sinal? (medido no acervo de placas de Petri)

| Braço | Acurácia por grupo | Macro-F1 por foto (mediana de 5 repetições) | Supera o controle? |
| --- | ---: | ---: | --- |
| `shuffled_control` | 0,2727 | 0,2152 | — (piso) |
| `cnn` | 0,4416 | 0,2935 | **não** |
| `descriptors` | **0,6883** | **0,6232** | **sim** |
| `encoder_probe` | 0,7532 | 0,6996 | **sim** |

| Contraste | Diferença | p (Holm) | MDE | Leitura |
| --- | ---: | ---: | ---: | --- |
| descritores × controle | +0,4156 | 6,61e-06 | 0,2629 | significativo, 1,6× o MDE |
| codificador × controle | +0,4805 | 3,63e-07 | 0,2534 | significativo, 1,9× o MDE |
| CNN × controle | +0,1688 | 0,0596 | 0,2434 | nenhuma das duas condições |
| codificador × descritores | +0,0649 | 0,3018 (sem Holm, família secundária) | 0,1336 | não significativo e abaixo do MDE |

**Leituras registradas:**

- A classe textural é recuperável dessas fotografias na resolução do
  experimento.
- **A CNN incumbente não superou seu próprio controle.** O macro-F1 dela variou
  de 0,2709 a 0,4682 entre repetições — a maior dispersão entre os braços, por
  um fator de seis —, compatível com ajustar 2,2 M parâmetros em 77 grupos.
- Os dois braços que passaram têm em comum uma **representação fixa com
  classificador linear regularizado**; o registro trata isso como hipótese, não
  como resultado.
- O codificador ficou 6,5 pontos acima dos descritores, mas o experimento não
  resolve menos de 13,4 pontos. Ele falhou três das quatro condições de adoção
  (não venceu o contraste, latência não medida, emendas não pedidas), então a
  regra pré-registrada **adotou o caminho de descritores**.
- Nenhum número por classe é resultado: cada um se apoia em três ou quatro
  grupos de teste por dobra.

Fonte: [docs/ml/e0-verdict.md](../ml/e0-verdict.md).

### 7.2 Ablação dos descritores

| Grupo removido | Acurácia sem ele | Perda | p (Holm) | MDE | Carrega sinal? |
| --- | ---: | ---: | ---: | ---: | --- |
| LBP | 0,5325 | +0,1558 | 0,0167 | 0,1467 | **sim** |
| primeira ordem | 0,6753 | +0,0130 | 1,0 | 0,1282 | não |
| espectral | 0,6753 | +0,0130 | 1,0 | nenhum | não |
| GLCM | 0,6753 | +0,0130 | 1,0 | nenhum | não |

Os padrões binários locais (LBP) carregam o braço: retirá-los custa 15,6
pontos. Isso confirma que o modelo lê **textura** e não brilho, o modo de falha
que a SPEC 0044 temia. A ablação não autoriza descartar os outros três grupos:
"nenhum" no MDE significa que o teste não tinha região de rejeição, isto é, o
experimento estava cego para eles.

Fonte: [docs/ml/e0-verdict.md](../ml/e0-verdict.md) (*The descriptor ablation*).

### 7.3 Sonda de população e sensibilidade

- **A população de captura é recuperável dos patches:** acurácia por grupo de
  90/97 = 0,928, intervalo de Wilson 95 % de [0,858; 0,965], contra 0,649 de
  sempre responder a população majoritária.
- **Mas retirar B do treino não muda o resultado de forma detectável:**
  descritores −0,0260 (p = 0,7539, MDE 0,1082); CNN +0,1039 (p = 0,2005, MDE
  0,1941). Os dois caem em "não significativo, abaixo do MDE", e B segue no
  treino e fora de todo teste
  ([ADR 0021](../adr/0021-the-transported-population-stays-in-training-and-out-of-every-test-side.md)).

Fonte: [docs/ml/capture-population-probe.md](../ml/capture-population-probe.md),
[docs/ml/transported-population-sensitivity.md](../ml/transported-population-sensitivity.md).

### 7.4 Custo por fotografia (medido em emulador)

| Fase | Mediana (ms) com o leitor A4 |
| --- | ---: |
| Decodificação | 1.347 |
| Orientação | 22 |
| Conversão de quadro | 59 |
| Medição (leitor A4) | 310 |
| Grade (reamostrar e cortar) | 27 |
| 26 descritores × 21 patches | 457 |
| Pontuação | 0 |
| **`classify` de ponta a ponta** | **2.637** (máx. 2.709) |

Uma classificação leva 2,6 s na mediana, com folga de cerca de 5,5× sobre o
tempo-limite de 15 s; o leitor custa cerca de 0,3 s. No pior caso de
decodificação (imagem de ruído de 12 MP, sem o leitor) foram 5,5 s. O custo
dominante é decodificar o JPEG, não os descritores (~23 ms por patch). **A
folga é do emulador, não de um celular**: nenhum aparelho físico foi medido, e
um telefone 2,5× mais lento atingiria o tempo-limite no pior caso.

Fonte: [docs/ml/descriptor-path-cost.md](../ml/descriptor-path-cost.md).

### 7.5 Custo computacional do E0

| Braço | Treinamentos | Tempo de parede |
| --- | ---: | ---: |
| `cnn` | 125 | 26,5 h |
| `shuffled_control` | 125 | 19,6 h |
| `encoder_probe` | 125 | 0,8 h |
| `descriptors` | 125 | 0,2 h |

Fonte: [docs/ml/e0-verdict.md](../ml/e0-verdict.md) (*Cost*).

### 7.6 Resultados de engenharia (medidos no repositório em `64a3333`)

| Métrica | Valor |
| --- | ---: |
| Período | 2026-03-05 a 2026-10-01 |
| Commits em `main` | 1.108 |
| Pull requests mergeados | 144 |
| Specs / ADRs | 92 / 26 |
| Dart em `lib/` (sem `*.g.dart`) | 115 arquivos, 12.710 linhas |
| Dart em testes (`test/`, `integration_test/`) | 89 arquivos de teste, 13.487 linhas, ~597 casos (`test`/`testWidgets`) |
| Python em `ml/` | 33.520 linhas; 44 arquivos de teste, 774 funções de teste |
| Python em `corpus/` | 3.752 linhas; 135 funções de teste |
| Jobs de CI | 8 (analyze, test, ml-tests, corpus-tests, build APK, build iOS, smoke em emulador, gates) |

Fonte: comandos `git rev-list --count`, `git log --merges`, `wc -l` e
`grep` sobre o repositório; [CLAUDE.md](../../CLAUDE.md) (*CI Pipeline*).
As linhas contam comentários e brancos.

---

## 8. Limitações e ameaças à validade → 3 Resultados e Discussão

1. **Mudança de domínio não medida.** A acurácia de 0,6883 vem de placas de
   Petri; o app fotografa sobre folha A4. Nada mediu o custo dessa troca, e por
   isso a loja não citará acurácia (ADR 0026).
2. **Leitor A4 validado só em cenas sintéticas.** Fotografias reais no
   protocolo precisam validá-lo antes do lançamento.
3. **Amostra pequena.** 77 grupos testáveis; o MDE fica entre 0,11 e 0,26
   conforme o contraste, e nenhuma afirmação por classe é sustentável.
4. **Rótulos não verificáveis e sem granulometria.**
5. **Uma câmera, um protocolo, um operador, material seco e peneirado.**
6. **Classe ausente.** Uma amostra siltosa receberá uma das quatro classes; o
   detector de fora-de-distribuição previsto (`rejectedOod`) ainda não tem
   implementação.
7. **Custo medido em emulador**, não em aparelho físico.
8. **Reprodução exige Keras 3.14.0**, e não o 3.15.1 fixado em
   `ml/requirements.txt`.
9. **Dicas sem corpus publicado.**

Fonte: [ADR 0026](../adr/0026-the-first-play-release-waits-for-classification.md),
[docs/ml/e0-verdict.md](../ml/e0-verdict.md) (*What this does not license*),
[ADR 0016](../adr/0016-dataset-is-the-existing-dish-archive-and-siltosa-is-out-of-v1.md),
[CLAUDE.md](../../CLAUDE.md) (*Current Limitations*, *Known Technical Debt*).

---

## 9. Em andamento e trabalhos futuros → 4 Considerações Finais

**Pull requests abertos em 2026-10-01** (não estão em `main`):

- [LukeSantossz/visiosoil-app#305](https://github.com/LukeSantossz/visiosoil-app/pull/305) — apagar o conteúdo e as dicas em cache de um registro excluído
- [LukeSantossz/visiosoil-app#307](https://github.com/LukeSantossz/visiosoil-app/pull/307) — apagar a cópia do seletor de imagem após gravar a foto
- [LukeSantossz/visiosoil-app#308](https://github.com/LukeSantossz/visiosoil-app/pull/308) — recuperar a foto quando o Android encerra o app
- [LukeSantossz/visiosoil-app#309](https://github.com/LukeSantossz/visiosoil-app/pull/309) — relatar confiança, cobertura e calibração na avaliação
- [LukeSantossz/visiosoil-app#310](https://github.com/LukeSantossz/visiosoil-app/pull/310) — persistir a distribuição de classes e as versões do contrato
- [LukeSantossz/visiosoil-app#311](https://github.com/LukeSantossz/visiosoil-app/pull/311) — pedir câmera e localização quando a captura precisar
- [LukeSantossz/visiosoil-app#312](https://github.com/LukeSantossz/visiosoil-app/pull/312) — estudar temperatura e bandas conformes para o veredito

**Trabalho futuro registrado:**

- validar o leitor A4 e medir a acurácia em fotos reais capturadas no
  protocolo — condição para o primeiro lançamento na Google Play (ADR 0026);
- ligar o veredito (ADR 0011) e o analisador de qualidade às telas, com nova
  tentativa específica por causa de falha;
- detector de fora-de-distribuição para a Siltosa ausente;
- rodar a nova sondagem do corpus e construir as 44 células de dicas;
- backend de sincronização;
- medir custo em aparelho físico.

---

## 10. Linha do tempo

| Mês (2026) | Commits | Marcos |
| --- | ---: | --- |
| Março | 27 | Projeto Flutter criado (05/03); telas iniciais, GoRouter, Riverpod, captura com `image_picker` |
| Abril | 50 | Pipeline de ML (treino, avaliação, exportação) e integração TFLite; histórico com seleção múltipla; Material 3 |
| Maio | 62 | Splash com permissões, filtros do histórico, tela de resultado com faixas de confiança; telas de lote e plano de manejo ainda simuladas |
| Junho | 142 | Corte de escopo: telas simuladas, galeria e telas inalcançáveis removidas (11–15/06); armazenamento estável das fotos; base de sincronização (Drift v3); login Google; lado do app das dicas (Drift v4); ADRs 0001–0003 |
| Julho | 264 | Specs 0001–0031: privacidade (EXIF, backup, compartilhamento), assinatura de release, R8 e smoke, CI de iOS, sistema de design, estados de erro; ADRs 0004–0011 |
| Agosto | 123 | Specs 0032–0039 (treino determinístico, protocolo de dados, contrato `spec.json`, patches em cinza); entrega do acervo (25/08) e ADRs 0014–0018 |
| Setembro | 438 | Specs 0040–0092 e ADRs 0019–0026: ingestão do `v1`, protocolo k-fold, E0 e veredito, sonda e sensibilidade, redesenho das dicas (0022, 0023), adoção dos descritores (22/09) e porte para Dart, remoção do TFLite, gates no CI, custo, decisão de lançamento e leitor A4 (29/09) |
| Outubro | 2 | Estado deste levantamento (01/10) |

Fonte: `git log` de `origin/main` (contagem por mês) e data de criação de cada
spec e ADR.

---

## 11. Divergências encontradas entre registros

O levantamento não corrige registros (SPEC 0100, *Scope*); só aponta onde eles
discordam, para que o relatório use a fonte certa.

| Onde | O que diz | O que vale |
| --- | --- | --- |
| [CONTEXT.md](../../CONTEXT.md) | o classificador atribui uma de **cinco** classes | o modelo emite **quatro** (ADR 0016, SPEC 0046) |
| [README.md](../../README.md), *Database schema* | esquema **v4** | **v5** (CLAUDE.md, *Database Schema*) |
| README.md, *Tech Stack* | treino com MobileNetV2; `http` para o proxy de pesquisa | o classificador adotado é o de descritores (ADR 0024); o proxy não tem chamador (CLAUDE.md) |
| ADR 0016, título e tabela | 194 amostras | 105 grupos de amostra (emenda de 2026-09-01) |

---

## 12. Mapa: seção do modelo → fontes

| Seção do modelo de artigo original | Seções deste levantamento | Fontes principais |
| --- | --- | --- |
| 1 Introdução | 2, 3 | README, CONTEXT.md, ADR 0017, ADR 0018; **bibliografia externa** |
| 2 Material e Métodos | 4, 6 | ADR 0016, SPEC 0040, ADR 0019–0021; `.standards/`, SPEC 0042, 0044, 0055, 0057, 0065, 0077, 0086, 0091 |
| 3 Resultados e Discussão | 5, 7, 8, 11 | ADR 0005–0007, 0011, 0013, 0015, 0017, 0022–0026; SPEC 0083, 0092; `docs/ml/*.md` |
| 4 Considerações Finais | 9 | ADR 0026, PRs abertos |

## 13. Lacunas a preencher pelo autor

- [ ] Instituição, curso, orientador(a), data de defesa.
- [ ] Referências bibliográficas (seção 3).
- [ ] Laboratório, origem das amostras e método de classificação (seção 4.1).
- [ ] Capturas de tela do app (seção 5.1).
- [ ] Política da instituição sobre uso de assistentes de IA (seção 6.1).
- [ ] Se possível antes da entrega: acurácia em fotos reais sobre folha A4 e
      custo em aparelho físico (seções 7 e 8).
