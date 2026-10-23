# VisioSoil · Redesign v11 · SPEC para implementação em Flutter

Destinatário: Dev Flutter. Repo: `LukeSantossz/visiosoil-app`. Referência visual: `telas/*.png` (390×844 @2x) e o protótipo em `../app-completo-v11/index.html`.
Leitura do repo feita em 22/10/2026 (somente leitura). Os nomes de arquivo abaixo seguem a estrutura atual de `lib/core/theme`, `lib/core/widgets` e `lib/core/features/*`.

> Regra de ouro: **o modelo devolve só a classe textural e a confiança.** Não há frações, top 3 nem talhão (detalhes na §11).

---

## 0. Divergências entre o repo e o redesign (resolver primeiro)

| Tema | Hoje no repo | Redesign v11 (aprovado) | Ação |
|---|---|---|---|
| Faixas de confiança | `ConfidenceLevel`: alta ≥ 0.80, moderada 0.60–0.79, baixa < 0.60 | **alta ≥ 75, média 50–74, baixa < 50** | Trocar `highThreshold=0.75` e `moderateThreshold=0.50`. Mudar o rótulo "Moderada" para "Média". Ajustar os testes |
| Haptics | `AppHaptics`: `selection`, `confirm`(light), `result`(medium). O comentário diz "sem tier heavy" (fica superado) | Acrescenta `heavyImpact` ×2 **só** na foto ruim, além de excluir, desfazer e a sequência de vincular conta | Estender `AppHaptics` (§7) com `blocked()` (heavy ×2) e atualizar o comentário. Respeitar o toggle Vibração |
| Curvas | `AppMotion.standard=Cubic(.2,0,0,1)`, `emphasized=Cubic(.3,0,.1,1)`, `out` | 5 curvas M3 (§6) | Trocar `emphasized` para `Cubic(.2,0,0,1)` (M3) e acrescentar as outras 4. As animações existentes passam a usar a curva nova |
| Modo Sol | Existem `lightHighContrast`/`darkHighContrast` (SPEC 0130), só com bordas | Paleta própria, tipografia maior e alvos de 56 dp | Criar a `AppPalette.sun` e uma extensão de densidade (§1.4) |
| `class_score.dart` | Lista de scores por classe | A UI mostra **somente** a classe vencedora | Não expor a lista na UI. Pode continuar no modelo de dados |

---

## 1. Tokens

### 1.1 Cores (as hex são as do mock; os nomes seguem `AppPalette`)

| Token AppPalette | CSS mock | Claro | Escuro | Modo Sol |
|---|---|---|---|---|
| background | --bg | #F8FAF5 | #121411 | #FFFFFF |
| surface | --surf | #FCFDF8 | #1E201D (valor do repo; o mock usava #1A1C19) | #FFFFFF |
| surfaceContainer | --surf2 | #EEF1E9 | #232521 | #F2F2F2 |
| surfaceContainerHigh | --surf3 | #E0E4DA | #2F312D | #E6E6E6 |
| onSurface / onBackground | --on | #1A1C19 | #E2E3DD | #000000 |
| onSurfaceVariant | --on2 | #43483E | #C3C8BB | #000000 |
| textTertiary (ext) | --on3 | #5E6359 | #A3A89C | #1F1F1F |
| outlineVariant | --line | #C3C8BB | #43483E | #000000 |
| divider (ext) | --line2 | #E0E4DA | #2F312D | #000000 |
| outline | --outline | #73796D | #8D9287 | #000000 |
| primary (fill) | --pri | #4A7C59 | #B1D1B9 | #1F4D2E |
| primaryText (ext: texto/ícone verde sobre o fundo) | --priT | #3B6A49 | #B1D1B9 | #1F4D2E |
| onPrimary | --onpri | #FFFFFF | #1B3625 | #FFFFFF |
| primaryContainer | --pc | #CCE8D4 | #324D3B | #FFFFFF (+ borda 2 px preta) |
| onPrimaryContainer | --onpc | #0D2818 | #CBEAD2 | #000000 |
| secondary | --sec | #8B6F47 | #E4C192 | #4A3417 |
| secondaryContainer | --sc | #F5E6D3 | #5A431E | #FFFFFF |
| onSecondaryContainer | --onsc | #2D1F0E | #FFDDB1 | #000000 |
| warning (ext) | --warn | #6D4C1D | #FEB968 | #4A3417 |
| warningContainer (ext) | --wc | #FBEBD2 | #604012 | #FFFFFF |
| error | --err | #BA1A1A | #FFB4AB | #8C0009 |
| errorContainer | --ec | #FFDAD6 | #93000A | #FFFFFF |
| onErrorContainer | --onec | #410002 | #FFDAD6 | #8C0009 |
| selected (ext: linha/chip selecionado) | --sel | #E4F0D9 | #243517 | #FFFFFF |
| destrutivo (botão Excluir no swipe) | — | #B3261E / texto #FFF | igual | igual (contraste 6,5:1) |
| Anel de foco | — | primary 2 px | primary 2 px | outline 3 px #000 + halo 6 px #FFD400 |

