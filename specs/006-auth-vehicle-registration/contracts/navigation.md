# Contract: Navegação e UI autenticada (iOS)

## Route catalog

| Route | Access | Arguments | Purpose |
|---|---|---|---|
| root `SessionGateView` | root | none | initializing, verifying, offline retry, blocked profile |
| Welcome (`RootPhase.unauthenticated`) | unauthenticated | none | public entry |
| `UnauthenticatedRoute.login` | unauthenticated | none | e-mail/senha login |
| `UnauthenticatedRoute.signUp` | unauthenticated or signup-in-progress | none | fluxo existente de `005` |
| `VehicleOnboardingView` (root, fora da `TabView`) | authenticated + pending | none | decisão explícita pós-cadastro |
| Home tab | authenticated | none | snapshot personalizado da conta |
| Garagem tab | authenticated | none | veículos ativos e seleção de principal |
| `VehicleFormView(origin:)` | authenticated | `.onboarding` ou `.garage` | formulário de veículo; owner nunca é passado |
| Perfil tab | authenticated | none | identidade atual e logout |
| rota existente de solicitação de serviço | authenticated | apenas ID do serviço existente | comportamento preservado |

Todas as rotas ficam centralizadas em `PitGoRoute`/`UnauthenticatedRoute` (`Hashable`). UUID,
e-mail, token, CPF/CNPJ, Renavam e chassi nunca aparecem em argumentos de navegação.

## Root session gate

`PitGoRootView` observa `SessionStore.state` (`AppSessionState`) e decide a raiz renderizada; este
destino não mostra dados da Home.

| Session state | Render/navegação |
|---|---|
| `.initializing`, `.verifying` | `ProgressView` em tela cheia |
| `.offlineVerification` | mensagem de verificação offline + `Tentar novamente` |
| `.profileBlocked` | mensagem de perfil bloqueado + `Tentar novamente` + `Sair` |
| `.unauthenticated` | monta a `NavigationStack` não autenticada (Welcome raiz), descartando destinos privados |
| `.authenticated` + onboarding pendente | monta `VehicleOnboardingView` (fora da `TabView`) |
| `.authenticated` + onboarding resolvido | monta a `TabView` autenticada (Home selecionada) |

Qualquer transição de `.authenticated` para um estado não autenticado/de verificação oculta
imediatamente o conteúdo privado — a troca de `RootPhase` descarta a `TabView`/`VehicleOnboardingView`
inteira, removendo também qualquer estado de ViewModel associado. `.offlineVerification` preserva a
sessão do SDK, mas não preserva um snapshot visível de Home/formulário.

## Login flow

```text
Welcome --Entrar--> Login (empilha .login no NavigationStack não autenticado)
Login --credenciais válidas + perfil verificado--> RootPhase muda para .home
Login --Voltar--> Welcome
```

- envio duplicado ignorado durante processamento;
- erros locais de campo aparecem antes de qualquer acesso à rede;
- falha remota permanece em Login com mensagem acionável;
- a navegação de sucesso descarta a `NavigationStack` não autenticada inteira (Login/Welcome somem
  junto com qualquer senha residual em memória);
- Voltar a partir da Home nunca revela o formulário de senha (a pilha não autenticada não existe
  mais).

## Signup and onboarding flow

```text
Welcome --Criar conta--> SignUp
SignUp --perfil confirmado + pendência persistida--> RootPhase.authenticated + onboarding pendente
VehicleOnboardingView --Agora não--> Home (pendência resolvida)
VehicleOnboardingView --Cadastrar veículo--> VehicleFormView(.onboarding) (pendência resolvida)
VehicleFormView(.onboarding) --salvo--> Home
VehicleFormView(.onboarding) --Voltar/descarte confirmado--> Home sem veículo
```

O destino de onboarding não pode ser dispensado sem uma ação explícita — ele não é empilhado numa
`NavigationStack` com gesto de borda habilitado da forma usual; um `.interactiveDismissDisabled()`
(ou equivalente ao renderizá-lo como tela cheia sem `NavigationStack`) impede o descarte por gesto.
Reabrir o app usa o estado pendente para reapresentá-lo antes da Home. Se persistir a pendência
falhar, o cadastro não emite sucesso de UI; ele permanece recuperável sem repetir a criação de
identidade.

## Garage flow

```text
Home/Perfil --aba Garagem--> Garagem
Garagem --Adicionar veículo--> VehicleFormView(.garage)
VehicleFormView(.garage) --salvo--> Garagem atualizada
VehicleFormView(.garage) --Voltar/descarte confirmado--> Garagem
Garagem --selecionar principal--> Garagem atualizada
Garagem --aba Início--> Home atualizada
```

