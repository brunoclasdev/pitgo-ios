---
description: "Implementation tasks for the mocked PitTec UI experience (iOS)"
---

# Tasks: Experiência mockada de UI do PitTec (iOS)

**Input**: Design documents from `specs/017-pittec-mocked-ui/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup & Isolation (Shared Infrastructure)

- [ ] T001 Isolar o wiring real de `013`/`015` em `PitGoRootView`: rota cliente PitTec não cria
  `PitTecRepository`/`DispatchResumeCoordinator`; providers `.pittec` não instanciam
  `ProviderDashboardViewModel` real, em `pitgo/Core/Navigation/PitGoRootView.swift`
- [ ] T002 [P] Restringir `ProviderLocationTracker` real (`009`/`013`) a iniciar tracking somente
  para `.mobile`, e implementar uma parada puramente local (sem RPC) para tracking PitTec legado em
  `pitgo/Features/ProviderTracking/ProviderLocationTracker.swift`
- [ ] T003 [P] Criar `PitTecMockModels.swift` com `MockParticipant`, `DistancePerimeter`,
  `ServiceEstimate`, `MockLocationSnapshot`, fixtures (`.progressiveSuccess`, `.noProvider`,
  `.providerIncoming`) em `pitgo/Features/PitTec/Model/PitTecMockModels.swift`

**Checkpoint**: fluxo real isolado; modelos/fixtures mockados prontos.

---

## Phase 2: User Story 2 - Conferir e confirmar a estimativa antes da busca (Priority: P1) 🎯 MVP

**Independent Test**: A partir do card PitTec atual, tocar "Buscar PitTec" e validar estimativas
nos perímetros simulados de 5km, 10km e 15km.

### Implementation

- [ ] T004 [US2] Criar `MockSearch`, `MockSearchFeedback`, `PitTecClientMockStage` em
  `pitgo/Features/PitTec/Model/PitTecMockModels.swift`
- [ ] T005 [US2] Implementar `PitTecClientMockViewModel` (`@Observable`) com estágios
  `.discovery`/`.estimating`/`.awaitingClientConfirmation`/`.searching`/`.noProvider`, guarda
  síncrona contra toque duplo e busca sequencial com expansão de perímetro em
  `pitgo/Features/PitTec/ViewModel/PitTecClientMockViewModel.swift`
- [ ] T006 [US2] Estender `PitTecView` (preservando a apresentação inicial de `015`) com o card de
  estimativa, feedback de busca e estado vazio em `pitgo/Features/PitTec/Views/PitTecView.swift`
- [ ] T007 [US2] Executar os cenários de estimativa/busca descritos em
  `specs/017-pittec-mocked-ui/quickstart.md §3`

**Checkpoint**: MVP — cliente confirma estimativa e acompanha busca sequencial simulada.

---

## Phase 3: User Story 3 - Acompanhar o encontro no mapa (Priority: P1)

**Independent Test**: Iniciar diretamente um cenário aceito com posições simuladas e observar o
enquadramento, as informações do card e pelo menos duas atualizações da posição do PitTec.

### Implementation

- [ ] T008 [US3] Criar `MockAppointment`, `MockAppointmentStatus`, `ParticipantConfirmation` em
  `pitgo/Features/PitTec/Model/PitTecMockModels.swift`
- [ ] T009 [US3] Implementar a timeline de posição (30s por passo, stale em 35s, sem comando de
  câmera automático) compartilhada por cliente/provider em
  `pitgo/Features/PitTec/ViewModel/PitTecClientMockViewModel.swift` e
  `pitgo/Features/PitTec/ViewModel/PitTecProviderMockViewModel.swift`
- [ ] T010 [US3] Criar `PitTecMockTrackingContent` reutilizando `MapLibreMapHost`/`Coordinator` de
  participantes (`010`/`014`) com enquadramento inicial e ação "Centralizar" em
  `pitgo/Features/PitTec/Views/PitTecMockTrackingContent.swift`
- [ ] T011 [US3] Executar os cenários de acompanhamento descritos em
  `specs/017-pittec-mocked-ui/quickstart.md §4`

---

## Phase 4: User Story 4 - Confirmar encontro e conclusão pelos dois participantes (Priority: P1)

**Independent Test**: Em qualquer perfil, confirmar a ação local e verificar que o estado aguarda
3s pela resposta automática simulada da outra pessoa antes de avançar.

### Implementation

- [ ] T012 [US4] Implementar `onMeetingConfirmed()`/`onCompletionConfirmed()` com guarda de
  idempotência, `Task` de 3s por token de revisão, em
  `pitgo/Features/PitTec/ViewModel/PitTecClientMockViewModel.swift` e
  `pitgo/Features/PitTec/ViewModel/PitTecProviderMockViewModel.swift`
- [ ] T013 [US4] Renderizar os textos "Aguardando confirmação da outra pessoa" e as transições de
  status no card compartilhado em
  `pitgo/Features/PitTec/Views/PitTecMockTrackingContent.swift`
- [ ] T014 [US4] Executar os cenários de confirmação bilateral descritos em
  `specs/017-pittec-mocked-ui/quickstart.md §5`

---

## Phase 5: User Story 1 - Receber e responder a uma chamada na Home PitTec (Priority: P1)

**Independent Test**: Abrir a Home do PitTec em um cenário simulado, disparar uma solicitação e
verificar mapa, alerta roxo, informações essenciais e as ações "Aceitar"/"Recusar".

### Implementation

- [ ] T015 [US1] Implementar `ProviderLocationGate` (`.checkingPermission`...`.ready`) usando
  `DeviceLocationRepository` (`009`) em
  `pitgo/Features/PitTec/ViewModel/PitTecProviderMockViewModel.swift`
- [ ] T016 [US1] Criar `MockServiceRequest`, geração de solicitação e o pulso roxo (3 ciclos,
  consumido uma vez, respeitando `UIAccessibility.isReduceMotionEnabled`) em
  `pitgo/Features/PitTec/ViewModel/PitTecProviderMockViewModel.swift`
- [ ] T017 [US1] Criar a Home mockada do provider com gate de localização, card roxo persistente e
  ações Aceitar/Recusar em `pitgo/Features/PitTec/Views/PitTecProviderMockView.swift`
- [ ] T018 [US1] Executar os cenários de Home/alerta descritos em
  `specs/017-pittec-mocked-ui/quickstart.md §2`

---

## Phase 6: User Story 5 - Navegar pelas áreas do PitTec (Priority: P2)

**Independent Test**: Acessar cada opção da navegação inferior como PitTec e comparar sua estrutura
visual com a navegação dos demais perfis.

### Implementation

- [ ] T019 [US5] Criar `PitTecProviderTabs` (Mapa/Dados da corrida/Valores/Perfil) reutilizando o
  componente visual de `PitGoBottomTabs` (`002`) em
  `pitgo/Core/UI/PitGoBottomTabs.swift`
- [ ] T020 [US5] Implementar as abas "Dados da corrida" e "Valores" derivando de
  `currentOrLastAppointment`, com estado vazio antes do primeiro aceite, em
  `pitgo/Features/PitTec/Views/PitTecProviderMockView.swift`
- [ ] T021 [US5] Implementar a aba "Perfil" com dados básicos do `AccountSnapshot` e logout
- [ ] T022 [US5] Executar os cenários de navegação descritos em
  `specs/017-pittec-mocked-ui/quickstart.md §6`

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T023 Executar `xcodebuild clean build` conforme `specs/017-pittec-mocked-ui/quickstart.md`
- [ ] T024 Revisar Dynamic Type grande, landscape, VoiceOver e redução de movimento em todas as
  Views de `pitgo/Features/PitTec/`
- [ ] T025 Inspecionar tráfego de rede para confirmar ausência de chamadas às RPCs/Edge Function
  reais de `013`/`015` durante todo o roteiro, conforme
  `specs/017-pittec-mocked-ui/quickstart.md §7`
- [ ] T026 Confirmar que FIXED/MOBILE (Dashboard real) não regrediram, conforme
  `specs/017-pittec-mocked-ui/plan.md`

---

## Dependencies & Execution Order

```text
Setup → US2 (MVP) → US3 → US4 → US1 → US5 → Polish
```

- **US2** entrega o fluxo de estimativa/busca do cliente, base para **US3**/**US4** (acompanhamento
  e confirmações).
- **US1** (Home do provider) pode ser desenvolvida em paralelo a US2/US3/US4 após o Setup.
- **US5** depende de US1 (shell do provider já existente).

### Parallel Opportunities

- Setup: T002/T003 em paralelo.
- US3: T008 em paralelo com o restante da Phase 2.
- US1 e US2/US3/US4 podem ser desenvolvidas em paralelo por partes diferentes da equipe.

## Notes

- Nenhuma migration, RPC ou Edge Function é usada — feature inteiramente client-side e em memória.
- Nenhuma dependência nova é adicionada.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
