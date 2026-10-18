# Protocolo de Captura

Como tirar uma foto de solo que o VisioSoil consegue classificar. Siga todos os
passos. O app lê a escala pela folha A4, e uma foto cuja folha ou cujo solo ele
não consegue ler é recusada com o motivo, nunca estimada
([ADR 0017](adr/0017-scale-is-read-by-a-classical-operator-on-a-known-circle.md)).
Ele não confere todos os passos: a secagem e o preparo do solo, a luz, o foco e o
tamanho máximo do círculo ficam por sua conta, e uma foto que falhe num deles
ainda pode ser lida.

Versão em pt-BR de [`capture-protocol.md`](capture-protocol.md), que é a fonte.
Os dois documentos trazem os mesmos passos e limites.

**Nenhuma foto real foi classificada ainda.** O código aplica dois dos limites
abaixo, 2299 px e 63 mm. Eles dizem o que o app vai ler, não quão precisa é a
leitura em fotos de campo
([`docs/ml/sheet-reader-real-photographs.md`](ml/sheet-reader-real-photographs.md)).

## 1. O que você precisa

- **Uma folha A4 branca e lisa** (210 × 297 mm): plana, sem dobras, sem nada
  escrito ou impresso.
- **Uma superfície bem mais escura que o papel**: madeira escura, uma placa ou um
  pano escuro. Mesa clara é o motivo mais comum de a folha não ser encontrada.
- **Solo seco ao ar e peneirado**, destorroado, sem torrões, raízes ou pedras. É o
  único material com que o modelo foi treinado. Solo úmido de campo pode ser
  fotografado, mas a leitura fica fora do que o modelo conhece
  ([ADR 0014](adr/0014-petri-dish-capture-protocol-and-the-unresolved-scale-reference.md)).
- **A câmera do celular na maior resolução.**

## 2. Prepare a amostra

1. Coloque a folha plana sobre a superfície escura. Não coloque mais nada sobre
   ela: nem outra folha, etiqueta, moeda ou recipiente.
2. Espalhe o solo direto no papel em **um círculo uniforme de 8 a 10 cm**, no
   meio da folha. O círculo precisa ter **pelo menos 63 mm**, senão o app o
   recusa como pequeno demais.
3. Deixe a camada uniforme e sem falhas, sem papel aparecendo dentro do círculo.

## 3. Enquadre e fotografe

1. Segure o celular **logo acima** da folha, paralelo a ela.
2. Mantenha **a folha inteira no quadro**, com os quatro cantos visíveis e uma
   margem da superfície em todos os lados.
3. Gire o celular para que **o lado maior da folha fique no lado maior do
   quadro**, e aproxime o quanto a margem permitir. O lado de 297 mm da folha
   precisa ocupar **pelo menos 2299 px** na foto. Numa câmera de 12 MP
   (4000 × 3000), isso é pelo menos 57,5 % do lado maior do quadro. Não use zoom
   digital: aproxime o celular.
4. Use **luz difusa**: sombra, céu nublado ou mesmo a luz do ambiente. **Sem
   flash**, sem mancha de sol direto e sem sombra sobre a folha, nem a do próprio
   celular.
5. Fique parado e deixe a câmera focar no solo.

## 4. Checklist antes da foto

- [ ] Folha A4 branca e lisa, plana, sobre uma superfície mais escura
- [ ] Nada sobre a folha além do solo
- [ ] Solo seco e peneirado, num círculo uniforme de 8 a 10 cm, centralizado
- [ ] Celular acima da folha, paralelo a ela, na maior resolução
- [ ] Folha inteira no quadro, quatro cantos, margem em volta, lados maiores alinhados
- [ ] Luz difusa, sem flash, sem sombra na folha

## 5. Quando o app recusa a foto

A prévia da captura mostra o motivo numa etiqueta. Cada uma abaixo pede outra
foto; mude o que a última coluna diz antes de tirá-la.

| O app mostra | Causa | O que mudar |
|---|---|---|
| Folha A4 não encontrada · tire outra foto | `sheetNotFound` | Use uma superfície mais escura e mantenha a folha inteira no quadro. A folha não pode ficar minúscula no quadro nem ocupar quase todo ele. |
| Folha cortada no quadro · tire outra foto | `sheetCropped` | Afaste o celular até os quatro cantos aparecerem, com margem. |
| Foto sem detalhe suficiente · tire outra foto | `photographTooCoarse` | A folha ocupa menos de 2299 px. Ponha a câmera na maior resolução, alinhe os lados maiores e aproxime. |
| Pouco solo na folha · espalhe um círculo de 8 a 10 cm e tire outra foto | `soilRegionTooSmall` | Espalhe mais solo, num círculo de 8 a 10 cm. |
| Amostra fora da área lida · tire outra foto | `soilRegionOutsideFrame` | Centralize o círculo de solo na folha, longe das bordas. |
| Foto ilegível · tire outra foto | `imageMissing`, `imageUndecodable` | Tire a foto de novo. |
| Não foi possível analisar esta foto · tire outra foto | `outputInvalid` | Tire a foto de novo, seguindo todos os passos acima. |

Uma etiqueta que diz *tocar para tentar de novo* não é sobre a foto: toque nela
para analisar a mesma foto outra vez. *Análise indisponível nesta versão*
significa que a versão instalada não tem um classificador utilizável, e nenhuma
foto resolve isso.

## De onde vêm os limites

- Os três passos que o app ensina: `lib/core/constants/capture_protocol.dart`, e
  o protocolo decidido em 2026-09-29 na emenda da ADR 0017.
- **2299 px**: os 297 mm da folha divididos pela escala canônica de
  0,1292 mm/px do contrato (`assets/models/spec.json`). Uma foto mais grosseira
  teria de ser ampliada, inventando grãos que nunca foram fotografados
  (`lib/core/services/descriptors/patch_grid.dart`).
- **63 mm**: os nove recortes que a ADR 0018 exige, de 20,7 mm cada e espaçados
  em meio recorte, precisam de um disco de 58,5 mm, e o leitor mede esse disco
  2 mm para dentro da borda do solo (`soilMarginMm` em
  `lib/core/services/descriptors/a4_sheet.dart`). O círculo de 8 a 10 cm
  reproduz a placa de 90 mm com que o modelo foi treinado.
- **A superfície e o enquadramento**: os limites de contraste e de fração do
  quadro do leitor da folha em `a4_sheet.dart`, e as falhas que a sessão de
  2026-10-05 mostrou.

`test/standards/capture_protocol_doc_test.dart` recalcula os dois números a
partir do contrato e falha se este documento deixar de trazê-los (SPEC 0164).
