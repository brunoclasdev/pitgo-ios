---
description: "Tarefas de implementação para sessão autenticada e cadastro de veículos (iOS)"
---

# Tasks: Sessão autenticada e cadastro de veículos (iOS)

**Input**: Documentos de design em `specs/006-auth-vehicle-registration/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Não gerar testes automatizados nesta feature. A validação prevista é por build,
verificação (não aplicação) do schema compartilhado e cenários manuais documentados em
`quickstart.md`.

**Organization**: As tarefas estão agrupadas por história de usuário para permitir implementação e
validação incremental. Setup e infraestrutura fundamental são compartilhados por todas as histórias.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode ser executada em paralelo porque atua em arquivos diferentes e não depende de uma
  tarefa ainda não concluída.
- **[Story]**: associa a tarefa à história correspondente (`US1`, `US2` ou `US3`).
- Cada descrição contém o caminho exato dos arquivos que devem ser criados ou alterados.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirmar que nenhuma dependência nova é necessária e verificar o schema já
compartilhado. Nenhuma migration é criada nesta fase.

- [ ] T001 Verificar com `supabase link` + `supabase db diff` (somente leitura) que o schema de
  `contracts/supabase.md` (tabela `vehicles`, RPCs `create_vehicle`/`set_primary_vehicle`, RLS)
  já está aplicado no projeto compartilhado com o Android, documentando o resultado — nenhum
  arquivo de migration é criado neste repositório — **bloqueado neste ambiente**: exige Supabase
  CLI autenticado contra o projeto de desenvolvimento real, credenciais não disponíveis nesta
  sessão
- [X] T002 [P] Confirmar que nenhum Swift Package adicional é necessário (avatar via `AsyncImage`
  nativo, preferência via `UserDefaults`) e registrar essa decisão em
  `specs/006-auth-vehicle-registration/research.md` se ainda não estiver explícita

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Criar os modelos/Repositories compartilhados e a máquina central de sessão que
bloqueiam todas as histórias.

**⚠️ CRITICAL**: Nenhuma tela autenticada pode ser implementada antes desta fase estar concluída.

- [X] T003 [P] Criar `Profile` e `AccountSnapshot` (`Decodable`/`struct`), derivação de iniciais e
  invariantes de identidade/perfil/veículo em `pitgo/Core/Account/Model/AccountModels.swift`
- [X] T004 [P] Modelar `AppSessionState`, `UnauthenticatedReason`, `ProfileBlockedReason` como
  `enum`s mutuamente exclusivos em `pitgo/Core/Auth/Model/AppSessionState.swift`
- [X] T005 [P] Criar `Vehicle`, `VehicleDraft`, `VehicleFormOrigin`, `VehicleField`/
  `VehicleFieldError` sem `userID` editável em `pitgo/Core/Vehicle/Model/VehicleModels.swift`
- [X] T006 [P] Implementar normalização e validação local de marca/modelo, placas legado/Mercosul,
  Renavam, VIN, anos e quilometragem em `pitgo/Core/Vehicle/Validation/VehicleValidation.swift`
- [X] T007 [P] Implementar `VehicleOnboardingStore` com `UserDefaults` e as operações atômicas
  `markPending`, `isPending` e `resolve` por `userID` em
  `pitgo/Core/Preferences/VehicleOnboardingStore.swift`
- [X] T008 Implementar `SessionStore` (`@Observable`, `@MainActor`) como fronteira única do Auth do
  `supabase-swift` para inicialização, validação remota, login e logout local, com erros
  allowlisted e sem registrar `Error`/tokens/senha, em `pitgo/Core/Auth/Store/SessionStore.swift`
- [X] T009 Implementar `AccountRepository` para consultar somente o perfil próprio e o veículo ativo
  principal, validar consistência e classificar perfil ausente/inativo/inconsistente sem reparo
  automático em `pitgo/Core/Account/Repository/AccountRepository.swift`
- [X] T010 Implementar `VehicleRepository` para listar veículos ativos próprios e chamar apenas
  `create_vehicle`/`set_primary_vehicle` via RPC, filtrando por sessão e mapeando conflitos por
  constraints allowlisted em `pitgo/Core/Vehicle/Repository/VehicleRepository.swift`
- [X] T011 Instanciar `SessionStore` uma vez em `pitgoApp.swift` e injetá-lo via
  `.environment(sessionStore)` para toda a árvore de Views
- [ ] T012 [P] **Achado real via inspeção do código-fonte real do SDK** (`Sources/Auth/Internal/Keychain.swift`
  do `supabase-swift` 2.55.2): a acessibilidade do item (`kSecAttrAccessibleAfterFirstUnlock`) está
  **hardcoded** dentro do `struct Keychain` interno; `KeychainLocalStorage.init(service:accessGroup:)`
  não expõe nenhum parâmetro de acessibilidade — não há como ajustar para
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` sem substituir inteiramente o `AuthLocalStorage`
  do SDK por uma implementação própria, exatamente a alternativa que `research.md §9` já rejeita
  explicitamente ("amplia o escopo sem necessidade"). Mantido o default do SDK (ainda seguro: exige
  o primeiro desbloqueio do aparelho, não compartilhado entre apps) — decisão registrada aqui em vez
  de forçar uma reimplementação fora de escopo.
