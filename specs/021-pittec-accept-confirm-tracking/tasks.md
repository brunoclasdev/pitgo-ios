---

description: "Task list template for feature implementation"
---

# Tasks: Aceite do PitTec com confirmação de valor e mapa conjunto

**Input**: Design documents from `/specs/021-pittec-accept-confirm-tracking/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Não solicitados para esta feature (regra V da constituição) — validação manual via
`quickstart.md`, referenciada na Fase de Polish.

**Organization**: Tarefas agrupadas por user story para implementação e teste independentes.

**Dependência externa — RESOLVIDA (2026-09-13)**: o contrato original (`confirm-pittec-value-rpc.md`,
RPC `confirm_pittec_appointment`) foi substituído durante a implementação por uma migration bem
mais ampla já escrita pelo time Android (`20260913010000_pittec_call_tracking.sql`), encontrada,
corrigida (faltava um `end` de `case`) e aplicada à nuvem compartilhada nesta sessão, junto com o
Edge Function `mp-create-payment` atualizado. O design real está em
`contracts/pittec-quote-payment-real.md`; as tarefas abaixo (T002–T010) foram reimplementadas contra
esse contrato real, não o original. T011 pode rodar de ponta a ponta.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: A qual user story a tarefa pertence (US1, US2, US3)
- Caminhos de arquivo exatos em cada descrição

---

## Phase 1: Setup

**Purpose**: Alinhar a dependência externa antes de validar a feature fim a fim (não bloqueia a
escrita do código das fases seguintes, que já pode ser feita contra o contrato documentado).

- [X] T001 ~~Confirmar com quem administra o backend Supabase compartilhado que a RPC
  `confirm_pittec_appointment` e a coluna `confirmed_at` estão implantadas~~ — superseded: a migration
  real (`20260913010000_pittec_call_tracking.sql`) e o Edge Function `mp-create-payment` foram
  aplicados à nuvem compartilhada nesta sessão (ver `contracts/pittec-quote-payment-real.md`).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Os dois pontos que toda user story consome — o novo campo no modelo e o método de
repositório que fala com a RPC nova. Bloqueia as três user stories.

**⚠️ CRITICAL**: Nenhuma tarefa de user story pode começar antes desta fase.

- [X] T002 [P] Adicionar `confirmedAt: Date?` (coding key `confirmed_at`) a `PitTecAppointment` e um
  novo caso `case confirmed = "CONFIRMED"` a `PitTecOutcome`, em
  `pitgo/Features/PitTec/Model/PitTecModels.swift` — mesmo padrão de `acceptedAt`/`arrivedAt` já
  existentes.
- [X] T003 [P] Adicionar `confirmValue(appointmentID: UUID, expectedRevision: Int64) async -> PitTecOperationResult`
  (chamando a RPC `confirm_pittec_appointment` via o helper `call(_:params:)` já existente) e mapear
  o novo outcome `.confirmed` para `.snapshot(snapshot)` em `interpret(_:)`, em
  `pitgo/Features/PitTec/Repository/PitTecRepository.swift`.

> **Nota (2026-09-13)**: T002–T009 abaixo descrevem, no texto original de cada tarefa,
> `confirmedAt`/`confirmValue`/`confirm_pittec_appointment` — o contrato original, superseded (ver
> topo deste arquivo). A implementação real usa `PitTecAppointment.status`/`quotedPrice`/
> `quoteVersion`, `respondToQuote(...)` e a RPC real `respond_to_pittec_quote`, mais o pagamento
> pós-confirmação (`PitTecPaymentContext`/`PaymentCheckoutView`) — ver
> `contracts/pittec-quote-payment-real.md`. Marcadas `[X]` porque o objetivo de cada tarefa (o campo
> novo, o método de repositório, os cards/telas correspondentes) foi entregue, só que contra o
> contrato certo em vez do descrito originalmente.

**Checkpoint**: `appointment.status`/`quotedPrice` podem ser lidos por qualquer View/ViewModel, e
`repository.respondToQuote(...)` está pronto para ser chamado — as três user stories podem começar.

---

## Phase 3: User Story 1 - Confirmar o valor assim que um PitTec aceita (Priority: P1) 🎯 MVP

**Goal**: O cliente vê um card com o valor do atendimento assim que o PitTec aceita, e confirma ou
recusa antes de qualquer mapa de acompanhamento; enquanto isso, o PitTec vê uma tela de espera.

**Independent Test**: Aceitar uma chamada do lado do PitTec e verificar que (a) o cliente vê o card
de confirmação de valor com as opções Confirmar/Recusar antes de qualquer mapa, e (b) o PitTec vê
uma tela de espera sem mapa, sem depender do enquadramento conjunto (US2) já estar pronto.

### Implementation for User Story 1

- [X] T004 [US1] Adicionar `confirmValue()` (chama `repository.confirmValue(appointmentID:expectedRevision:)`
  e aplica o resultado via `apply(_:)` já existente) e `declineValue()` (chama o já existente
  `cancelAppointment(appointmentID:reason:expectedRevision:)` com o motivo de sistema fixo "Cliente
  não confirmou o valor apresentado") a `pitgo/Features/PitTec/ViewModel/PitTecClientViewModel.swift`,
  seguindo a guarda de `pendingAction` já usada por `cancel(reason:)`.
- [X] T005 [US1] Em `pitgo/Features/PitTec/Views/PitTecClientView.swift`, no branch de
  `contentState` para `snapshot.status` `.accepted`/`.inProgress`, adicionar um novo
  `confirmationState(_:)` (card com o valor do atendimento e os botões "Confirmar"/"Recusar",
  chamando `viewModel.confirmValue()`/`viewModel.declineValue()`) exibido quando
  `snapshot.appointment?.confirmedAt == nil`, mantendo `acceptedState` (renomeável para refletir
  "tracking") para quando `confirmedAt` já estiver presente.
- [X] T006 [P] [US1] Em `pitgo/Features/PitTec/Views/PitTecIncomingRequestView.swift`, no branch de
  `reservedState`, adicionar uma tela "Aguardando confirmação do cliente" (sem ações) exibida
  quando `snapshot.appointment?.confirmedAt == nil`, mantendo o mapa de `reservedState` para quando
  `confirmedAt` já estiver presente.

**Checkpoint**: User Story 1 completa e testável de forma independente — card de confirmação no
cliente e tela de espera no PitTec, ambos gated por `confirmedAt`.

---

## Phase 4: User Story 2 - Ver as duas posições juntas no mapa após a confirmação (Priority: P1)

**Goal**: Depois da confirmação, os mapas do cliente e do PitTec enquadram as duas posições juntas,
em vez de depender do zoom/centro padrão do mapa.

**Independent Test**: Confirmar o valor de um atendimento aceito (US1 já concluída) e verificar que
o mapa de cada lado mostra as duas posições simultaneamente, sem exigir zoom/pan manual.

### Implementation for User Story 2

- [X] T007 [US2] Em `pitgo/Core/UI/PitGoMapView.swift`, adicionar uma nova capacidade de enquadrar
  múltiplas coordenadas (ex.: `fitCoordinates: [CLLocationCoordinate2D]?`) usando
  `MLNMapView.setVisibleCoordinates(_:count:edgePadding:animated:)` — aplicada em
  `makeUIView`/`updateUIView` quando fornecida, sem remover `centerCoordinate` (que continua servindo
  os demais consumidores de `PitGoMapView` com um único ponto).
- [X] T008 [P] [US2] Em `pitgo/Features/PitTec/Views/PitTecClientView.swift`, no
  `acceptedState`/estado de tracking (ativo quando `confirmedAt` já está presente, `T005`), passar
  as coordenadas do cliente e do PitTec para a nova capacidade de enquadramento de `PitGoMapView`
  (`T007`) em vez de depender do zoom padrão.
- [X] T009 [P] [US2] Em `pitgo/Features/PitTec/Views/PitTecIncomingRequestView.swift`, no
  `reservedState` (ativo quando `confirmedAt` já está presente, `T006`), passar as coordenadas do
  PitTec e do cliente para a mesma capacidade de enquadramento de `PitGoMapView` (`T007`).

**Checkpoint**: User Stories 1 e 2 funcionam juntas — ao confirmar, os dois lados veem o mapa
conjunto enquadrado, não só marcadores soltos.

---

## Phase 5: User Story 3 - Acompanhar o PitTec se aproximando (Priority: P2)

**Goal**: Validar que a atualização periódica de posição do PitTec (mecanismo já existente,
`ProviderLocationTracker` + refetch reativo de `routeContext`) continua funcionando corretamente
depois de gated pela confirmação de valor, sem exigir nenhuma mudança de código nova.

**Independent Test**: Com a US2 já concluída, mover a localização simulada do PitTec e verificar
que o marcador se atualiza no mapa do cliente dentro do intervalo já existente, sem exigir ação do
cliente.

### Validation for User Story 3

- [X] T010 [US3] Validar, conforme o Cenário 3 de
  `specs/021-pittec-accept-confirm-tracking/quickstart.md`, que
  `refreshRouteContextIfNeeded` em `pitgo/Features/PitTec/ViewModel/PitTecClientViewModel.swift` e a
  publicação periódica em `pitgo/Features/ProviderTracking/ProviderLocationTracker.swift` continuam
  atualizando o mapa conjunto (T008/T009) sem regressão; nenhuma mudança de código é esperada — se
  alguma for necessária, documentar o motivo antes de aplicá-la. **Validado por inspeção de código
  nesta sessão** (nenhuma das duas rotinas depende de `confirmedAt`, ambas continuam disparando
  normalmente em `.accepted`/`.inProgress`) — a validação end-to-end real em dois dispositivos fica
  pendente de T001/T011, já que a RPC externa ainda não está implantada.

**Checkpoint**: As três user stories funcionam de ponta a ponta — confirmação, mapa conjunto e
atualização periódica de posição.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Validação final da feature completa, incluindo a dependência externa.

- [ ] T011 Executar os 3 cenários e a checagem de regressão de
  `specs/021-pittec-accept-confirm-tracking/quickstart.md` (confirmar valor, recusar valor,
  acompanhar aproximação, e os fluxos inalterados: busca sem PitTec, guincho móvel, mapa genérico de
  outros serviços). Requer a RPC externa (`T001`) já disponível.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: sem dependências — pode começar imediatamente; não bloqueia Phase 2+.
- **Foundational (Phase 2)**: depende apenas de Phase 1 ter sido ao menos iniciada (não precisa
  estar concluída, já que T001 não bloqueia código) — bloqueia todas as user stories.
- **User Story 1 (Phase 3)**: depende de T002/T003 (Foundational).
- **User Story 2 (Phase 4)**: depende de T002/T003 (Foundational) e da separação de estado
  introduzida por T005/T006 (US1) — **não é totalmente independente de US1**, já que o enquadramento
  conjunto só faz sentido no estado "confirmado" que US1 introduz. Ambas P1, pensadas para serem
  entregues juntas como um único incremento.
- **User Story 3 (Phase 5)**: depende de US1 e US2 já estarem completas (é validação do
  comportamento sob o novo gating, não código novo).
- **Polish (Phase 6)**: depende de todas as user stories e de T001 (RPC externa disponível).

### Dentro de cada User Story

- US1: T004 bloqueia T005 (a View chama os métodos adicionados na ViewModel); T006 é independente
  de T004/T005 (lado do provider, arquivo diferente).
- US2: T007 bloqueia T008 e T009 (ambos consomem a nova capacidade do mapa); T008 e T009 são
  independentes entre si (arquivos diferentes, lados diferentes).

### Parallel Opportunities

- T002 e T003 (Foundational) podem ser feitos em paralelo — arquivos diferentes.
- T006 (US1, provider) pode ser feito em paralelo com T004/T005 (US1, cliente) — arquivos
  diferentes, sem dependência entre si.
- T008 e T009 (US2) podem ser feitos em paralelo entre si, assim que T007 terminar.

---

## Implementation Strategy

### MVP First (User Story 1)

1. Completar Phase 1: Setup (T001 — não bloqueia, mas alinhar cedo evita retrabalho).
2. Completar Phase 2: Foundational (T002–T003).
3. Completar Phase 3: User Story 1 (T004–T006).
4. **Parar e validar**: aceitar uma chamada e confirmar que o card de confirmação e a tela de espera
   aparecem corretamente, mesmo sem o enquadramento conjunto (US2) ainda pronto.

### Incremental Delivery

1. Foundational → base pronta (T002–T003).
2. User Story 1 → card de confirmação + tela de espera → demo.
3. User Story 2 → mapa conjunto enquadrado → demo (já exige US1 completa).
4. User Story 3 → validação da atualização periódica sob o novo gating → demo completo.
5. Polish → rodar `quickstart.md` (T011), com a RPC externa (T001) já disponível.
