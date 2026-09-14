---

description: "Task list template for feature implementation"
---

# Tasks: Home do PitTec

**Input**: Design documents from `/specs/022-pittec-provider-home/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/pittec-provider-home-ui.md, quickstart.md

**Tests**: não solicitados explicitamente (regra V da constituição) — nenhuma task de teste automatizado incluída; validação por `quickstart.md`.

**Organization**: Tasks agrupadas por user story (US1 = P1, US2 = P2) para permitir implementação e teste independentes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência)
- **[Story]**: a qual user story a task pertence (US1, US2)
- Caminhos de arquivo exatos em cada descrição

## Path Conventions

Projeto único (Xcode app iOS). Todos os caminhos são relativos à raiz do repositório
(`/Users/brunocesar/projetos-mobile/ios/pitgo`), dentro de `pitgo/`.

---

## Phase 1: Setup

**Purpose**: Estrutura de pastas da nova feature

- [X] T001 Criar a estrutura de pastas `pitgo/Features/PitTecHome/{Model,Repository,ViewModel,Views}`, espelhando a organização já usada por `pitgo/Features/ProviderDashboard`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Casca da tela (TabView + roteamento) que as duas user stories precisam para serem testáveis — nenhuma delas pode ser validada isoladamente sem isto.

**⚠️ CRITICAL**: Nenhuma task de US1/US2 começa antes desta fase estar completa.

- [X] T002 [P] Criar `enum PitTecHomeTab: CaseIterable, Hashable` (casos: `map`, `ride`, `values`, `profile`) e `enum PitTecHomeUiState` (`.content(ProviderSnapshot)` / `.failure(ProviderDashboardFailureReason)`, reaproveitando o `ProviderDashboardFailureReason` já existente) em `pitgo/Features/PitTecHome/Model/PitTecHomeModels.swift`
- [X] T003 Generalizar `pitgo/Core/UI/PitGoBottomTabs.swift`: extrair um protocolo (`title: LocalizedStringResource`, `symbolName: String`, `CaseIterable & Hashable`) e tornar `PitGoBottomTabs` genérico sobre esse protocolo em vez de fixo em `BottomItemID`; fazer `BottomItemID` conformar ao protocolo sem mudar nenhum comportamento visível do `TabView` do cliente
- [X] T004 Criar `PitTecHomeViewModel` em `pitgo/Features/PitTecHome/ViewModel/PitTecHomeViewModel.swift` com `@Observable`/`@MainActor`, estado inicial `.content(snapshot)`, `selectedTab: PitTecHomeTab = .map`, e inicializador recebendo `ProviderDashboardRepository`, `PitTecRepository`, `DeviceLocationRepository` e um `ProviderDiscoveryTracker` (mesmas dependências já injetadas em `ProviderDashboardViewModel`)
- [X] T005 Criar `PitTecHomeView.swift` em `pitgo/Features/PitTecHome/Views/PitTecHomeView.swift`: `NavigationStack` + `PitGoBottomTabs<PitTecHomeTab, _>` selecionando `viewModel.selectedTab`, com as 4 abas renderizando `PlaceholderTabContent` temporariamente (conteúdo real vem nas fases seguintes)
- [X] T006 Atualizar `pitgo/Core/Navigation/PitGoRootView.swift`: no `case let .authenticatedProviderReady(snapshot)`, instanciar `PitTecHomeView` (com as mesmas dependências já montadas ali) quando `snapshot.provider.locationMode == .pittec`; manter `ProviderDashboardView` para `.fixed`/`.mobile` exatamente como hoje

**Checkpoint**: abrir o app com uma conta PitTec mostra a `TabView` de 4 abas (ainda com placeholders); uma conta Fixo/Móvel continua vendo a `ProviderDashboardView` de sempre.

---

## Phase 3: User Story 1 - Ver minha posição e disponibilidade de relance (Priority: P1) 🎯 MVP

**Goal**: Ao abrir a home do PitTec, ver o mapa centralizado na posição atual (atualizada periodicamente) e um card de disponibilidade tocável no topo, sem nenhuma outra ação.

**Independent Test**: Abrir o app logado como PitTec e verificar que o mapa aparece centralizado na posição do dispositivo e que o card de disponibilidade reflete e permite alternar o estado real — conforme `quickstart.md` Cenário 1.

### Implementation for User Story 1

- [X] T007 [US1] Expor o último `DeviceLocationFix` recebido como `private(set) var lastFix: DeviceLocationFix?` em `pitgo/Features/MobileDispatch/ProviderDiscoveryTracker.swift`, atualizado dentro de `handle(fix:)` antes do envelope de publicação (sem alterar o comportamento de publicação existente)
- [X] T008 [US1] Em `PitTecHomeViewModel` (`pitgo/Features/PitTecHome/ViewModel/PitTecHomeViewModel.swift`), reaproveitar a mesma lógica de `ProviderDashboardViewModel.syncTracker()`/`setAvailability(_:)` para iniciar/parar o `ProviderDiscoveryTracker` conforme `provider.active && provider.available` e expor `discoveryTracker` para a View observar `lastFix`/`state`
- [X] T009 [P] [US1] Criar `pitgo/Features/PitTecHome/Views/PitTecHomeMapTab.swift` com `PitGoMapView` centralizado em `viewModel.discoveryTracker.lastFix` (`showsUserLocation: true`), mostrando a mensagem de estado degradado (reaproveitando o texto de `ProviderDashboardView.discoveryDegradedMessage`/`TrackingDegradedReason`) no lugar do mapa quando não houver fix e nenhum fix anterior
- [X] T010 [US1] No mesmo arquivo, adicionar o card de disponibilidade fixo no topo (`"Disponível"`/`"Indisponível"`, tocável, chamando `viewModel.setAvailability(_:)`), revertendo visualmente e mostrando erro (mesmo texto de `ProviderDashboardView.message(for:)`) se a chamada falhar
- [X] T011 [US1] Em `PitTecHomeView.swift`, substituir o placeholder da aba `.map` por `PitTecHomeMapTab`

**Checkpoint**: US1 completa e testável isoladamente (Cenário 1 do `quickstart.md`).

---

## Phase 4: User Story 2 - Navegar entre mapa, corrida ativa, valores e perfil (Priority: P2)

**Goal**: As outras 3 abas (Dados da corrida, Valores, Perfil) mostram conteúdo real, e uma solicitação nova continua avisando o PitTec independentemente da aba aberta.

**Independent Test**: Com a home aberta, tocar em cada uma das 4 abas e confirmar o conteúdo esperado; disparar uma solicitação nova a partir de outra aba e confirmar que a tela de aceitar/recusar abre normalmente — conforme `quickstart.md` Cenários 2 e 3.

### Implementation for User Story 2

- [X] T012 [P] [US2] Criar `pitgo/Features/PitTecHome/Repository/PitTecPricingRepository.swift`: leitura somente-consulta de `provider_services` (join com `services` por `dispatch_kind = PITTEC_AUTO_SEQUENTIAL`) filtrado pelo `provider_id` atual, mesmo padrão de `ProviderRegistrationRepository.fetchOwnAggregate`/`fetchImplicitService`
- [X] T013 [P] [US2] Criar `pitgo/Features/PitTecHome/Model/PitTecHomeModels.swift` → adicionar `struct PitTecPricingInfo` (`price: Decimal`, `serviceName: String`) e `enum PitTecPricingLoadState` (`.loading`/`.loaded(PitTecPricingInfo)`/`.failure`)
- [X] T014 [US2] Em `PitTecHomeViewModel`, carregar o preço via `PitTecPricingRepository` ao entrar na aba "Valores" (ou eagerly no `onAppear`, reaproveitando o mesmo carregamento) e expor `pricingState: PitTecPricingLoadState`
- [X] T015 [P] [US2] Criar `pitgo/Features/PitTecHome/Views/PitTecHomeValuesTab.swift` mostrando `viewModel.pricingState` (preço formatado, somente leitura — sem nenhum campo editável, conforme clarificação do spec.md)
- [X] T016 [P] [US2] Criar `pitgo/Features/PitTecHome/Views/PitTecHomeRideTab.swift` mostrando um resumo do atendimento PitTec ativo (`AWAITING_CLIENT_CONFIRMATION`/`AWAITING_PAYMENT`/`ACCEPTED`/`IN_PROGRESS`) ou a mensagem vazia quando não houver nenhum
- [X] T017 [US2] Em `PitTecHomeViewModel`, reaproveitar `PitTecRepository.getActiveDispatch()` (mesmo padrão de `ProviderDashboardViewModel.checkPitTecIncoming`) para alimentar o resumo de `PitTecHomeRideTab`, ignorando o status `PENDING` aqui (esse continua indo para o push automático existente)
- [X] T018 [P] [US2] Criar `pitgo/Features/PitTecHome/Views/PitTecHomeProfileTab.swift` mostrando nome/e-mail do `ProviderSnapshot` e um botão "Sair" com `confirmationDialog`, reaproveitando o texto/padrão de `ProviderDashboardView.signOutButton`
- [X] T019 [US2] Passar `onSignOut: () -> Void` para `PitTecHomeView`/`PitTecHomeViewModel` (mesmo padrão de `ProviderDashboardView`) e conectar ao botão criado em T018
- [X] T020 [US2] Em `PitTecHomeViewModel`, reaproveitar o mesmo par `subscribeToProvider`/`getActiveDispatch` de `PitTecRepository` já usado em `ProviderDashboardViewModel.onAppear`/`checkPitTecIncoming` para detectar uma solicitação `PENDING` nova e expor um sinal (`pitTecAppointmentToOpen`) que `PitTecHomeView` usa para empurrar `PitTecIncomingRequestView` na `NavigationStack`, independentemente da aba selecionada
- [X] T021 [US2] Em `PitTecHomeView.swift`, substituir os placeholders das abas `.ride`, `.values` e `.profile` pelas Views criadas em T016/T015/T018

**Checkpoint**: as 4 abas funcionam de ponta a ponta (Cenários 2 e 3 do `quickstart.md`).

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Validação final e checagem de não-regressão

- [X] T022 [P] Rodar `xcodebuild -project pitgo.xcodeproj -scheme pitgo build` e corrigir quaisquer erros de compilação
- [ ] T023 Validar manualmente os 4 cenários de `quickstart.md` (US1, US2, notificação cruzando abas, e Fixo/Móvel inalterados — Cenário 4/FR-012)
- [X] T024 [P] Revisar o código gerado contra a constituição: nomes claros, sem `Bool`s paralelos para estado mutuamente exclusivo, Views sem lógica de negócio, `PitGoBottomTabs` generalizado sem quebrar o `TabView` do cliente

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sem dependências
- **Foundational (Phase 2)**: depende do Setup — bloqueia US1 e US2
- **US1 (Phase 3)**: depende só do Foundational
- **US2 (Phase 4)**: depende só do Foundational (não depende de US1 estar "pronta", mas compartilha o mesmo `PitTecHomeView.swift`/`PitTecHomeViewModel.swift` editados por T011 — ver nota de conflito de arquivo abaixo)
- **Polish (Phase 5)**: depende de US1 e US2 completas

### Nota sobre conflito de arquivo entre US1 e US2

`PitTecHomeView.swift` e `PitTecHomeViewModel.swift` são editados tanto em US1 (T008, T011) quanto
em US2 (T014, T017, T019, T020, T021) — não são arquivos exclusivos de uma story. Se as duas
stories forem trabalhadas em paralelo por pessoas diferentes, tratar essas tasks como
sequenciais nesses dois arquivos (US1 primeiro, já que é P1), mesmo que o restante de cada story
(Views novas, Repository) seja paralelizável.

### Parallel Opportunities

- T002 e T003 (Foundational) podem rodar em paralelo — arquivos diferentes
- Dentro de US1: T007 e T009 podem rodar em paralelo (arquivos diferentes); T010 depende de T009 (mesmo arquivo)
- Dentro de US2: T012, T015, T016, T018 podem rodar em paralelo entre si (arquivos diferentes); T013 pode rodar junto por estar no mesmo `PitTecHomeModels.swift` de T002 mas em bloco distinto
- T022 e T024 (Polish) podem rodar em paralelo com T023

---

## Parallel Example: User Story 2

```bash
# Repository + as 3 Views de conteúdo, em paralelo (arquivos distintos):
Task: "Criar PitTecPricingRepository.swift"
Task: "Criar PitTecHomeValuesTab.swift"
Task: "Criar PitTecHomeRideTab.swift"
Task: "Criar PitTecHomeProfileTab.swift"

# Depois, sequencial no mesmo arquivo (PitTecHomeViewModel/PitTecHomeView):
Task: "Wire pricing/ride/sign-out/incoming request no ViewModel e na View"
```

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1 (Setup)
2. Completar Phase 2 (Foundational) — bloqueia tudo
3. Completar Phase 3 (US1)
4. **Parar e validar**: Cenário 1 do `quickstart.md` isoladamente
5. Demonstrar/entregar se for suficiente para essa entrega

### Incremental Delivery

1. Setup + Foundational → casca com 4 abas placeholder
2. US1 → mapa + disponibilidade funcionando (MVP demonstrável)
3. US2 → as outras 3 abas + notificação cruzando abas
4. Polish → build limpo + validação manual completa
