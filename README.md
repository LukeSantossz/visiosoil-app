# VisioSoil App

## O que isso faz?

Aplicativo mobile para classificação de textura do solo por imagem. Funcionalidades planejadas:

- Captura de fotos de amostras de solo via câmera ou importação da galeria
- Registro automático de coordenadas GPS no momento da captura
- Geocodificação reversa (conversão de coordenadas em endereço legível)
- Armazenamento local dos registros no dispositivo
- Histórico de capturas com visualização detalhada de cada registro
- Classificação de textura do solo por modelo de IA embarcado (fase futura)

## O que é?

Aplicativo mobile multiplataforma (Android + iOS) desenvolvido com Flutter. Codebase única em Dart que compila nativamente para ambas as plataformas. O app é voltado para uso em campo no agronegócio, onde o usuário fotografa amostras de solo e obtém dados geolocalizados para análise.

## Quais tecnologias são usadas?

| Tecnologia | Função |
|---|---|
| **Flutter** | Framework multiplataforma (Android + iOS) |
| **Dart** | Linguagem de programação nativa do Flutter |
| **Riverpod** | Gerenciamento de estado (type-safe, escalável) |
| **Hive** | Persistência local NoSQL (leve, sem dependência nativa) |
| **GoRouter** | Navegação declarativa com deep linking |
| **image_picker** | Captura de fotos via câmera e importação da galeria |
| **geolocator** | Obtenção de coordenadas GPS |
| **geocoding** | Conversão reversa de coordenadas para endereço |
| **TensorFlow Lite** | Classificação de textura do solo on-device (Fase 2) |

## Qual é a ambição do projeto?

O VisioSoil é a evolução para produção mobile de um trabalho acadêmico apresentado na conferência ConBAP, onde comparou-se a arquitetura SqueezeNet contra métodos manuais (FFT, Gabor, LBP) para classificação de textura do solo. O objetivo é transformar essa pesquisa em um produto real e funcional para uso no campo por profissionais do agronegócio.

## Qual é o estágio do projeto?

**Status: em desenvolvimento — Fase 1 (fundação mobile)**

### Concluído

- Flutter SDK instalado e configurado
- Android Studio com emulador funcional
- Repositório Git criado e publicado no GitHub
- Estrutura de pastas feature-first implementada
- Fundamentos Dart (variáveis, tipos, funções, classes, null safety)
- Tela inicial com MaterialApp, Scaffold, AppBar, widgets de texto e botão

### Pendente (Fase 1)

- Extração da HomeScreen para arquivo dedicado
- Navegação com GoRouter (4 rotas declarativas)
- Gerenciamento de estado com Riverpod
- Telas de Captura, Histórico e Detalhes
- BottomNavigationBar
- Integração com image_picker (câmera e galeria)
- Permissões Android e iOS
- Preview de imagem capturada
- Integração com geolocator e geocoding
- Persistência local com Hive e modelo SoilRecord
- Histórico populado com dados reais

### Pendente (Fase 2)

- Integração de modelo classificador de textura do solo via TensorFlow Lite on-device

## Existem problemas conhecidos?

- O app está na fase inicial de desenvolvimento. Atualmente exibe apenas a tela principal com UI placeholder (textos e botão sem funcionalidade real).
- Nenhum pacote externo (Riverpod, Hive, GoRouter, image_picker, etc.) foi integrado ainda. As dependências listadas acima refletem a arquitetura alvo, não o estado atual.
- O botão "Capturar Solo" na tela inicial apenas imprime uma mensagem no console como placeholder — a funcionalidade real de câmera será implementada na Semana 3.

## Como executar

```powershell
# Clonar o repositório
git clone https://github.com/com.visiosoil/visiosoil-app.git

# Entrar no diretório
cd visiosoil-app

# Instalar dependências
flutter pub get

# Executar no emulador ou dispositivo conectado
flutter run
```

## Estrutura do Projeto

```
lib/
  main.dart             — ponto de entrada do app
  core/
    constants/          — cores, strings, dimensões
    theme/              — ThemeData customizado
    utils/              — funções utilitárias
    features/
      home/             — tela principal
      capture/          — captura de imagem
      history/          — histórico de registros
      details/          — detalhes de registro individual
  models/               — classes de dados (SoilRecord)
  providers/            — Riverpod providers
```
