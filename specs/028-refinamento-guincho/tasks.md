---
description: "Tarefas do porte iOS do refinamento de Guincho"
---

# Tasks: Refinamento do fluxo de Guincho (porte iOS)

**Tests**: build dos três schemes via `xcodebuild`; sem suíte automatizada nova.

## Phase 1: Modelo compartilhado (`MobileDispatch`)

- [X] T001 Adicionar `MobileDispatchKind` (`MOBILE_SEQUENTIAL`/`PITTEC_AUTO_SEQUENTIAL`/
  `GUINCHO_DIRECT`), `AWAITING_CLIENT_COMPLETION_CONFIRMATION`/`DISPUTED` em `ServiceSearchStatus`/
  `AppointmentStatus`, `ARRIVE`/`START`/`CONFIRM_COMPLETION`/`DISPUTE` em `DispatchAction`,
  `.arrive`/`.confirmCompletion`/`.dispute(reason:)` em `DispatchActionKind` —
  `pitgo/Features/MobileDispatch/Model/MobileDispatchModels.swift`.
- [X] T002 Estender `DispatchAppointment` (`arrivedAt`/`serviceStartedAt`/`completionRequestedAt`/
  `clientCompletionConfirmedAt`/`quoteVersion`, decodificação dual-campo do `quote` aninhado) e
  `MobileDispatchSnapshot` (`dispatchKind`/`trackingAuthorized`/`guinchoTrip`/`guinchoDispute`/
  `providerName`) no mesmo arquivo do T001.
- [X] T003 [P] Criar `pitgo/Features/Guincho/Model/GuinchoDTOs.swift` (`GuinchoTripDTO`/
  `GuinchoVehicleDTO`/`GuinchoDisputeDTO`, reaproveitados por T002).

## Phase 2: Etapa pré-pagamento (novo — `Features/Guincho`)

- [X] T004 [P] Criar `pitgo/Features/Guincho/Model/GuinchoModels.swift` (draft, provider, quote,
  sugestão de endereço, `GuinchoOutcome`, `GuinchoPaymentContext`).
- [X] T005 Criar `pitgo/Features/Guincho/Repository/GuinchoRepository.swift`
  (`saveTrip`/`discover`/`quote`/`reserve`, RPCs/Edge Function já implantadas).
- [X] T006 [P] Criar `pitgo/Features/Guincho/Repository/GuinchoAddressRepository.swift` (Edge
  Function `guincho-address-search` + `CLGeocoder` como complemento de melhor esforço).
- [X] T007 Criar `pitgo/Features/Guincho/ViewModel/GuinchoMapViewModel.swift` (estágios
  pickup→destination→confirm→discovery, descoberta a cada 5s, cotação por seleção).
- [X] T008 Criar `pitgo/Features/Guincho/Views/GuinchoMapView.swift` (mapa + card inferior por
  estágio, reaproveitando `PitGoMapView`).

## Phase 3: Pós-aceite (estender `MobileDispatch`/`Payment`)

- [X] T009 Adicionar `StartGuinchoTransportParams`/`ArriveGuinchoAppointmentParams`/
  `DisputeGuinchoCompletionParams` e os métodos `startGuinchoTransport`/`arriveGuincho`/
  `confirmCompletion`/`disputeCompletion` em `MobileDispatchRepository.swift`.
- [X] T010 [P] Adicionar `arrive()`/`startTransport()` a `ProviderIncomingRequestViewModel.swift`;
  rotear `.accepted/.inProgress/.awaitingClientCompletionConfirmation/.disputed` para `.reserved`.
- [X] T011 Adicionar `guinchoReservedState` a `ProviderIncomingRequestView.swift` (remuneração só do
  guincheiro, chegada/início/conclusão/contestação); `startedAppointmentID` nunca navega para
  `ProviderTrackingView` quando `dispatchKind == .guinchoDirect`.
- [X] T012 [P] Adicionar `confirmCompletion()`/`dispute(reason:)`/`guinchoPaymentContext` a
  `ClientMobileDispatchViewModel.swift`.
- [X] T013 Adicionar `guinchoAwaitingPaymentState`/`guinchoAcceptedState`/`guinchoDisputedState`/
  `guinchoDisputeSheet` a `ClientMobileDispatchView.swift`; `.sheet(item:)` ligado a
  `guinchoPaymentContext` para abrir `PaymentCheckoutView(dispatchKind: .guinchoDirect)`;
  `acceptedAppointmentID` nunca navega para `AppointmentTrackingView` quando Guincho.
- [X] T014 [P] Adicionar `.guinchoDirect` a `PaymentDispatchKind`; `GuinchoPaymentContext` em
  `PaymentCheckoutViewModel.swift`/`PaymentCheckoutView.swift`.
- [X] T015 Estender `SimulatedPaymentGateway.swift`: `GUINCHO_DIRECT` delega ao backend real via
  `simulate_guincho_payment` (migration `20260930145000_guincho_dev_simulation.sql`, mesma do
  Android) em vez de simular em memória — mesmo em Dev, o pagamento Guincho é uma linha real.
- [X] T016 Corrigir `DispatchResumeCoordinator`/`ProviderDashboardViewModel.checkIncoming()` para
  nunca resolver Guincho para as telas genéricas de tracking (`AppointmentTrackingView`/
  `ProviderTrackingView`).

## Phase 4: Navegação

- [X] T017 Adicionar `PitGoRoute.guincho(serviceID:)`; repontar o card de Guincho da Home
  (`dispatchKind == .mobileSequential`) de `.mobileDispatchNewSearch` para `.guincho`;
  `GuinchoMapView.onContract` empurra `.mobileDispatchSearch(searchID:)` (reaproveita a retomada já
  existente de `013`); adicionar `.guincho` aos switches exaustivos de `PitGoRoute` em
  `PitTecHomeView`/`ProfileView`/`ProviderDashboardView`.

## Phase 5: Validação

- [X] T018 Build do scheme `pitgo` (Dev) — `** BUILD SUCCEEDED **` após 8 rodadas de correção
  (isolamento de ator por `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`, `Sendable` em genéricos,
  `CoreLocation` ausente, switches não-exaustivos por novos casos de enum).
- [X] T019 Build dos schemes `pitgo-Homol`/`pitgo-Prod` — ambos `** BUILD SUCCEEDED **`.
- [ ] T020 Validação funcional manual: escolher retirada/destino/veículo, selecionar guincheiro,
  contratar, aceitar/recusar do lado prestador, pagar, chegar/iniciar/concluir, confirmar/contestar.
  Pendente de sessão manual do usuário (duas contas — cliente e prestador Móvel).
- [X] T021 Corrigir `PitGoMapView.Coordinator.regionDidChangeAnimated` para notificar consumidores
  somente quando pan/zoom manual foi detectado; movimentos programáticos não podem disparar
  reverse-geocoding nem substituir o endereço digitado no destino de `GuinchoMapView`.
- [X] T022 Restringir a área de hit-testing do `ScrollView` do cartão inferior e guardar centro/zoom
  após gestos manuais para que o painel não bloqueie pan/zoom nem recoloque a câmera no zoom padrão.

## Coverage

Cobre FR-001–FR-021, FR-023 (visualização apenas) e SC-001–SC-003, SC-005–SC-008 do `spec.md`
original. FR-022 (resolução de contestação) e SC-004 dependem do dashboard web, fora do escopo deste
porte (ver "Ajustes de escopo" em `spec.md`). GPS ao vivo do guincheiro, vistoria fotográfica e
avaliação ficam para as specs 029-034, ainda não portadas.