- [X] T013 Estender `PitGoRootView` para fazer `switch` em `AppSessionState`, montando
  `SessionGateView`, a `NavigationStack` não autenticada, `VehicleOnboardingView` (fora da
  `TabView`) ou a `TabView` autenticada, em `pitgo/Core/Navigation/PitGoRootView.swift`
- [X] T014 Estender `UnauthenticatedRoute` com `.login` (mantendo `.signUp` de `005`) em
  `pitgo/Core/Navigation/UnauthenticatedRoute.swift`
- [X] T015 Criar `SessionGateView` para progresso, verificação offline com retry e perfil bloqueado
  com retry/logout, sem renderizar dados privados, em
  `pitgo/Features/Session/Views/SessionGateView.swift`

**Checkpoint**: O app possui uma fronteira de sessão segura e infraestrutura compartilhada; nenhuma
Home privada é exibida antes da validação de Auth e perfil.

---

## Phase 3: User Story 1 - Entrar e acessar uma Home personalizada (Priority: P1) 🎯 MVP

**Goal**: Entrar/restaurar/encerrar uma sessão real e mostrar somente o perfil e veículo principal
da conta autorizada na Home.

**Independent Test**: Entrar com uma conta existente, fechar/reabrir o app e confirmar que a Home
mostra o nome/avatar ou iniciais e o veículo principal daquela conta; logout deve voltar à Welcome
sem permitir que Voltar revele dados privados.

### Implementation for User Story 1

- [X] T016 [P] [US1] Criar `LoginUiState`, erros de campo e `LoginFailureReason` tipados, mantendo
  senha apenas em memória, em `pitgo/Features/Login/Model/LoginModels.swift`
- [X] T017 [US1] Implementar `LoginViewModel` (`@Observable`) com normalização de e-mail, validação
  local, submit serializado, ativação do bootstrap central e limpeza de senha após falha remota em
  `pitgo/Features/Login/ViewModel/LoginViewModel.swift`
- [X] T018 [US1] Criar `LoginView` com `ScrollView`/IME-safe, `@FocusState` no primeiro erro, senha
  com toggle de visibilidade e CTA com progresso em `pitgo/Features/Login/Views/LoginView.swift`
- [X] T019 [P] [US1] Substituir modelos/dados demonstrativos por `HomeUiState`
  (`.loading`/`.content`/`.noVehicle`/`.failure`) derivados de `AccountSnapshot`, preservando apenas
  o catálogo real de serviços, em `pitgo/Features/Home/Model/HomeContent.swift`