Âmbar do aviso "foto ruim": fundo `warningContainer`, texto `warning`, contorno âmbar nos chips que falharam (`warning`).
Fundo decorativo (glow), só nos temas claro e escuro: primary a 13–16% (claro) / #B1D1B9 a 10% (escuro). No Modo Sol, nenhum.

### 1.2 Tipografia: Inter
- Fonte: `Inter` (asset ou `google_fonts`), com as features `cv11` e `ss01` (`FontFeature('cv11')`, `FontFeature('ss01')`). Números tabulares (`tnum`) em %, horários e estatísticas.
- Base claro/escuro (Modo Sol entre parênteses):

| Papel | Uso | Tamanho/altura | Peso |
|---|---|---|---|
| displaySmall | % da confiança no resultado | 40/44 | 650 |
| headlineMedium (`t-title`) | títulos de tela e nome da classe | 28/36, tracking −0,025em | 650 |
| titleMedium | título de card, nome na linha (`.k`) | 16/22 (17/24) | 600 |
| bodyLarge (`t-body`) | parágrafos | 16/24 (18/27) | 400 |
| bodyMedium (`t-sm`) | texto de apoio | 14/20 (16/24) | 400 |
| labelLarge | botões | 15–16 (17) | 600 |
| labelMedium | barra inferior | 12 (14, 600) | 500/700 sel. |
| bodySmall (`t-xs`) | metadados e legendas | 12/16 (14/20, cor #000) | 400 |
| pill | badge de status | 12 (14), altura 24 (28) | 600 |

### 1.3 Espaçamento (manter `AppSpacing`)
xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32 · xxxl 48. Margem lateral das telas: 20 (mock). Usar `lg`+4 = 20 ou criar `AppSpacing.page = 20`. Gap entre seções: 24. Lista: linha com `min-height` de 56 (64 no Modo Sol), padding vertical 8 e gap 12.

### 1.4 Raios, alvos e bordas
- Raios: mock r1 4 · r2 8 · r3 12 · r4 16. Repo: sm 8 · md 12 · lg 16 · xl 24 · pill 999. Acrescentar `AppRadius.xs = 4` e usar `6` no badge (pill de status).
- Botões: pill (999). Cards: 16. Sheets: 24 no topo. Miniatura: 12. Câmera/moldura: 16.
- Densidade (criar `ThemeExtension<AppDensity>`): `tap` 48 (claro/escuro) / 56 (Sol); `buttonHeight` 52 / 56; `borderWidth` 1 / 2; `navHeight` 80 / 88; `shutter` 72 / 80.

### 1.5 Elevação
Plana por padrão. Usar a sombra do `AppPalette` existente: `shadowCard` (cards, 0 1 2), `shadowControl` (chips e controles), `shadowElevated` (sheets, snackbar, menus). Escuro: sem sombra; a elevação vem pelo tom (surface → surfaceContainer). Modo Sol: **sem sombra**, só borda 2 px preta.

---

## 2. ThemeData e ColorScheme (M3)

Estender `AppTheme._build(AppPalette p)` (já é `useMaterial3: true`):
- `ColorScheme`: primary, onPrimary, primaryContainer, onPrimaryContainer, secondary…, error…, `surface`=p.surface, `onSurface`, `onSurfaceVariant`, `outline`, `outlineVariant`, `surfaceContainerLowest`=background, `surfaceContainer`=--surf2, `surfaceContainerHigh`=--surf3, `inverseSurface`, `onInverseSurface`, `inversePrimary`. `scaffoldBackgroundColor = p.background`.
- Tokens fora do M3 (`primaryText`, `textTertiary`, `divider`, `warning*`, `selected`, `destructive`) ficam em `AppPalette` (já é `ThemeExtension`).
- Acrescentar `static ThemeData get sun => _build(AppPalette.sun)`, com:
  - `textTheme` escalado (§1.2);
  - `materialTapTargetSize: padded`;
  - `visualDensity: standard`;
  - `ButtonStyle.minimumSize: Size(64,56)`;
  - `side` 2 px preto em Outlined, cards, chips e Switch (track outline);
  - `NavigationBarTheme`: height 88, indicador preto e ícone branco quando selecionado.
- Seleção do tema: `appearance_provider` passa a ter 3 valores (claro | escuro | sol). O padrão inicial segue o sistema (claro/escuro); o Modo Sol só liga manualmente. O Modo Sol força o tema claro de alto contraste e ignora o `platformBrightness`.
- `SnackBar` flutuante, raio 8, `inverseSurface`. `NavigationBar` com `indicatorColor = primaryContainer` (já existe).

---

## 3. Inventário de telas

Convenção: cada tela tem os estados **ok · vazio · carregando · erro · offline** quando se aplica. "Foto ruim" só existe na câmera. Confiança: **alta ≥ 75** (primaryContainer, ícone `verified`, rótulo "Confiança alta"), **média 50–74** (warningContainer, `info`, "Confiança média"), **baixa < 50** (errorContainer, `warning`, "Confiança baixa"). O mock só tem PNG de alta. Média e baixa seguem a mesma tela, com as cores e o texto da tabela da §3.14. Todo texto do mock marcado "Exemplo/Simulação" e os dados (Ana Ribeiro, Rio Verde) são fictícios.

### 3.1 Boot "Peneira": `splash_screen.dart` · `telas/01-boot-peneira.png`
- Layout: fundo verde (#1B3625 escuro / #1F4D2E Sol / primary claro). Ao centro, a malha da peneira com grãos caindo e assentando. Logo `visio_soil_logo.dart` e abaixo "VisioSoil" + "Análise de textura do solo". Botão de texto "Pular" no canto inferior.
- Motion (§6): ≈1,6 s no total, e depois Hero do logo até o app bar da Home. Reduzir movimento: logo estático e fade de 150 ms.
- Só aparece a frio. Em retorno quente, nenhum.

### 3.2 Onboarding (4 passos): `onboarding_screen.dart`
Cabeçalho comum: "Passo N de 4" + indicador de passos (4 traços). Ilustração no topo (até 330 px no Sol, onde fica branca com borda inferior de 2 px).
1. **Login Google opcional** (`02`, `03` carregando, `04`/`37` vinculado)
   - Título: "Vincular conta para salvar e sincronizar suas análises"
   - Texto: "Guardamos suas análises, fotos e coleção na sua conta Google. Sem conta, tudo fica só neste aparelho."
   - Botões: [Continuar com o Google] (botão de marca, §9) · [Agora não] (texto)
   - Carregando: o botão vira "Vinculando sua conta…" com spinner e desabilitado. "Agora não" continua ativo.
   - Vinculado: título "Conta vinculada", texto "Suas análises vão sincronizar sozinhas quando houver internet.", card da conta (avatar com iniciais "AR", nome, e-mail) e [Continuar]. Haptic medium e light 90 ms depois. Anel verde no avatar.
   - Erro (sem PNG): snackbar "Não foi possível vincular. Tente de novo ou continue sem conta." Os botões voltam ao estado inicial.
   - Offline (sem PNG): o botão Google fica desabilitado, com a legenda "Sem conexão. Você pode vincular depois em Perfil."
2. **Foto da amostra** (`05`): "Fotografe a amostra de solo" / "Destorroe uma porção da camada de 0–20 cm e enquadre na moldura. O app checa luz, foco e distância antes de liberar a foto." · [Continuar] · [Pular]
3. **Classe estimada** (`06`): ilustração do triângulo (Argila/Areia/Silte) · "Veja a classe textural estimada" / "O resultado mostra a classe textural estimada pelo modelo e a confiança dela, em palavras e em percentual." · [Continuar] · [Pular]
4. **Permissão de câmera** (`07`): "Permita o acesso à câmera" / "Usamos a câmera para fotografar o solo. Funciona sem internet; as análises sincronizam quando houver sinal." Lista com:
   - "Câmera, para fotografar a amostra. As fotos ficam no aparelho."
   - "Localização aproximada, opcional, para registrar onde a amostra foi coletada."
   
   Botões: [Permitir câmera] · [Agora não]. Negada: reaproveitar `camera_permission_denied_view.dart`.

### 3.3 Home: `home_screen.dart` · `08`, `09` vazio, `25` Sol, `27` escuro
- App bar: "Início". Card herói `hero_capture_card.dart`: [Analisar solo] (CTA primário, ícone câmera).
- "Esta semana": `stats_grid.dart` com 3 células: "6 análises" · "7/12 coleção" · "82% última confiança" (vazio: "0", "0/12", "— última classe").
- "Recentes" + link "Ver todas": até 5 linhas (miniatura, classe, "hoje 10:42", "82%", status pill **Enviada / Pendente / Erro**). Linha com erro: "—" no lugar do %.
- Vazio (`09`): "Suas análises aparecem aqui." / "Fotografe a camada de 0–20 cm, na sombra e sem palha."
- Carregando: skeleton (3 células + 3 linhas) com shimmer. Reduzir movimento: sem shimmer.
- Erro: `home_data_error.dart` com "Não foi possível carregar suas análises." [Tentar de novo].
- Offline: a Home funciona (é local). Mostrar só o pill Pendente.
- NavigationBar: Início · Histórico · Dicas · Perfil.

### 3.4 Câmera guiada: `guided_camera_screen.dart` · `10`, `11` pronta, `12` foto ruim, `28` obturador
- Barra superior: voltar + "Nova análise". Moldura central (`capture_guide_overlay.dart`) com dica dinâmica no topo, por exemplo "Aproxime até a amostra preencher a moldura" e "Procure sombra uniforme ou mais luz".
- 3 chips de qualidade (`live_reading`): **Luz** (Baixa/Boa · "180 lx"), **Foco** (Desfocado/Ajustando…/Nítido), **Distância** ("48 cm", alvo 18–25 cm). Cada chip tem 3 estados: falha, ajustando, ok.
- Rodapé: legenda "Captura liberada quando os 3 itens estiverem ok", botão galeria (56 no Sol) e obturador (72/80).
- **Pronta** (`11`/`28`): todos os chips ok, o obturador habilita e entra o anel verde. Toque: scale .86 + flash branco 55% (sem flash no Sol) + mediumImpact.
- **Foto ruim** (`12`): toque com algum chip falhando. O botão treme (300 ms), entra o aviso âmbar fixo acima dos chips, por 3,8 s, com o texto "Ainda não dá para fotografar" e o detalhe gerado a partir dos chips que falharam, por exemplo "Pouca luz, fora de foco, longe demais. Procure sombra clara, aproxime até a amostra preencher a moldura e segure firme." Os chips que falharam ganham contorno âmbar e toca heavyImpact ×2. O detalhe é composto por partes: luz → "Pouca luz" / "Procure sombra clara"; foco → "fora de foco" / "segure firme"; distância → "longe demais"/"perto demais" / "aproxime até a amostra preencher a moldura".
- Sem permissão: `camera_permission_denied_view.dart`. Erro de câmera: "Não foi possível abrir a câmera." [Tentar de novo].
- Remover da UI o rótulo "Simulação" e o indicador de haptic (só existem no mock).

### 3.5 Processando: dentro do fluxo de resultado · `13`, `29`, `30`, `31`, `38` Sol
- App bar "Resultado". Triângulo textural (Argila/Areia/Silte) grande com as partículas caindo (§6.3). No fim, a região da classe preenche e mostra o nome ("Franco-argilosa").
- Textos: "Analisando a amostra" · "Comparando com o modelo no aparelho" · "cerca de 5 s" + barra de progresso indeterminada fina.
- Legenda fixa: "Diagrama ilustrativo, com regiões aproximadas (USDA/SBCS). Mostra a classe, não a posição da amostra."
- Sol (`38`): sem partículas. A região preenche em #1F4D2E e só há troca de estado.
- Timeout de mais de 15 s: vai para o erro do resultado.

### 3.6 Resultado: `details_screen.dart`/`classification_header.dart` · `14`, `32` entrada, `33` salvo, `26` Sol, `15` erro
- Topo: "22/10/2026 · 10:42" · overline "Classe textural (triângulo USDA)" · **nome da classe** (headline) · badge "Confiança alta" + "82%" (display, tnum) + barra de confiança.
- Abas (segmentado): **Visão geral · Manejo · Detalhes**.
- Visão geral:
  - "O modelo estima a classe textural pela foto. A confiança indica o quanto ele está seguro dessa classe."
  - Card "No triângulo textural": região destacada, com "A região está destacada." e a legenda do diagrama.
  - Card "Sobre a classe" · "Referência geral": "Solos franco-argilosos costumam ter 27–40% de argila e 20–45% de areia, segundo o triângulo USDA. Retêm bem água e nutrientes e compactam com facilidade quando úmidos." + nota "Faixa típica da classe, não medição desta amostra." (texto estático por classe, não é saída do modelo).
  - Card "Amostra": "Rio Verde, GO · −17,79, −50,92 · Camada 0–20 cm · solo seco ao ar".
  - Aviso: "Estimativa por imagem. Para laudo, confirme com análise granulométrica em laboratório."
- Rodapé: [Corrigir] (outlined, abre `labels_dialog.dart`) · [Dicas de manejo] (primário). Ação "Salvar" (bookmark) no app bar.
- Salvo (`33`): o bookmark preenche, faz pop 1.28, snackbar "Salvo no histórico" e lightImpact.
- Erro (`15`): "Não deu para classificar" / "A foto ficou escura e com reflexo. Refaça na sombra, com a amostra preenchendo a moldura." · [Fotografar de novo] · [Ver dicas de captura]. O motivo vem do `image_quality_report`. Variações: "A foto ficou desfocada…" / "A amostra ficou pequena na moldura…".
- Offline: o resultado é local e funciona. A seção Manejo mostra "Dicas atualizadas precisam de internet. Mostrando as últimas salvas."

### 3.7 Histórico: `history_screen.dart` · `16`, `17` vazio, `18` offline, `34` swipe
- App bar "Histórico" + buscar + filtros (`history_filter_bar.dart`). Segmentado: **Análises · Coleção**.
- Resumo em 3 células: "25 análises" · "6 nesta semana" · "7/12 classes".
- Lista agrupada por data ("Hoje", "Ontem", "18 out"). Cada linha: miniatura de 56 com raio 12, classe, "10:42 · 82% de confiança", chevron ou pill "Pendente".
- **Swipe para excluir** (`34`): ao arrastar para a esquerda e passar de 50 px, a linha recua 12 px e o botão vermelho "Excluir" (largura 104, ícone lixeira) entra pela direita. **A miniatura e o texto continuam visíveis.** Tocar em Excluir: o botão se expande até a largura toda, a linha sai e a altura colapsa. Snackbar "Análise excluída" [Desfazer] (5 s). Implementar com `Dismissible`/`Slidable` custom, sem confirmação modal (o undo substitui). Acessibilidade: ação de semântica "Excluir" (`CustomSemanticsAction`), já que o swipe não é acessível.
- Vazio (`17`): "Nenhuma análise ainda" / "Suas análises aparecem aqui, agrupadas por data, mesmo sem internet." [Fazer primeira análise].
- Offline (`18`): banner "Sem conexão" / "1 análise aguarda envio. Tudo continua salvo neste aparelho." (plural: "N análises aguardam envio.").
- Carregando: "Carregando histórico" (skeleton). Erro: "Não foi possível carregar o histórico." [Tentar de novo].
- Coleção: grade das 12 classes USDA (`history_grid.dart`). As classes conquistadas ficam coloridas com `soil_texture_colors.dart`; as outras, em contorno.

### 3.8 Detalhe da análise: `details_screen.dart` · `19`
Foto da amostra no topo (Hero a partir da miniatura). Lista de pares rótulo/valor:
- "Classe estimada · Franco-argilosa"
- "Confiança · Alta · 82%"
- "Data e hora · 22/10/2026 · 10:42"
- "Coordenadas · −17,79 · −50,92"
- "Captura · 1.480 lx · 21 cm · nítido"
- "Modelo · no aparelho · v0.3"

Ações: compartilhar e excluir (`confirm_destructive_action.dart`).

### 3.9 Dicas de manejo: `management_tips_section.dart` · `20`
- Cabeçalho "Dicas de manejo", contexto "Franco-argilosa · Soja · safra 26/27 · 4 dicas" e aviso de exemplo (no app real: fonte e citação reais).
- Timeline por fase: "Antes do plantio · Agora", "Semeadura · Próximo", "Ciclo da cultura". Card da dica: título, texto e fonte.
- Carregando: "Carregando dicas". Offline: as últimas em cache + aviso. Erro: "Não foi possível carregar as dicas." [Tentar de novo]. Vazio: "Sem dicas para esta classe ainda."

### 3.10 Perfil (4ª aba da barra): `21` anônimo, `22` vinculado (criar `profile_screen.dart`; hoje não existe)
- Anônimo:
  - card "Sem conta vinculada · Dados só neste aparelho";
  - "Vincule uma conta para salvar e sincronizar suas análises. Se trocar ou perder o aparelho, elas não se perdem.";
  - "25 análises e 7 classes guardadas neste aparelho";
  - [Continuar com o Google].
- Vinculado: avatar, nome, e-mail, "Sincronizado hoje, 10:45" [Sincronizar].
- "Neste aparelho": 25 análises · 7/12 coleção · 23 enviadas (anônimo: "só no aparelho").
- Links: "Configurações · Tema, câmera, dados e acessibilidade" · "Como fotografar a amostra · Luz, distância e preparo".
- Vinculado: [Sair da conta] + "As análises continuam neste aparelho".

### 3.11 Configurações: `settings_screen.dart` · `23`, `24` exportar, `35`/`36` vibração
Seções e itens (o copy é exato):
- **Conta:**
  - anônimo: "Não vinculada · dados só neste aparelho";
  - vinculado: "Conta Google · e-mail".
- **Preferências:**
  - Tema (segmentado Claro | Escuro | Modo Sol), legenda "Alto contraste e letras maiores para o campo";
  - **Vibração** (switch, ligado por padrão, logo abaixo do Modo Sol) "Toques sutis ao capturar, salvar e concluir";
  - Unidades "Distância em cm";
  - Idioma "Português (Brasil)".
- **Câmera e análise:**
  - Guia de enquadramento "Moldura e checagem de luz, foco e distância";
  - Salvar fotos na galeria;
  - Registrar localização "Aproximada, opcional".
- **Dados e sincronização:**
  - Backup na conta: "Requer conta vinculada" (desabilitado) / "Último: hoje, 10:45" [Fazer agora];
  - Sincronizar só no Wi-Fi;
  - Exportar análises "Planilha CSV";
  - Limpar dados do aparelho "Apaga análises e fotos locais" (destrutivo, com confirmação).
- **Acessibilidade:**
  - Reduzir movimento "Troca animações por transições curtas" (padrão: segue o sistema);
  - Tamanho do texto (segmentado Padrão | Grande).
- **Sobre e ajuda:** Como fotografar a amostra · Privacidade e dados · Enviar comentário · Versão.

Sheet Exportar (`24`):
- "25 análises em uma planilha CSV.";
- checkboxes "Classe e confiança" (fixo), "Data e hora", "Localização aproximada", "Incluir fotos (arquivo .zip)";
- [Exportar].

Usar `share_service`.

### 3.12 Captura guia: `capture_guide_screen.dart`
Mantém o conteúdo atual, com tokens novos (fora do escopo do mock).

### 3.13 Snackbars e banners globais
"Salvo no histórico" · "Análise excluída" [Desfazer] · "Sem conexão" (banner) · erro de rede: só snackbar, sem haptic.

### 3.14 Tabela de confiança (fonte única: `ConfidenceLevel`)
| Nível | Faixa | Rótulo | Container | Ícone | Texto de apoio | Haptic de entrada |
|---|---|---|---|---|---|---|
| alta | ≥ 75% | Confiança alta | primaryContainer | verified | — | mediumImpact |
| média | 50–74% | Confiança média | warningContainer | info_outline | "Resultado provável. Se puder, refaça a foto para confirmar." | mediumImpact |
| baixa | < 50% | Confiança baixa | errorContainer | warning_amber | "O modelo não está seguro. Refaça a foto na sombra, com a amostra preenchendo a moldura." + [Fotografar de novo] | lightImpact |

Sempre mostrar o rótulo **e** o percentual (nunca só a cor).

---

## 4. Componentes reutilizáveis (`lib/core/widgets/`)

| Componente | Props | Estados |
|---|---|---|
| `VisioButton` (existe) | `label`, `icon?`, `variant` (primary/outlined/text/destructive), `onPressed?`, `loading` | default, pressed (scale .97, `press_scale.dart`), disabled, loading (spinner + label alternativo) |
| `GoogleSignInButton` | `onPressed`, `loading`, `label` ("Continuar com o Google") | default, pressed, loading, disabled (offline). Seguir a §9 |
| `VisioAppBar` (existe) | `title`, `leading?`, `actions` | — |
| `StatCell` / `StatsRow` | `value`, `label`, `semanticLabel` | normal, skeleton |
| `AnalysisTile` | `record`, `onTap`, `onDelete?`, `dense` | normal, pendente, erro, skeleton, swipe-revelado, excluindo |
| `SwipeToDelete` | `child`, `onDelete`, `onUndo`, `threshold=50` | fechado, revelado, saindo |
| `SoilThumb` | `image`, `size` (56), `heroTag` | carregando, ok, sem imagem (textura por classe) |
| `StatusPill` | `status` (enviada/pendente/erro) | 3 cores. Sol: branco com borda preta |
| `ConfidenceBadge` | `score` (0–1) → `ConfidenceLevel` | alta/média/baixa; `compact` (só %) |
| `ConfidenceBar` | `score`, `animate` | preenche 600 ms |
| `TextureTriangle` | `highlightClass`, `mode` (estático/processando), `onSettled` | vazio, partículas, assentado, destacado |
| `QualityChip` | `kind` (luz/foco/distância), `value`, `status` | falha (âmbar no aviso), ajustando, ok |
| `ShutterButton` | `enabled`, `onCapture`, `onBlocked` | desabilitado, pronto (anel), pressionado, shake |
| `CaptureAlert` | `failures: Set<QualityKind>` | entra / visível 3,8 s / sai |
| `SegmentedControl` | `options`, `value`, `onChanged` | indicador desliza 250 ms |
| `SettingsSwitchTile` | `title`, `subtitle`, `value`, `onChanged`, `haptic` | on/off/disabled, mola do thumb |
| `EmptyState` / `ErrorState` / `LoadingIndicator` (existem) | `icon`, `title`, `message`, `action?` | — |
| `OfflineBanner` | `pendingCount` | singular/plural |
| `AccountCard` | `account?` | anônimo, vinculado, vinculando |
| `StepIndicator` | `total=4`, `current` | — |
| `TipCard` / `TipTimeline` | `phase`, `title`, `body`, `source` | normal, skeleton |

---

## 5. Princípios de layout
- A grade é uma coluna única com margem de 20 e largura máxima de conteúdo de 560 (tablet, §10).
- Ícones Lucide (`lucide_icons_flutter`, ou exportar os SVG usados), com stroke de 1,75 (2,25 no Sol). O logo vem de `visio_soil_logo.dart` (fonte: `logo/visiosoil-logo.svg`).
- Nada de gradiente chamativo, glow forte ou emoji. Um CTA primário por tela.

## 6. Motion

### 6.1 Tokens (acrescentar em `AppMotion`)
```dart
static const emphasized = Cubic(.2, 0, 0, 1);          // M3 emphasized (substitui o .3,0,.1,1 atual)
static const emphasizedDecelerate = Cubic(.05, .7, .1, 1);
static const emphasizedAccelerate = Cubic(.3, 0, .8, .15);
static const standardDecelerate = Cubic(0, 0, 0, 1);
static const standardAccelerate = Cubic(.3, 0, 1, 1);
// durações: instant 90 · fast 140 (mock 120) · base 220 (mock 200–250) · slow 380 · reveal 640
```

### 6.2 Boot Peneira (≈1,6 s)
1. A malha entra com fade e scale .96→1 (250 ms, emphasizedDecelerate).
2. Grãos (CustomPainter) caem pela malha com defasagem de 20 ms e assentam (760 ms, emphasizedDecelerate).
3. O logo e o nome sobem 8 px com fade (250 ms, standardDecelerate).
4. Em 1,2 s, Hero do logo até a Home.

"Pular" encerra na hora. Reduzir movimento: só o logo, fade de 150 ms.

### 6.3 Partículas do processamento (CustomPainter)
- 26 partículas (círculos e polígonos irregulares de 2–4 px na cor da textura da classe; Sol: não renderiza).
- Cada uma vai de y aleatório acima do triângulo até um ponto aleatório **dentro do polígono da classe** (rejection sampling), com dispersão em x.
- 760 ms emphasizedDecelerate cada, defasagem de 28 ms, janela de 1,15 s a 1,9 s.
- Em 2,1 s: lightImpact, pulso de 4% na região (360 ms) e saída das partículas (280 ms standardAccelerate).
- Implementação: um `AnimationController` de 2,4 s e um `CustomPainter` que lê `controller.value` e calcula o progresso de cada partícula com `Interval`. Pré-gerar as posições com `Random(seed)`. Envolver em `RepaintBoundary`. Nada de widget por partícula.

### 6.4 Demais transições
- Rotas: shared axis X (push 300 ms emphasized) e fade-through nas abas da barra.
- Hero: miniatura → foto do detalhe (tag `record.id`); logo boot → Home.
- Entrada do resultado: blocos sobem 8 px em cascata (250 ms, +30 ms/bloco); a barra de confiança preenche (600 ms, atraso de 180 ms).
- Swipe, salvar, toggles e login: exatamente como na tabela da §7.
- Skeleton shimmer de 1,2 s em loop (desligado com reduzir movimento).

### 6.5 Reduzir movimento
`final reduce = MediaQuery.disableAnimationsOf(context) || prefs.reduzirMovimento;`
- Se `reduce`, durações de 0 ou fade de 150 ms. Sem partículas, sem shake (o aviso âmbar continua), sem shimmer e sem Hero (usar fade).
- **Os haptics continuam** (não são movimento).

## 7. Haptics
A tabela completa (evento → API Flutter → animação → duração/curva) está em `haptics.md` (cópia nesta pasta). Implementação:
```dart
abstract final class AppHaptics {
  static bool enabled = true;                 // ligado ao toggle Vibração (prefs)
  static Future<void> selection() async { if (enabled) await HapticFeedback.selectionClick(); }
  static Future<void> confirm()  async { if (enabled) await HapticFeedback.lightImpact(); }   // assentar, salvar, desfazer, baixa confiança, ligar vibração
  static Future<void> result()   async { if (enabled) await HapticFeedback.mediumImpact(); }  // obturador, resultado alta/média, excluir
  static Future<void> blocked() async {        // foto ruim
    if (!enabled) return; await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 60)); await HapticFeedback.heavyImpact(); }
  static Future<void> linked() async {         // conta vinculada
    if (!enabled) return; await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 90)); await HapticFeedback.lightImpact(); }
}
```
- Resumo dos usos:
  - `selection`: aba, segmentado, toggle, swipe passando do limite, remover dos salvos;
  - `result`: obturador, resultado alta/média, excluir;
  - `confirm`: assentamento, salvar, desfazer, resultado baixa, ligar Vibração;
  - `blocked`: foto ruim;
  - `linked`: login.
- Não vibram: rolagem, abrir dicas, progresso dos chips, boot, pull-to-refresh, erros de rede.
- Ao ligar a Vibração, tocar `confirm` depois de gravar a pref, como amostra.

## 8. Acessibilidade
- **Contraste:** texto ≥ 4,5:1 e ícones/bordas ≥ 3:1 nos temas claro e escuro. No Modo Sol, ≥ 7:1 (texto preto sobre branco e #1F4D2E sobre branco = 9,6:1). Testar com `meetsGuideline(textContrastGuideline)`.
- **Alvos:** ≥ 48 dp (`androidTapTargetGuideline`); 56 dp no Sol. Chips da câmera não são clicáveis (apenas `Semantics(liveRegion)`).
- **Semantics:**
  - linha do histórico: `"Franco-argilosa, 10:42, 82% de confiança"` + ação "Excluir";
  - badge: "Confiança alta, 82 por cento";
  - obturador: "Fotografar", com `enabled` e dica "Aguardando luz, foco e distância" quando bloqueado;
  - aviso foto ruim e snackbar: `liveRegion: true`;
  - triângulo: `excludeSemantics` + rótulo "Diagrama do triângulo textural, classe Franco-argilosa destacada";
  - stat: "6 análises nesta semana".
- **Escala de fonte:** suportar até 200% (`MediaQuery.textScalerOf`). Sem altura fixa em linhas e botões (usar `minHeight`). A partir de 1,3×, os stats passam para 1 coluna e os botões do rodapé empilham. "Tamanho do texto: Grande" aplica 1,15× sobre a escala do sistema.
- Foco visível em todos os interativos (anel da §1.1) e ordem de leitura igual à visual.
- Não depender de cor: status, confiança e chips sempre com texto ou ícone.

## 9. Login Google opcional
- O login é **opcional**: o app funciona 100% anônimo e local. "Agora não" no onboarding e o vínculo depois em Perfil ou Configurações. Já existem `google_auth_service.dart` e `google_sign_in_gateway.dart`; só ligar a UI.
- **Branding (Google Identity guidelines):**
  - usar o logo "G" multicolor oficial, sem recolorir, em fundo branco/claro (#FFFFFF, borda #747775) ou escuro (#131314, texto #E3E3E3, borda #8E918F). No Modo Sol, a versão clara com altura de 56;
  - texto exato **"Continuar com o Google"**, Roboto Medium 14 (ou a fonte do sistema), formato pill, padding de 12 e gap de 10 entre logo e texto;
  - não usar o logo sozinho, não usar a cor primária do app no botão e não colocar outro ícone.
- Depois de vincular: anel verde no avatar + `AppHaptics.linked()`. Em caso de erro: snackbar (§3.2). Ao sair: confirmação "Sair da conta? As análises continuam neste aparelho."

## 10. Responsividade
- **Telas pequenas (≤ 360 × 640):**
  - a moldura da câmera reduz para 80% da largura;
  - ilustração do onboarding com altura máxima de 200;
  - stats com 3 colunas e valor de 20;
  - rodapé do resultado empilhado;
  - a NavigationBar mantém os rótulos.
- **Tablet (≥ 600 dp):** `NavigationRail` à esquerda.
  - Conteúdo com largura máxima de 560, centralizado.
  - Histórico em master-detail ≥ 840 (lista 360 + detalhe).
  - Resultado em 2 colunas (triângulo | informações).
  - Câmera em tela cheia, em retrato.
- Orientação: telefone travado em retrato, inclusive na câmera. Tablet livre (a câmera também em retrato).
- Safe areas: `SafeArea` em tudo. Câmera com edge-to-edge.

## 11. NÃO implementar
1. **Frações** de areia/silte/argila da amostra (o modelo não as devolve). As faixas de "Sobre a classe" são texto de referência por classe.
2. **Top 3** ou qualquer lista de classes alternativas ou probabilidades.
3. **Talhão** (cadastro, seleção ou agrupamento por área).
4. **Indicador de vibração** (a onda e o nome do haptic no canto) e os selos "Exemplo"/"Simulação" do mock.
5. Os dados fictícios do mock (Ana Ribeiro, Rio Verde, dicas "exemplo").

## 12. Ordem de implementação (PRs pequenos)
| # | PR | Critérios de aceite |
|---|---|---|
| 1 | Tokens: `AppPalette` (claro/escuro/sol), `AppDensity`, `AppRadius.xs`, Inter, `AppTypography` | Golden tests das 3 paletas. Contraste verificado por teste. Nenhuma tela muda de layout |
| 2 | `AppTheme.sun` + seletor de 3 temas em `appearance_provider` | Trocar tema em Configurações atualiza tudo sem reiniciar. Alvos de 56 no Sol (`androidTapTargetGuideline` customizado) |
| 3 | `ConfidenceLevel` 75/50 + "Média" + `ConfidenceBadge`/`ConfidenceBar` | Testes nos limites 49,9/50/74,9/75. Badge com rótulo + % |
| 4 | `AppMotion` (curvas M3) + `AppHaptics` estendido + toggle Vibração + reduzir movimento | Vibração off silencia tudo. Com `disableAnimations`, nenhuma animação acima de 150 ms (widget test) |
| 5 | Componentes base (§4): botões, pills, tiles, stat, segmentado, switch tile, estados | Widget tests de cada estado. Semantics em todos |
| 6 | Home (`08`/`09`/`25`/`27`) | Bate com o PNG nos 3 temas (golden). Vazio, skeleton e erro |
| 7 | Câmera: chips, obturador, aviso foto ruim (`10`/`11`/`12`/`28`) | Bloqueado: shake, aviso por 3,8 s e haptic ×2. Pronto: medium e flash (sem flash no Sol) |
| 8 | Processando + `TextureTriangle` com partículas (`29`–`31`/`38`) | 60 fps em aparelho de entrada (profile mode). Sem partículas no Sol e com reduzir movimento |
| 9 | Resultado + erro + salvar (`14`/`15`/`32`/`33`) | 3 níveis de confiança. Haptic por nível. Snackbar salvo |
| 10 | Histórico + swipe/undo + offline + coleção (`16`–`18`/`34`) | O swipe mantém a miniatura visível. O undo restaura a posição. Ação semântica Excluir. Banner plural |
| 11 | Detalhe + Hero (`19`) e Dicas (`20`) | Hero sem jank. Estados offline e erro |
| 12 | Perfil como 4ª aba (`21`/`22`) + Configurações + Exportar (`23`/`24`/`35`/`36`) | Todos os itens com copy exato. CSV gerado com as colunas escolhidas |
| 13 | Onboarding 4 passos + login Google (`02`–`07`/`37`) | Pular funciona. O botão Google segue o branding. Erro e offline tratados |
| 14 | Boot Peneira + Hero do logo (`01`) | ≤ 1,6 s. Pular. Reduzir movimento |
| 15 | Responsivo (rail, master-detail) + escala de fonte 200% | Sem overflow em 320×568 e com texto a 200%. Rail ≥ 600 dp |

## 13. Referência de PNGs (`telas/`)
01 boot · 02–04, 37 login · 05–07 onboarding · 08, 09, 25, 27 home · 10, 11, 12, 28 câmera · 13, 29–31, 38 processando · 14, 15, 26, 32, 33 resultado · 16–18, 34 histórico · 19 detalhe · 20 dicas · 21, 22 perfil · 23, 24, 35, 36 configurações.

## 14. Decisões aprovadas (23/10/2026)
1. **Tema inicial:** segue o sistema (claro/escuro). O Modo Sol só liga manualmente em Configurações.
2. **Textos:** os textos de apoio de confiança média/baixa (§3.14) e os de erro/offline (§3.2, §3.3, §3.6, §3.7, §3.9) estão aprovados como copy final.
3. **Escuro `surface`:** #1E201D (valor do repo).
4. **`AppMotion.emphasized`:** passa a ser `Cubic(.2,0,0,1)` (M3), inclusive nas animações existentes.
5. **Orientação:** telefone travado em retrato, inclusive na câmera.
6. **Perfil:** tela nova, 4ª aba da barra (Início · Histórico · Dicas · Perfil). Configurações é acessada pelo Perfil.
7. **Haptic heavy:** `heavyImpact` ×2 (60 ms de intervalo) só na foto ruim. Supera a regra "sem tier heavy" do repo.
8. **Confiança:** alta ≥ 75, média 50–74, baixa < 50, com o rótulo "Média" (substitui "Moderada").
