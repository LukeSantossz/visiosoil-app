# Conferências do TCC

Uma entrada por conferência, a mais recente primeiro. O procedimento está no
[guia de redação](guia-de-redacao.md#2-conferência-obrigatória). Cada entrada
descreve o dia em que foi feita e não é reescrita depois.

## 2026-10-07

### O que foi lido

- **Pasta do TCC**: a raiz tem agora três itens. As pastas `modelo original
  Fatec` e `Versões anteriores` foram criadas hoje e reúnem arquivos que já
  existiam. O `.docx` do artigo na raiz é novo, enviado hoje.
- **Google Doc**: revisão `AHj4eMR7fgcR…`, abas TCC, Introdução, INTRODUÇÃO,
  Material e Métodos, Referências e Dicas - Eloiza. A aba "Revisão - Métodos e
  Resultados" passou a se chamar TCC e tem o artigo inteiro. A aba "Guia 6" não
  existe mais.
- **Comentários**: cinco abertos, de 26 a 28 de setembro, e dois resolvidos.
  Nenhum é posterior a 2026-09-30.
- **Repositório**: `main` em `834a9ab` (2026-10-05), com os pull requests #358,
  #365 e #366 abertos.

### A exportação e a aba

São iguais, salvo uma frase do Resumo: a aba corrigiu "propriedade física é um"
para "propriedade física e um", e a exportação não tem a correção. A aba é a
versão mais recente.

### O que os autores mudaram desde 2026-10-01

- Escreveram o Resumo, com 240 palavras, e as Considerações Finais.
- Retiraram Romanelli (2025) do texto e das referências. Ficam 30 referências,
  e toda citação tem a sua.
- Acrescentaram a distribuição regional dos 86 laboratórios aprovados em
  granulometria e o nome do laboratório do acervo, e renumeraram Material e
  Métodos de 2.1 a 2.5.

### Divergências com as fontes externas

| Trecho | O texto diz | O que a fonte mostra |
| --- | --- | --- |
| Introdução, PAQLF | "cerca de 139 laboratórios de fertilidade [...] participam do [...] PAQLF (Embrapa Solos, 2026b)" | A página do PAQLF diz "cerca de 150 laboratórios de fertilidade". 139 é o número de aprovados em 2026 (Embrapa Solos, 2026a). |
| Resumo | "No Brasil, conforme dados da Embrapa de 2026, 86 laboratórios realizam a análise textural do solo" | 86 são os aprovados em granulometria no PAQLF, que reúne apenas laboratórios que usam o Método Embrapa e aderem ao programa. Não é o total do país. |
| Resumo | "acurácia de 68%" | O valor medido é 68,8% por amostra, na validação cruzada (`docs/ml/e0-verdict.md`), e a seção 3.4 usa 68,8%. |
| 2.3 | O acervo foi rotulado pelo laboratório da Fundação Shunji Nishimura | Os registros do repositório não nomeiam o laboratório (a ADR 0014 diz só que é do próprio projeto). É informação dos autores, não conferida aqui. |

**Confere**: a distribuição regional dos 86 laboratórios aprovados em
granulometria (35 no Centro-Oeste, cerca de 40%; 21 no Sudeste; 12 no Sul; 10 no
Nordeste; 8 no Norte), contada na lista de 2026 da Embrapa Solos. O Resumo está
entre 230 e 250 palavras, e as três palavras-chave não repetem o título.

**Grafia**: "(por hora)", na seção 2.4, é "por ora"; "à partir", na seção 3.4,
é "a partir".

### Divergências com o aplicativo

O texto descreve o aplicativo no commit `64a3333` (2026-10-01). Em `834a9ab`:

| Seção | O texto diz | O `main` mostra | Fonte |
| --- | --- | --- | --- |
| 3.2 | Na primeira abertura, o aplicativo pede as permissões de câmera e de localização. | A abertura não pede nada. A câmera é pedida ao tocar em "Câmera", e a localização quando a foto chega. Antes do pedido, uma linha sob o botão explica para que serve cada permissão. | SPEC 0099, SPEC 0115 |
| 3.2 | Na captura, o aplicativo registra a localização, classifica a imagem e guarda o registro. | Salvar espera a classificação, não a localização: um registro salvo antes de a localização chegar fica sem coordenadas. Depois de salvar, abrem-se os detalhes do registro. Durante a classificação, a tela mostra a etapa em curso ("Lendo a foto...", "Procurando a folha A4...", "Descrevendo a textura..."). | SPEC 0117, SPEC 0132, SPEC 0116 |
| 3.2 | No histórico, tocar em uma análise abre a foto em tela cheia, e dali os detalhes. | Tocar abre os detalhes, e a foto em tela cheia se abre pela própria foto, em "Ampliar foto". | SPEC 0125 |
| 3.2 | Configurações: conta Google, versão, instruções de captura e apagar os dados. | Também excluir a conta, escolher o tema (sistema, claro ou escuro), ligar o alto contraste e enviar o relatório de erros. | SPEC 0113, SPEC 0107, SPEC 0130, SPEC 0110 |
| 3.3 | A estrutura do banco passou por cinco versões. | Passou por sete. A v6 apaga o conteúdo dos registros excluídos, e a v7 guarda a probabilidade de cada classe e a versão do modelo que classificou. | SPEC 0093, SPEC 0097 |
| 3.1 | 1.108 commits e 144 pull requests, com etapas até setembro. | 1.404 commits e 193 pull requests até 2026-10-05. Em outubro entraram as permissões no momento da captura, o protocolo da folha A4 na apresentação, o tema escuro e o alto contraste, ajustes de acessibilidade (rótulos e área de toque, texto em até 200%, redução de movimento), a exclusão da conta, o relatório de erros e a primeira verificação do leitor da folha em fotografias reais. | `git rev-list`, `git log --merges` |
| 3.5 | 89 arquivos e cerca de 597 casos de teste em Dart; 774 funções de teste em Python no modelo. | 114 arquivos e cerca de 844 casos em Dart; 800 funções no modelo e 135 nas recomendações. A integração contínua segue com oito etapas; a inicialização em emulador roda no Android 14, 15 e 16, e a compilação gera também o pacote para a Play Store. | comandos da seção 4 do guia, SPEC 0102, SPEC 0103 |
| 2.4 e 3.4 | O leitor da folha foi testado só com imagens sintéticas; falta medi-lo em fotografias reais. | Houve uma primeira verificação em 2026-10-05, com 31 fotografias de uma sessão. Depois da SPEC 0140, o leitor encontrou a folha em 24 e recusou as outras 7 pela causa certa; antes dela, não encontrava nenhuma. Nenhuma foi classificada: o disco de solo media de 46 a 51 mm, abaixo dos 58,5 mm que os nove recortes exigem e dos 8 a 10 cm do protocolo. O estudo com discos menores manteve o mínimo de nove recortes. | `docs/ml/sheet-reader-real-photographs.md`, SPEC 0140, `docs/ml/small-disc-study.md` |

**Sem mudança**: o modelo (`assets/models/spec.json` é o mesmo), a acurácia de
68,8% contra 27,3% do controle, os tempos da Tabela 2, as sete rotas, as
tecnologias do Quadro 1 e as oito etapas da integração contínua.

**Em pull request aberto, ainda não feito**: #358 (guia de captura antes da
primeira abertura da câmera), #365 (estudo de nove recortes em discos pequenos)
e #366 (leitor da folha com gradiente de luz).

### Comentários abertos e a aba TCC

- "Destacar isso [...] Quantos laboratórios de solos credenciados há no Brasil?
  onde estão localizados": respondido pelo parágrafo do PAQLF, com a ressalva
  sobre os 139 da tabela acima.
- "Essa informação deve estar antes de vocês explicarem o que é a textura do
  solo": atendido; na aba TCC a granulometria vem antes da textura.
- "o que é simples e intuitiva?": a expressão não aparece mais na aba TCC.
- "foi" e "Esse parágrafo está mais próximo de uma discussão do que de uma
  introdução": a API não devolve o trecho em que estão ancorados, então não foi
  possível saber se ainda se aplicam. Ficam para os autores conferirem no
  documento.