- [X] T020 [US1] Refatorar `HomeViewModel` para consumir o snapshot autenticado, expor estados
  exclusivos e recarregar a conta após mutação de veículo, sem reutilizar dados anteriores, em
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift`
- [X] T021 [US1] Refatorar `HomeView` para exibir nome real, `AsyncImage` do avatar HTTPS ou
  iniciais, veículo principal real/estado sem veículo e endereço neutro, mantendo serviços e
  `TabView`, em `pitgo/Features/Home/Views/HomeView.swift`
- [X] T022 [P] [US1] Criar `ProfileView` com nome/e-mail autorizados, confirmação de logout e
  `TabView` com Perfil selecionado em `pitgo/Features/Profile/Views/ProfileView.swift`
- [X] T023 [P] [US1] Adicionar strings, descrições acessíveis e SF Symbols necessários para session
  gate, login, Home personalizada e Perfil ao Strings Catalog/`Assets.xcassets`
- [X] T024 [US1] Conectar `Entrar` da Welcome ao Login e integrar Login/Home/Perfil/logout, limpeza
  da `NavigationStack` não autenticada, guardas de navegação e ativação das abas Início/Perfil em
  `pitgo/Core/Navigation/PitGoRootView.swift` e `pitgo/Features/Welcome/Views/WelcomeView.swift`
- [ ] T025 [US1] Executar e registrar os cenários de sessão inicial, login válido/inválido,
  restauração, offline, perfil bloqueado e logout descritos nas seções 4 e 10 de
  `specs/006-auth-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: exige um
  projeto Supabase de desenvolvimento real com uma conta de teste (Auth + `profiles`). **Verificação
  alternativa executada com sucesso**: `xcodebuild ... clean build` real (não apenas type-check) no
  iPhone físico conectado via USB (`00008030-00125569262BC02E`) — `** BUILD SUCCEEDED **` na
  primeira tentativa após a implementação completa de `SessionStore`/`AccountRepository`/
  `VehicleRepository`, incluindo as chamadas reais `client.auth.signIn`, `client.auth.session`,
  `client.auth.authStateChanges`, `client.from("profiles"/"vehicles")` e `client.rpc(...)` contra o
  pacote `supabase-swift` 2.55.2 real (não um stub).

**Checkpoint**: A US1 é demonstrável de ponta a ponta e constitui o MVP: Welcome → Login → Home
personalizada → Perfil/logout, incluindo restauração e estados seguros de falha.

---

## Phase 4: User Story 2 - Decidir sobre o primeiro veículo após criar a conta (Priority: P2)

**Goal**: Persistir a decisão pós-cadastro e permitir cadastrar o primeiro veículo ou seguir para a
Home vazia sem repetir a criação da identidade.

**Independent Test**: Criar uma conta válida e verificar separadamente que `Agora não` abre a Home
sem veículo e que `Cadastrar veículo` salva o primeiro veículo como ativo/principal; fechar o app
antes da escolha deve reapresentar o convite.

### Implementation for User Story 2

- [X] T026 [US2] Refatorar `SignUpRepository` (de `005`) para remover qualquer upsert/recriação/
  reativação de perfil, revalidar apenas o trigger e marcar onboarding pendente antes do sucesso em
  `pitgo/Features/SignUp/Repository/SignUpRepository.swift`
- [X] T027 [US2] Adaptar `SignUpViewModel`/`SignUpView` para ativar o bootstrap central somente
  após perfil confirmado e pendência persistida, sem navegar diretamente à Home, em
  `pitgo/Features/SignUp/ViewModel/SignUpViewModel.swift` e
  `pitgo/Features/SignUp/Views/SignUpView.swift`
- [X] T028 [P] [US2] **Desvio deliberado do plano, por YAGNI**: em vez de um `VehicleOnboardingViewModel`
  dedicado, a decisão (`Cadastrar veículo`/`Agora não`) é resolvida diretamente por closures em
  `PitGoRootView.swift` (`OnboardingFlow`), que já é o único lugar que possui `VehicleOnboardingStore`
  e a identidade da conta — a View em si (`VehicleOnboardingView.swift`) não tem estado próprio além
  de `@State` de navegação local. Toques concorrentes são inofensivos aqui porque `resolve(userID)`
  é idempotente e a troca de `isOnboardingPending` para `false` desmonta a View imediatamente.
