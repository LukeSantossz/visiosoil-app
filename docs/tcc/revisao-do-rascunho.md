# Revisão do rascunho do artigo

Revisão do rascunho *Aplicativo móvel para identificação da textura do solo
como ferramenta de apoio na tomada de decisão agrícola* (`.docx` no Drive,
versão de 2026-10-01), contra o modelo `modelo_artigo_original.docx` e as
anotações do orientador que estão no próprio rascunho.

**Critério.** O texto de vocês é a referência e a direção do trabalho não
muda. O repositório entra só na seção 4, para conferir afirmações que o texto
faz sobre o aplicativo. Cada divergência vem com o que o código mostra e fica
para vocês decidirem.

---

## 1. Situação em relação ao modelo

| Seção do modelo | No rascunho | Situação |
| --- | --- | --- |
| Título, autores e notas de vínculo | só o título (no nome do arquivo) | faltam autores e notas de rodapé de vínculo |
| RESUMO e Palavras-chave | só as anotações do orientador | a escrever por último (seção 7) |
| 1 INTRODUÇÃO | três versões (Versão 1, Versão 2 e a final) | consolidar na final e apagar as outras |
| 2 MATERIAL E MÉTODOS | texto sem o título da seção | falta o título; conteúdo na seção 3 |
| 3 RESULTADOS E DISCUSSÃO | só as anotações do orientador | a escrever (seção 6) |
| 4 CONSIDERAÇÕES FINAIS | ausente | a escrever (seção 7) |
| REFERÊNCIAS | três listas, parcialmente repetidas | unificar em uma lista alfabética (seção 5) |

Formatação exigida pelo modelo: Arial 12 com texto justificado; legendas e
fontes de figuras e tabelas em tamanho 10; referências alinhadas à esquerda,
em espaço simples e separadas por uma linha em branco. O orientador também
anotou que referência não é justificada. As seções são numeradas sem ponto
("1 INTRODUÇÃO").

---

## 2. Introdução (versão final)

A Introdução está completa no essencial: contexto, problema, iniciativas
existentes, lacuna e objetivo no último parágrafo, como o modelo pede. Os
pontos abaixo estão em ordem de importância.

1. **A ordem granulometria → textura está certa e fica.** Esta revisão
   sugeriu inverter a ordem, mas o comentário de Gustavo Faulin no documento
   pede granulometria antes de textura, em ordem cronológica, porque a textura
   é determinada a partir da granulometria. A aba "Revisão - Métodos e
   Resultados" segue o orientador.
2. **Falta ligar o triângulo textural às quatro classes do trabalho.** A
   Figura 1 mostra o triângulo, mas Material e Métodos fala de quatro classes
   (Arenosa, Média, Argilosa e Muito Argilosa) que não aparecem na Introdução.
   Essas quatro são grupamentos texturais e não as classes do triângulo. Uma
   frase que diga como o triângulo leva aos grupamentos, com fonte técnica,
   fecha esse buraco. O Sistema Brasileiro de Classificação de Solos da
   Embrapa é o candidato natural; confiram a edição e as faixas antes de
   citar.
3. **A fonte da Figura 1 é um blog** (Ataíde, 2022). Uma figura técnica
   central fica mais sólida com fonte técnica (Embrapa, SBCS ou um manual de
   solos).
4. **O parágrafo dos desafios foi muito encurtado.** Na Versão 1, o parágrafo
   sobre Kaplan et al. (2024) e Sattar et al. (2024) explicava iluminação,
   padronização da captura (a "Blackbox") e resolução. Na versão final isso
   virou uma frase. Não precisa voltar para a Introdução, mas é o melhor
   material para a Discussão: é contra esses desafios que o aplicativo será
   comparado (seção 6).
