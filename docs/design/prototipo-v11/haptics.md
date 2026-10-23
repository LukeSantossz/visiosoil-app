# VisioSoil v11 · Microinterações e mapa de haptics

Princípios:
- O haptic confirma uma ação do usuário ou um resultado do sistema. Não toca em rolagem nem em animação decorativa.
- No máximo 1 haptic por evento. Nunca toca em loop.
- O toggle **Configurações → Preferências → Vibração** (ligado por padrão) desliga todos os haptics. Implementar com `if (prefs.vibracao) HapticFeedback.x()`.
- **Reduzir movimento** (`MediaQuery.disableAnimationsOf`) troca as animações por um fade de 150 ms ou por nenhuma animação. Os haptics continuam, porque não são movimento. Se a vibração estiver desligada, eles não tocam.
- **Modo Sol:** sem partículas, flash ou brilhos. Ficam só as mudanças de estado (cor/ícone) e os haptics. A partícula usa #1F4D2E, de alto contraste.
- **Curvas (tokens M3):**
  - emphasized `Cubic(.2,0,0,1)`
  - emphasizedDecelerate `Cubic(.05,.7,.1,1)`
  - emphasizedAccelerate `Cubic(.3,0,.8,.15)`
  - standardDecelerate `Cubic(0,0,0,1)`
  - standardAccelerate `Cubic(.3,0,1,1)`
- **Mock:** o indicador no canto superior direito (onda + nome do haptic) existe só no protótipo e não vai para o app. No mock, `navigator.vibrate(padrão)` é chamado quando disponível (Android/Chrome) e o padrão em ms está na coluna "Padrão web".

| Evento | Flutter | Padrão web (ms) | Animação | Duração / curva |
|---|---|---|---|---|
| Troca de aba (barra inferior) | `HapticFeedback.selectionClick()` | 8 | Indicador da aba estica (scaleX .6→1.08→1) | 320 ms · emphasizedDecelerate |
| Segmentado (Análises/Coleção, Tema, Texto) | `selectionClick()` | 8 | Indicador desliza (já existia na v9) | 250 ms · emphasized |
| Obturador: captura liberada | `HapticFeedback.mediumImpact()` | 18 | Botão afunda (scale .86) + flash branco 55% | 280 ms emphasized + flash 260 ms standardDecelerate |
| Obturador: foto ruim (bloqueado) | `heavyImpact()` ×2, com 60 ms de intervalo | 30·60·30 | Tremor do botão (v3) + aviso âmbar fixo acima dos chips + contorno âmbar nos chips que falharam | tremor 300 ms linear · aviso entra em 240 ms emphasizedDecelerate e fica 3,8 s |
| Processando: assentamento | `HapticFeedback.lightImpact()` no fim (2,1 s) | 12 | 26 partículas de solo caem de cima (com dispersão) e assentam dentro da região da classe. Somem quando a região preenche. Pulso de 4% na região | cada partícula 760 ms emphasizedDecelerate, defasagem de 28 ms entre elas (de 1,15 s a 1,9 s) · saída 280 ms standardAccelerate · pulso 360 ms |
| Entrada do resultado | `mediumImpact()` (confiança alta/média) · `lightImpact()` (baixa) | 18 / 12 | Blocos sobem 8 px em cascata (v10) + barra de confiança preenche da esquerda | cascata 250 ms standardDecelerate (+30 ms por bloco) · barra 600 ms emphasizedDecelerate, atraso de 180 ms |
| Salvar (bookmark) | `lightImpact()` | 12 | Ícone preenche + pop scale 1.28 + snackbar "Salvo no histórico" | 340 ms emphasizedDecelerate · snackbar 250 ms |
| Remover dos salvos | `selectionClick()` | 8 | Ícone esvazia + encolhe para .8 | 340 ms emphasizedDecelerate |
| Histórico: deslizar e revelar Excluir | `selectionClick()` ao passar do limite (50 px) | 8 | Linha recua 12 px e o botão vermelho "Excluir" (104 px) entra pela direita. A miniatura continua visível | 240 ms emphasizedDecelerate |
| Histórico: excluir | `mediumImpact()` | 18 | "Excluir" se expande até a largura toda e a linha sai para a esquerda, depois a altura colapsa. Snackbar com "Desfazer" | saída 220 ms emphasizedAccelerate · colapso 260 ms emphasized (atraso de 180 ms) |
| Desfazer exclusão | `lightImpact()` | 12 | Linha volta (fade + scale .98→1) | 250 ms emphasizedDecelerate |
| Toggles (Configurações) | `selectionClick()` | 8 | Thumb da chave faz "mola" (achata 1.18×.86 no meio do trajeto) | 260 ms emphasizedDecelerate |
| Ligar Vibração | `lightImpact()` (amostra do que vai sentir) | 12 | Mesma mola do toggle | 260 ms |
| Login Google vinculado | `mediumImpact()` e, 90 ms depois, `lightImpact()` | 18·90·12 | Card da conta sobe 10 px + anel verde se expande no avatar + nuvem com check (v9) | card 340 ms emphasizedDecelerate (atraso de 120 ms) · anel 700 ms standardDecelerate |

Não vibram: rolagem, abrir dicas, progresso dos chips da câmera (já há feedback visual), boot, pull-to-refresh, erros de rede (mostram só o snackbar de erro). O motivo é evitar excesso.