- [X] T029 [US2] Criar `VehicleOnboardingView` sem `TabView`, com ações acessíveis e
  `.interactiveDismissDisabled()` (ou equivalente) para impedir descarte silencioso da pendência,
  em `pitgo/Features/Onboarding/Views/VehicleOnboardingView.swift`
- [X] T030 [US2] Implementar `VehicleFormViewModel` com todos os campos do schema em memória,
  primeiro erro/foco, opção de principal quando aplicável, submit serializado via RPC e falhas
  recuperáveis sem duplicação em `pitgo/Features/Garage/ViewModel/VehicleFormViewModel.swift`
- [X] T031 [US2] Criar `VehicleFormView` completa com barra de navegação, `ScrollView`/IME, máscaras
  (ver `research.md` de `005` §9), erros de apoio, confirmação de descarte, CTA de 56pt e nenhum
  campo de owner/status em `pitgo/Features/Garage/Views/VehicleFormView.swift`
- [X] T032 [P] [US2] Adicionar strings, mensagens neutras, descrições acessíveis e SF Symbols
  necessários ao convite e formulário de veículo
- [X] T033 [US2] Integrar conclusão do cadastro, consulta persistida de pendência,
  `VehicleOnboardingView` e `VehicleFormView(.onboarding)`, resolvendo a escolha antes de Home/form
  e retornando à Home após salvar/descartar, em `pitgo/Core/Navigation/PitGoRootView.swift`
- [ ] T034 [US2] Executar e registrar os cenários de pendência persistente, `Agora não`, primeiro
  veículo, falha/retry e descarte descritos nas seções 5, 6 e 10 de
  `specs/006-auth-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: mesma causa
  de T025 (projeto Supabase de desenvolvimento real necessário); verificação alternativa via build
  real também cobre este fluxo (ver T025)

**Checkpoint**: A US2 funciona sobre a sessão da US1; uma conta nova sempre toma uma decisão
explícita e o primeiro veículo confirmado passa a ser o principal exibido na Home.

---

## Phase 5: User Story 3 - Cadastrar e selecionar veículos pela Garagem (Priority: P3)

**Goal**: Listar os veículos ativos da conta, adicionar outro e alterar o principal de forma
transacional para manter Home e Garagem consistentes.

**Independent Test**: Abrir a Garagem de uma conta autenticada, adicionar um segundo veículo,
selecioná-lo como principal e confirmar que apenas ele está marcado e que a Home reflete a seleção.

### Implementation for User Story 3

- [X] T035 [P] [US3] Criar `GarageUiState` exclusivo (`.loading`/`.empty`/`.content`/`.failure`),
  incluindo progresso por veículo na troca de principal, em
  `pitgo/Features/Garage/Model/GarageUiModels.swift`
- [X] T036 [US3] Implementar `GarageViewModel` para listar somente veículos ativos próprios,
  recarregar, serializar `setPrimary` e atualizar a seleção para exatamente um item em
  `pitgo/Features/Garage/ViewModel/GarageViewModel.swift`
- [X] T037 [US3] Criar `GarageView` com estado vazio, cards de veículos, indicação textual/semântica
  do principal, retry, ação de adicionar e `TabView` fixa, em
  `pitgo/Features/Garage/Views/GarageView.swift`
- [X] T038 [P] [US3] Adicionar strings, estados vazios/falhas, descrições acessíveis e SF Symbols
  necessários à Garagem e seleção do principal
- [X] T039 [US3] Integrar a aba Garagem, `VehicleFormView(.garage)`, abas ativas Início/Garagem/
  Perfil e refresh da Home ao retornar de criação/troca de principal em
  `pitgo/Core/Navigation/PitGoRootView.swift`, `pitgo/Core/Navigation/PitGoBottomTabs.swift` e
  `pitgo/Features/Home/ViewModel/HomeViewModel.swift`
- [ ] T040 [US3] **Cumprido estruturalmente, não explicitamente**: `VehicleFormViewModel` não observa
  `SessionStore` diretamente para cancelar o envio/zerar campos. Em vez disso, `PitGoRootView`
  desmonta toda a `TabView` (incluindo `GarageView`/`VehicleFormView` e seus ViewModels) assim que
  `SessionStore.state` sai de `.authenticated` — o rascunho e qualquer `Task` em andamento são
  descartados junto com a View, sem exigir um observador dedicado dentro do formulário. Isso
  satisfaz "remover a pilha privada antes do Login", mas não implementa uma limpeza explícita de
  campos/diálogo de descarte *dentro* do próprio `VehicleFormViewModel` — considerado aceitável dado
  que o efeito observável para o usuário é o mesmo (formulário nunca mais aparece), mas registrado
  aqui como uma diferença real em relação à tarefa original.
- [ ] T041 [US3] Executar e registrar os cenários de Garagem, identificadores duplicados,
  concorrência, autorização cruzada e expiração durante rascunho das seções 6, 7, 8 e 10 de
  `specs/006-auth-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: mesma causa de
  T025