Voltar a partir de um formulário de veículo com rascunho sujo exige confirmação de descarte
(`.confirmationDialog`). Expiração de sessão contorna o diálogo, limpa o rascunho e roteia pelo
tratamento de sessão (troca de `RootPhase`). Uma identidade autenticada diferente nunca recebe esse
rascunho.

## Profile/logout flow

```text
Home/Garagem --aba Perfil--> Perfil
Perfil --Sair + confirmar--> RootPhase muda para .unauthenticated (Welcome)
```

Logout limpa o snapshot de sessão, os ViewModels/pilha de navegação e a sessão local do
`supabase-swift`, mesmo que a revogação remota esteja indisponível. A pendência de onboarding
daquele `userID` não é tratada como conteúdo de tela privada e permanece, para que a mesma conta
responda depois.

## Bottom navigation (`TabView`)

- Início, Garagem e Perfil são destinos ativos nesta feature — Garagem e Perfil já existiam como
  abas placeholder desde `002-initial-layouts` e passam a navegar de fato;
- o estado selecionado segue a aba atual e inclui semântica de ícone/texto, não somente cor;
- Serviços e Atendimentos preservam o comportamento atual (não navegável) até sua própria feature;
- a solicitação de serviço mantém Início selecionado, como no design existente;
- uma única `PitGoBottomTabs`/`TabView` compartilhada (de `002`) é reutilizada, sem duplicação por
  tela.

## Screen contracts

### `SessionGateView`

- sem `TabView`;
- progresso ou um único card de erro;
- offline: `Tentar novamente`;
- perfil bloqueado: `Tentar novamente` e `Sair`;
- mensagens nunca incluem IDs ou detalhes de backend.

### `LoginView`

- ação de voltar no topo, título e conteúdo com `ScrollView`/`.scrollDismissesKeyboard`;
- e-mail e senha obrigatórios; senha oculta com toggle de visibilidade;
- CTA desabilitado com progresso durante o envio;
- erros anunciados e `@FocusState` no primeiro campo inválido;
- senha não é salvável/persistente e é limpa após falha remota.

### `VehicleOnboardingView`

- superfície autenticada sem `TabView`;
- motivo conciso para cadastrar um veículo;
- ação primária `Cadastrar veículo` e secundária `Agora não`;
- Voltar/gesto não resolve/dispensa silenciosamente a decisão pendente.

### Home (dentro da `TabView`)

- loading, conteúdo personalizado, sem-veículo e falha são exclusivos;
- nome do perfil/`AsyncImage` do avatar ou iniciais a partir do snapshot autorizado;
- card de veículo ausente/substituído por estado vazio acionável quando não há principal;
- texto de endereço é neutro, nunca dado demonstrativo;
- serviços existentes continuam utilizáveis.

### Garagem (dentro da `TabView`)

- `TabView` fixa compartilhada, conteúdo rolável acima dela;
- estado vazio com ação de adicionar;
- somente cards de veículo ativo;
- item principal com semântica de rótulo/check independente de cor;
- progresso por item impede toques repetidos durante troca de principal;
- ação de adicionar (botão flutuante ou de largura total) com alvo de pelo menos 44×44pt.

### `VehicleFormView`

- barra de navegação e uma única coluna rolável IME-safe (`.scrollDismissesKeyboard`);
- marca/modelo obrigatórios; todos os opcionais do schema disponíveis;
- exibição formatada para placa/Renavam/chassi/campos numéricos enquanto o estado permanece
  normalizável;
- `Tornar principal` opcional, exibido somente quando a conta já tem veículo;
- CTA de envio com altura mínima de 56pt, texto de progresso e guarda contra toque duplo;
- primeiro campo inválido recebe foco (`@FocusState`) e erro de apoio;
- sem alturas fixas que cortem texto com fonte ampliada.

### Perfil (dentro da `TabView`)

- `TabView` compartilhada com Perfil selecionado;
- nome/e-mail atuais do snapshot;
- ação explícita `Sair` com confirmação;
- sem exibição de CPF/CNPJ nesta entrega.

## Navigation consistency rules

- todo efeito colateral de navegação é iniciado por Views observando estado durável de ViewModel
  (`@Observable`);
- ViewModels/Repositories nunca recebem referência à `NavigationPath`/`NavigationStack`;
- callbacks usam uma guarda síncrona local (`@State isNavigating`/verificação de estado) para
  impedir destinos duplicados, mesmo racional do `dropUnlessResumed` do Android;
- rotas privadas verificam o estado central antes de renderizar qualquer componente personalizado;
- retornar à Home após mutação de veículo solicita um novo snapshot da conta;
- gesto de sistema, botão de navegação e diálogos de descarte têm um único comportamento
  compartilhado por destino.