5. **"de fácil entendimento e utilização por todo público"** é uma afirmação
   que pede evidência, como um teste de usabilidade, e a banca pode perguntar
   por ela. Sem essa avaliação, é mais seguro falar em intenção ("pensada
   para ser de fácil uso").
6. **Tempo verbal do objetivo:** "O objetivo deste trabalho foi desenvolver…"
   seguido de "Busca-se desenvolver…". Usem um tempo só; o modelo usa "O
   objetivo do trabalho foi".

### Redação

- "pode ocasionar **em** decisões indevidas" → "pode ocasionar decisões
  indevidas" ("ocasionar" não pede preposição).
- "A ausência de informações relevantes do solo**,** pode ocasionar" → sem
  vírgula entre sujeito e verbo.
- "Conforme a EMBRAPA há cerca de 150 laboratórios" → "Conforme a Embrapa,
  há cerca de 150 laboratórios".
- "uma pesquisa realizada no município de Uruçuí […], **na qual relata que**"
  → "uma pesquisa […] que relata que" ou "segundo a qual".
- "uma interface simples e intuitiva, **na qual é** de fácil entendimento" →
  "que seja de fácil entendimento".

---

## 3. Material e Métodos

1. **Falta o título "2 MATERIAL E MÉTODOS".**
2. **O modelo pede que o trabalho possa ser repetido**, e hoje a seção
   descreve as ferramentas, mas não os procedimentos. Para a reprodução
   faltam:
   - **o conjunto de imagens:** origem, quantidade, classes e como as fotos
     foram feitas;
   - **o preparo das imagens** antes do treino;
   - **como o modelo foi treinado e avaliado:** divisão dos dados, métrica e
     número de repetições;
   - **o procedimento de captura no aplicativo:** o que o usuário faz e em que
     condições;
   - **o processo de desenvolvimento:** etapas, versionamento e testes.

   O repositório tem todos esses dados registrados; a seção 4 e o
   [levantamento do projeto](revisao-do-projeto.md) dizem onde estão.
3. **Dezesseis parágrafos seguidos, um por ferramenta, viram uma lista em prosa.**
   O modelo permite Quadros: um Quadro "Tecnologias utilizadas" (ferramenta,
   função no aplicativo, referência) diz o mesmo em meia página e deixa o
   texto para os procedimentos.
4. **Concordância e redação:**
   - "A captura de imagens do solo utilizadas como base para a análise **são
     obtidas**" → "As imagens do solo […] são obtidas" ou "A captura […] é
     realizada".
   - "O TensorFlow Lite é um conjunto de ferramentas **voltada**" →
     "voltado".
   - "retornando as probabilidades associadas a cada classe textural, **que a
     partir desses valores**, o aplicativo determina" → dividir em duas
     frases.

---

## 4. Afirmações sobre o aplicativo que divergem do código

O texto descreve algumas partes do aplicativo de um jeito que o código, em
2026-10-01 (commit `64a3333`), já não confirma. A banca pode pedir para ver o
aplicativo funcionando, então vale decidir cada ponto de forma consciente.
Nenhum deles muda o objetivo: o método atual também é visão computacional com
aprendizado de máquina.

| Trecho do rascunho | O que o código mostra | Fonte |
| --- | --- | --- |
| "O TensorFlow Lite […] foi utilizado para realizar a inferência do modelo" | O TFLite foi integrado em 21/04/2026 e **removido em 29/09/2026**. Hoje não há TFLite no aplicativo: a classificação é calculada em Dart. | `pubspec.yaml`; [SPEC 0084](../specs/0084-remove-the-tflite-export-that-nothing-ships.md) |
| "o projeto utiliza a MobileNetV2 […] por meio de transferência de aprendizado" | A MobileNetV2 foi treinada e avaliada, mas **não é o modelo que o aplicativo usa**. Na avaliação comparativa obteve acurácia de 0,4416 e não superou um controle treinado com rótulos embaralhados (0,2727; p = 0,0596). O aplicativo usa 26 descritores de textura das imagens e uma regressão logística, com acurácia de 0,6883 nas mesmas condições. | [docs/ml/e0-verdict.md](../ml/e0-verdict.md); [ADR 0024](../adr/0024-the-descriptor-path-is-the-v1-classifier-computed-in-dart-from-a-contract-of-numbers.md) |
| "O treinamento dessa rede foi conduzido com o Keras" / Python para "o treinamento da rede neural" | Vale para a MobileNetV2. O modelo adotado foi treinado com scikit-learn (Python), e não é uma rede neural. | ADR 0024 |
| GitHub Actions faz "o treinamento do modelo de aprendizado de máquina" | **O CI não treina modelo.** Ele roda a análise do código, os testes em Flutter e Python, a compilação Android e iOS, um teste do APK em emulador e os gates de padrões. O treino rodou na máquina de desenvolvimento. | `.github/workflows/ci.yml` |
| "funcionalidades complementares, como […] recomendações de manejo do solo" | A função existe no aplicativo ("dicas de manejo", de caráter orientativo), mas **ainda não há base de conteúdo publicada**: hoje toda consulta responde que não há evidência suficiente. | [corpus/README.md](../../corpus/README.md); `CLAUDE.md` (*Current Limitations*) |
| Acurácia ou desempenho do aplicativo (se o texto citar) | A acurácia de 0,6883 foi medida em fotos de **placas de Petri** do acervo. O aplicativo fotografa o solo sobre uma **folha A4**, e nenhuma acurácia foi medida nessas fotos. | [ADR 0026](../adr/0026-the-first-play-release-waits-for-classification.md) |

As bibliotecas citadas (Flutter, Riverpod, GoRouter, SQLite e Drift,
`image_picker`, `geolocator`, `geocoding`, `permission_handler`,
`google_sign_in`, `flutter_secure_storage`) estão todas no aplicativo e com a
função que o texto descreve.

**Sobre a MobileNetV2 e o TFLite**, há três caminhos coerentes, e a escolha é
de vocês:

- descrever o modelo atual em Material e Métodos;
- manter a MobileNetV2 como modelo e apresentar os resultados dela;
- contar a trajetória: começar pela MobileNetV2, compará-la com outras
  abordagens e adotar a que funcionou.

O terceiro caminho combina com as anotações do orientador ("relatar tudo o que
foi feito", "passo a passo do desenvolvimento"), mas aumenta a seção de
Resultados.

---

## 5. Citações e referências

**Citação sem referência, ou o contrário**

- **Orawo et al. (2026)** está nas referências, mas não é citado no texto.
  Citar ou remover; o modelo diz que as referências são os documentos citados.
- O link da **Revista Cultivar** ("déficit de 8 milhões de análises de solo")
  está solto no fim do arquivo, sem citação e sem referência formatada. Se
  for usado, merece entrar na Introdução, porque reforça o problema do acesso
  à análise.
- **(PUB.DEV, 2026)** cita o `flutter_secure_storage`, mas a referência está
  como **STEENBAKKER.DEV**. Os dois precisam coincidir.

**Ano ou autoria divergente**

- **(ROCHA, 2026)** no texto, mas a referência é de **2024** (o TCC é de
  2024; 2026 é só o ano de acesso).
- **(Flutter, 2026)** para o Google Sign-In, mas a referência é de **2025**.
- **Centeno et al. (2017):** o acesso está como "10 ago. **2025**" e todos os
  outros são de 2026. Conferir.

**Mesmo autor e mesmo ano precisam de letra** (regra do próprio modelo)

- AWS 2026 (Flutter e Python) → 2026a e 2026b.
- Baseflow 2026 (Geocoding, Geolocator e Permission handler) → 2026a, 2026b
  e 2026c.
- Flutter 2026 (GoRouter e Image picker) → 2026a e 2026b.
- TensorFlow 2026 (Keras e TensorFlow Lite) → 2026a e 2026b.

**Referências incompletas ou quebradas**

- **EMBRAPA (2026):** sem ano no corpo da referência e com a URL partida ao
  meio por um `>`.
- **EMBRAPA SOLOS (2026):** sem título; é a fonte dos "cerca de 150
  laboratórios credenciados", então precisa de título.
- **GITHUB:** o link aponta para a página do `flutter_riverpod`, embora o
  texto mostre o endereço do GitHub Actions, e há um "8" solto depois de
  "2026.".

**Padronização**

- Uma lista só, em ordem alfabética. Na lista de Material e Métodos, BINDER
  aparece depois de SANDLER.
- A mesma caixa nas citações entre parênteses, como no modelo ("Derrida,
  1967"): "(ROCHA, 2026)" → "(Rocha, 2024)"; "(KAPLAN et al., 2024)", da
  Versão 2, → "(Kaplan et al., 2024)". E a grafia do nome: "Mcfadden" →
  "McFadden", "Tensorflow" → "TensorFlow".
- "[S. l.]" aparece em algumas referências de site e em outras não.
- **Quantidade:** são 31 referências diferentes, para cerca de 20
  recomendadas pelo modelo, e cerca de metade é documentação de software
  (`pub.dev`, AWS, TensorFlow, SQLite, GitHub). Não é um limite, mas a Discussão vai precisar de mais artigos
  científicos para comparar os resultados, e o Quadro de tecnologias da seção
  3 pode concentrar as referências de software.

---

## 5a. Verificação das referências (2026-10-01)

Cada referência citada foi conferida na fonte (Crossref, DataCite, páginas
das revistas e dos repositórios), e cada afirmação atribuída a ela foi
procurada no texto da fonte. A aba "Revisão - Métodos e Resultados" do
documento já traz as correções.

**Corrigido**

| Referência | O que estava | O que a fonte mostra |
| --- | --- | --- |
| Faulin; Aleixo; Favan (2025) | iniciais "D. C.", "C." e "R." | Gustavo Di Chiacchio Faulin, Gabriel Carneiro Aleixo, João Ricardo Favan |
| Embrapa Solos (2026) | "cerca de 150 laboratórios credenciados" | cerca de 150 laboratórios de fertilidade *participam* do PAQLF; a lista de 2026 tem 139 aprovados, 86 em granulometria (52 no Centro-Oeste, 35 no Sudeste, 22 no Sul, 17 no Nordeste, 13 no Norte) |
| Rocha (2024) | "cerca de 80%", citado como 2026 | 81,7% não sabiam onde fazer a análise; dois laboratórios no Piauí, nos campi da UFPI em Bom Jesus e Teresina; o TCC é de 2024 |
| Embrapa (2026), região Norte | autoria "EMBRAPA", ano 2026 | projeto da Embrapa Amazônia Ocidental, 2015 a 2019; a frase sobre infraestrutura e acesso confere |
| Bolfe et al. (2020) | "análise espacial e temporal" | a definição fala em análise espacial, sem "temporal" |
| Centeno et al. (2017) | URL antiga e acesso "2025" | o DOI resolve; a revista mudou de endereço |

**Confere**: Kaplan et al. (2024), Sattar et al. (2024), McFadden; Njuki;
Griffin (2023), Moraes; Salame (2017), Castro; Gonçalves; Castro (2024),
Bertoni; Lombardi Neto (2017), Indie Mobile Apps (2026, com versão iOS),
Santos et al. (2018) e as referências de software. As nove referências
metodológicas acrescentadas na primeira versão da aba (Duda e Hart, Haralick
et al., Hartley e Zisserman, Holm, McNemar, Ojala et al., Otsu, Pedregosa et
al. e Santos et al.) conferem e passaram a ter DOI quando existe. Quando a aba
passou a dar uma visão geral da construção do aplicativo, sem o detalhe das
técnicas do modelo, ficaram só McNemar (1947), que nomeia o teste usado na
avaliação, e Santos et al. (2018), citado na Introdução; as outras sete saíram
junto com os trechos que as citavam, e a lista final tem 31 referências.

**Acrescentado**: Romanelli (2025), da Revista Cultivar, que estava solta na
aba "Guia 6" e sustenta o déficit de cerca de 8 milhões de análises de solo
por ano.

**Não foi possível confirmar no texto da fonte**, porque o site bloqueia
acesso automático ou só o resumo está disponível:

- Sattar et al. (2024): a frase sobre características físicas, químicas e
  biológicas como principais fatores da qualidade do solo, e "espaço" e
  "logística" entre as exigências do laboratório. O resumo confirma custo,
  tempo, equipamentos e profissionais.
- Centeno et al. (2017): a frase sobre defensivos agrícolas e prejuízos
  econômicos e ambientais. O resumo confirma a relação entre textura e
  manejo.
- Ataíde (2022): a página do triângulo textural. A Figura 1 do SiBCS
  (Santos et al., 2018, p. 47, "Guia para grupamento de classes de
  textura") é uma alternativa técnica.

## 6. O que falta em Resultados e Discussão

É o capítulo que o orientador marcou como o mais importante, e ainda não
existe. As anotações dele pedem:

- relatar tudo o que foi feito, passo a passo;
- prints da criação do projeto;
- prints de código com fundo branco;
- toda figura com título e explicada no texto.

Um roteiro que segue a ordem de Material e Métodos de vocês:

1. **Estrutura do projeto e telas**: prints de cada tela (permissões,
   apresentação inicial, início, captura, resultado, histórico,
   configurações) e explicação do fluxo do usuário.
2. **Captura e localização**: câmera, GPS, endereço e o procedimento de
   captura.
3. **Armazenamento local**: tabelas e histórico.
4. **Modelo de classificação**: conjunto de imagens, treino, avaliação e
   resultados (ver a decisão da seção 4).
5. **Integração do modelo ao aplicativo**: o que acontece entre a foto e a
   classe exibida.
6. **Infraestrutura**: CI, testes e versionamento.
7. **Discussão**: comparar com o que a Introdução levantou.
   - Kaplan et al. (2024) e Sattar et al. (2024) pedem captura padronizada.
     Sattar resolveu isso com uma caixa fechada; o aplicativo pede uma folha
     A4 branca sob luz difusa, e a folha também fornece a escala da foto.
   - Moraes e Salame (2017) exigem a granulometria como entrada; o aplicativo
     parte da foto.
   - Comparar com o Soil Identifier App, se houver como.

O [levantamento do projeto](revisao-do-projeto.md) reúne, com a fonte de cada
dado, o material do repositório para cada item: datas, números do
experimento, protocolo de captura, privacidade, testes e CI.

**Falta material que o repositório não tem:** prints das telas, que exigem
rodar o aplicativo num aparelho ou emulador, e fotos reais tiradas com o
aplicativo.

---

## 7. Resumo e Considerações Finais

**Resumo**, a escrever depois de Resultados:

- **Tamanho:** 230 a 250 palavras pela nota do orientador (o modelo aceita de
  100 a 250, então vale a regra mais estreita).
- **Formato:** parágrafo único, voz ativa, terceira pessoa do singular.
- **Ordem:** introdução (1 a 3 frases), objetivo, metodologia (1 a 2 frases),
  o que foi feito, resultados, conclusão e próximos passos.
- **Palavras-chave:** de 3 a 5, separadas por ponto, em ordem de importância,
  de preferência sem repetir palavras do título. O título já usa "aplicativo
  móvel", "textura do solo" e "tomada de decisão agrícola"; candidatas que não
  repetem: visão computacional, aprendizado de máquina, agricultura digital,
  granulometria.
- **Conferência:** o orientador sugeriu tradução reversa (DeepL ou Linguee)
  para checar o sentido do abstract.

**Considerações Finais**: as conclusões sobre o que os Resultados mostraram.
Os próximos passos registrados no repositório estão na
[seção 9 do levantamento](revisao-do-projeto.md):
validar a captura com fotos reais, publicar o conteúdo das dicas de manejo e
medir o desempenho num celular.

---

## 8. Lista de tarefas

- [ ] Consolidar a Introdução na versão final e apagar Versão 1, Versão 2 e
      Continuação.
- [ ] Manter granulometria antes de textura (comentário do orientador) e
      ligar o triângulo aos grupamentos texturais (seção 2).
- [ ] Decidir como tratar MobileNetV2, TFLite, CI e dicas de manejo
      (seção 4).
- [ ] Completar Material e Métodos com dados, treino, avaliação e captura
      (seção 3).
- [ ] Corrigir citações e referências e unificar a lista (seção 5).
- [ ] Fazer os prints do aplicativo e do código.
- [ ] Escrever Resultados e Discussão (seção 6).
- [ ] Escrever Considerações Finais, Resumo e Palavras-chave (seção 7).
- [ ] Incluir autores e notas de vínculo.