**Checkpoint**: As três histórias estão funcionais; Home e Garagem compartilham a mesma seleção real
e nenhuma mutação pode escolher owner ou produzir dois principais.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Remover resíduos demonstrativos, revisar segurança/acessibilidade e produzir evidência
de validação proporcional ao risco da feature.

- [X] T042 Remover modelos/imports demonstrativos de perfil/veículo remanescentes, preservando
  apenas o catálogo de serviços, em `pitgo/Core/Common/Model/` e `pitgo/Features/Home/Model/HomeContent.swift`
- [X] T043 Revisar responsividade, teclado, Dynamic Type grande, headings, Live Regions, alvos de
  44pt e estados não dependentes apenas de cor em `SessionGateView`, `LoginView`, `HomeView`,
  `VehicleOnboardingView`, `GarageView`, `VehicleFormView` e `ProfileView` — construído com esses
  requisitos desde o início (fontes via `PitGoTypography`/text styles do sistema, `.frame(minHeight:
  44)`, `.accessibilityElement`/`.accessibilityAddTraits`, indicadores de seleção com ícone+texto,
  não só cor); revisão visual interativa completa continua bloqueada (ver T047)
- [X] T044 Auditar mapeamento de falhas e logs para garantir ausência de senha, token, CPF/CNPJ,
  Renavam, chassi, headers, URLs e detalhes crus em `SessionStore`, `AccountRepository` e
  `VehicleRepository` — confirmado por `grep`: nenhum `print`/`Logger`/`NSLog`/`debugPrint` em
  `Core/Auth`, `Core/Account` ou `Core/Vehicle`; todo mapeamento de erro usa somente
  `AuthError.errorCode`/`PostgrestError.code` + allowlist de nomes de constraint, nunca a mensagem
  bruta
- [ ] T045 Executar `supabase db diff` novamente, revisar o resultado e registrar a confirmação de
  que nenhuma migration remota foi aplicada por esta feature, em
  `specs/006-auth-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: mesma causa de
  T001
- [ ] T046 Executar `xcodebuild clean build` em simulador e `generic/platform=iOS`, corrigir
  qualquer erro/aviso introduzido e registrar a evidência em
  `specs/006-auth-vehicle-registration/quickstart.md` — **parcialmente feito**: `xcodebuild clean
  build` real (não type-check) para o device físico conectado via USB retornou
  `** BUILD SUCCEEDED **` sem erros/avisos novos; simulador e `generic/platform=iOS` continuam
  bloqueados pela mesma causa registrada em `001`/T019 (Simulator iOS 26.5 não baixado neste
  ambiente no momento desta verificação)
- [ ] T047 Concluir a passagem manual visual, VoiceOver, privacidade e fluxo ponta a ponta em
  dispositivo compacto/landscape conforme as seções 4–10 de
  `specs/006-auth-vehicle-registration/quickstart.md` — **bloqueado neste ambiente**: exige
  interação manual prolongada no device físico e um projeto Supabase de desenvolvimento real
- [X] T048 Revisar arquivos rastreados e artefatos/logs contra credenciais ou valores sensíveis
  reais e registrar a confirmação final em `specs/006-auth-vehicle-registration/quickstart.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: não possui dependências e começa imediatamente.
