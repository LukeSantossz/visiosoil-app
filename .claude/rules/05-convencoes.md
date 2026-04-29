# 5. Convenções de Código

## 5.1 Nomenclatura — VAR Method

O VAR Method é complementar às convenções já existentes no projeto, não substituto. Se o projeto já possui padrões de nomenclatura estabelecidos, eles têm precedência. Os sufixos abaixo se aplicam quando não há convenção prévia ou quando a convenção existente não cobre o caso.

**Sufixos primários:**

| Sufixo | Significado | Uso |
|--------|-------------|-----|
| `Data` | Dados brutos | Informações cruas, payloads, atributos simples de objetos. Ex: `userData`, `paymentData` |
| `Info` | Metadados | Dados processados, resumos descritivos, configuração. Ex: `systemInfo`, `accountInfo` |
| `Manager` | Gerenciador | Classes ou objetos que orquestram processos, estados e conexões. Ex: `SessionManager` |
| `Handler` | Manipulador | Funções que reagem a eventos específicos. Ex: `onClickHandler`, `submitFormHandler` |

**Sufixos estendidos (aplicar conforme a arquitetura do projeto):**

| Sufixo | Significado | Uso |
|--------|-------------|-----|
| `Service` | Serviço | Lógica de negócio ou integração com APIs externas. Ex: `AuthService`, `PaymentService` |
| `Repository` | Repositório | Acesso e persistência de dados. Ex: `UserRepository`, `OrderRepository` |
| `Controller` | Controlador | Ponto de entrada para requisições ou navegação. Ex: `AuthController` |
| `Adapter` | Adaptador | Tradução entre interfaces ou formatos. Ex: `ApiAdapter`, `StorageAdapter` |
| `Mapper` | Mapeador | Conversão entre modelos ou entidades. Ex: `UserMapper`, `ResponseMapper` |
| `Middleware` | Intermediário | Processamento intermediário em pipelines. Ex: `AuthMiddleware`, `LogMiddleware` |
| `Provider` | Provedor | Fornecimento de dependências ou estado. Ex: `ThemeProvider`, `AuthProvider` |
| `Hook` | Hook | Lógica reutilizável com estado em frameworks reativos. Ex: `useAuth`, `useFetch` |

## 5.2 Commits — Conventional Commits

Estrutura obrigatória: `!type(?scope): !subject`

- **type:** o tipo da alteração (ver tabela abaixo).
- **scope:** o contexto da mudança (opcional, entre parênteses).
- **subject:** mensagem descritiva **em inglês**, no imperativo, lowercase. Teste: "If applied, this commit will... [subject]".

| Tipo | Quando usar |
|------|-------------|
| `feat` | Nova funcionalidade para o usuário |
| `fix` | Correção de bug |
| `docs` | Alterações apenas na documentação |
| `style` | Formatação, espaços, ponto e vírgula (sem mudar lógica) |
| `refactor` | Refatoração de código (sem corrigir bugs ou criar features) |
| `perf` | Melhoria de performance |
| `test` | Criação ou ajuste de testes |
| `chore` | Alterações de build, ferramentas ou configurações |
| `build` | Dependências externas ou sistema de build |
| `ci` | Configuração de CI |
| `revert` | Reversão de um commit anterior |

Exemplos: `feat(auth): add google sign-in integration`, `fix(api): handle 500 error on users endpoint`.

**Restrições obrigatórias de commit:**

- **Sem body/description:** O commit contém APENAS a linha de subject. Nunca adicione corpo, rodapé, parágrafos explicativos ou qualquer texto além da primeira linha. Se a mudança não cabe em uma linha de subject clara, a mudança é grande demais — quebre em commits menores.
- **Sem Co-authored-by:** Nunca inclua trailers de co-autoria (`Co-authored-by`, `Signed-off-by`, etc.). O responsável pelo commit é quem o executa. Código gerado por IA não tem autoria a ser creditada.
- **Formato final do comando:** `git commit -m "type(scope): subject"` — nada além disso.

## 5.3 Branches — Nomenclatura

Toda branch de trabalho segue o formato: `type/TASK-NNN-descricao-curta`

- **type:** o mesmo tipo do Conventional Commits (feat, fix, refactor, etc.).
- **TASK-NNN:** referência direta à task registrada em `tasks.md`.
- **descricao-curta:** 2 a 4 palavras separadas por hífen, descrevendo o escopo.

Exemplos: `feat/TASK-001-login-google`, `fix/TASK-012-erro-upload-foto`, `refactor/TASK-023-migrar-hive`.

O agente deve sugerir o nome da branch ao iniciar uma task, seguindo esta convenção. Se o projeto já possuir uma convenção de branches estabelecida, ela tem precedência.

## 5.4 Pull Requests — Labels Obrigatórias

Toda Pull Request criada pelo agente deve incluir labels correspondentes. O agente aplica labels via `gh pr create --label` ou `gh pr edit --add-label`.

**Labels mínimas obrigatórias:**

| Label | Quando aplicar |
|-------|---------------|
| Tipo (`feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `ci`) | Sempre — corresponde ao tipo do commit/task |
| `patch`, `minor` ou `major` | Sempre — corresponde à complexidade da task |

O agente deve verificar se as labels existem no repositório antes de aplicá-las. Se não existirem, deve criá-las via `gh label create` ou informar ao usuário.