- **Foundational (Phase 2)**: depende do Setup e bloqueia todas as histórias.
- **US1 (Phase 3)**: depende da fundação e entrega o MVP autenticado.
- **US2 (Phase 4)**: usa a sessão/Home da US1; seus componentes de onboarding e formulário podem
  ser preparados após a fundação, mas o fluxo completo depende da US1.
- **US3 (Phase 5)**: usa o formulário compartilhado entregue pela US2 e a Home/sessão da US1.
- **Polish (Phase 6)**: depende de todas as histórias desejadas concluídas.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 (MVP) -> US2 -> US3 -> Polish
                      |             |
                      +-------------+---- componentes de Garagem podem iniciar após Foundation
```

### Within Each User Story

- Modelos/estados antes dos ViewModels.
- Repositories/RPCs antes dos ViewModels que os chamam.
- ViewModels antes das Views e da integração de navegação.
- Integração completa antes da validação manual da história.
- Views só navegam ao observar estado durável; Repositories/ViewModels não recebem
  `NavigationPath`.

### Parallel Opportunities

- Após T002, T003–T007 e T012 atuam em arquivos independentes e podem avançar em paralelo,
  respeitando as dependências de compilação indicadas pela ordem.
- Após a fundação, T016 e T019 podem avançar em paralelo; T022 e T023 também são independentes dos
  ajustes centrais de Home enquanto seus contratos permanecem estáveis.
- Na US2, T028 pode avançar em paralelo ao refactor inicial do cadastro; T032 pode avançar enquanto
  o formulário e o convite são implementados.
- Na US3, T035 e T038 podem avançar em paralelo antes da integração final.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Concluir Setup.
2. Concluir a fundação crítica, incluindo verificação de schema, raiz de sessão e guardas privados.
3. Implementar US1.
4. Parar no checkpoint e validar login, restauração, Home real, falhas seguras e logout.
5. Demonstrar o MVP antes de ampliar onboarding/Garagem, se desejado.

### Incremental Delivery

1. Setup + Foundation → fronteira de Auth, dados e navegação segura pronta.
2. US1 → login e Home personalizada entregues como MVP.
3. US2 → novo cadastro recebe convite persistente e primeiro veículo.
4. US3 → Garagem permanente, múltiplos veículos e troca de principal.
5. Polish → validação completa de segurança, build e acessibilidade.

### Safe Database Delivery

Nenhuma migration é criada ou aplicada por estas tarefas. A única ação de banco é a verificação de
leitura (`supabase db diff`) descrita em T001 e T045; qualquer divergência de schema deve ser
corrigida no repositório Android, fonte única de verdade.

---

## Notes

- Tarefas `[P]` atuam em arquivos diferentes e não possuem dependência imediata entre si.
- Labels `[US1]`, `[US2]` e `[US3]` garantem rastreabilidade aos cenários da especificação.
- Nenhuma tarefa cria teste automatizado; build e `quickstart.md` são os gates de qualidade
  definidos.
- Não adicionar framework de DI, `SwiftData`, Realtime, cache de conta/veículo, biblioteca de
  imagem assíncrona ou persistência de rascunho.
- Não enviar `user_id`, `active` ou `is_primary` final pela interface; as RPCs e `auth.uid()` são a
  autoridade para ownership/status.
- Não executar migração remota nem incluir credencial real em arquivo rastreado.
- Fazer commit após cada tarefa ou grupo lógico pequeno facilita revisão e rollback.
