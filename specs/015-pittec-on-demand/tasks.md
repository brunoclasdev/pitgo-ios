---
description: "Implementation tasks for PitTec on-demand service (iOS)"
---

# Tasks: PitTec sob demanda (iOS)

**Input**: Design documents from `specs/015-pittec-on-demand/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

> **ACHADOS CRÍTICOS desta sessão** (via `pg_get_functiondef`/`supabase functions list` no projeto
> compartilhado, muito mais profundo que `db diff`):
> 1. `start_pittec_dispatch` exige um pagamento `APPROVED` prévio (`payments.request_id = p_request_id`)
>    — mesma dependência de `018-mercadopago-payments` já documentada em `013`, não citada em
>    `015 spec.md`/`contracts/`. Sem pagamento aprovado, nenhuma chamada PitTec inicia ponta a ponta.
> 2. A Edge Function `pittec-route` citada como "já existente" em `plan.md` **não está deployada**
>    (`supabase functions list` não a lista). `upsert_pittec_route_snapshot` nunca é chamada por
>    ninguém, então `get_pittec_route_snapshot` sempre retorna `NOT_FOUND`. O fallback de estimativa
>    direta (FR-023, já exigido pelo próprio spec) é o único caminho exercitável — implementado como
>    tal via `get_pittec_route_context` (duas posições correntes), nunca como exceção.
> 3. O formato real do snapshot PitTec (`private.pittec_dispatch_snapshot`) é estruturalmente
>    diferente do snapshot de guincho móvel (`013`): sem `candidate` visível ao cliente antes do
>    aceite, `offer` (distância arredondada a 500m + região) só visível ao provider quando
>    `PENDING`, `provider` só visível ao cliente a partir de `ACCEPTED`, e inclui `last_event`/
>    `last_event_at` (ausentes no snapshot de guincho). O modelo Swift foi desenhado a partir desse
>    formato real, não da prosa do contrato.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Verificado com `supabase link` + `pg_get_functiondef` de todas as ~12 RPCs PitTec +
  `supabase functions list` — schema e RPCs aplicados; Edge Function `pittec-route` **ausente**
  (achado crítico #2 acima)
- [ ] T002 [P] **Não feito** — nenhuma integração com `UserNotifications` foi implementada nesta
  sessão (autorização, categoria, agendamento). Ver racional em T027

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase estar concluída.

- [X] T003 [P] Estendido `ServiceDispatchKind`/`ProviderLocationMode` com `.pittecAutoSequential`/
  `.pittec` — **`pendingLocationMode` não foi implementado**: `setMode()` (`ProviderDashboardViewModel`)
  troca a modalidade imediatamente via RPC, sem adiar o efeito durante um atendimento ativo
  (FR-037 não coberto; o backend em si não expõe um campo de pendência confirmado nesta sessão)
- [X] T004 [P] Criado `PitTecDispatchSnapshot` e tipos correlatos em
  `pitgo/Features/PitTec/Model/PitTecModels.swift` — nomes adaptados ao formato real (`PitTecMarker`,
  `PitTecOfferAction`, `PitTecFailureReason` em vez de `NearbyPitTecMarker`/`PitTecAction`/
  `PitTecErrorCode`; `PitTecDispatchStatus` reaproveita `ServiceSearchStatus` de `013`, já idêntico)
- [ ] T005 [P] **Não feito como módulo separado**: sem Edge Function real para chamar (achado #2),
  não há um `Core/Routing` — a leitura de duas posições (`get_pittec_route_context`) e o fallback de
  linha reta vivem diretamente em `PitTecRepository.swift`/`PitGoMapView.swift` (`routeLine`)
- [ ] T006 **Não feito como generalização de `ProviderLocationTracker`**: `publish_mobile_provider_location`
  (`013`) já aceita `location_mode in ('MOBILE','PITTEC')` no servidor — `ProviderDiscoveryTracker`
  (`013`) é reaproveitado sem nenhuma mudança para publicar a posição PitTec. Disparo de notificação
  local não foi implementado (ver T002/T027)

**Checkpoint**: modelos e reaproveitamento do tracker de `013` prontos; notificações locais e
`RoutingRepository` dedicado ficam pendentes.

---

## Phase 3: User Story 5 - Cadastrar empresa como PitTec (Priority: P1, base de dados para as demais)

**Independent Test**: Cadastrar empresas em cada uma das três modalidades e confirmar que apenas a
opção PitTec, com os demais requisitos válidos, participa da descoberta e do despacho PitTec.

### Implementation

- [X] T007 [US5] Opção PitTec adicionada ao seletor de modalidade (Fixo/Móvel/PitTec) com descrição
  de cada uma em `pitgo/Features/ProviderRegistration/Views/ProviderRegistrationView.swift` — ver
  também `016` (oferta implícita, sem preço/duração para PitTec)
- [ ] T008 [US5] **Não feito** — ver T003 (`pendingLocationMode`)
- [ ] T009 [US5] **bloqueado neste ambiente** (interação manual); adicionalmente, cadastro real
  depende do bug pré-existente documentado em `016 tasks.md` (`create_provider_registration`)

---

## Phase 4: User Story 1 - Encontrar PitTecs próximos no mapa (Priority: P1)

**Independent Test**: Com PitTecs disponíveis e indisponíveis em distâncias conhecidas, abrir o
card PitTec e conferir quais marcadores aparecem e como os estados vazios são explicados.

### Implementation

- [X] T010 [US1] Implementado `listNearby` chamando `list_nearby_pittecs` (retorno de tabela, não
  jsonb — decodificado direto como `[PitTecMarker]`) em
  `pitgo/Features/PitTec/Repository/PitTecRepository.swift`
- [X] T011 [US1] Implementado `PitTecClientViewModel` com fix one-shot (`DeviceLocationRepository`,
  `009`), estados de loading/erro/vazio/retomada em
  `pitgo/Features/PitTec/ViewModel/PitTecClientViewModel.swift`
- [X] T012 [US1] Criado o mapa de descoberta com marcadores aproximados (ícone de chave de fenda,
  distinto do carro do guincho) e o CTA "Chamar PitTec" — **em `PitTecClientView.swift`, não um
  `PitTecMapView` separado**: usa `PitGoMapView` (`009`) em vez de `MapLibreMapHost` (`010`, nunca
  construído — mesma decisão de escopo já registrada em `010`/`013`), e a mesma View também cobre
  busca/proposta/acompanhamento (ver T017/T021 sobre a decisão de manter tudo autocontido)
- [X] T013 [US1] Card PitTec adicionado à Home, navegando para `PitGoRoute.pitTec(serviceID:)` via
  `dispatchKind` (`handleServiceTap` em `PitGoRootView.swift`)
- [ ] T014 [US1] **bloqueado neste ambiente** (interação manual)

---

## Phase 5: User Story 2 - Chamar automaticamente o PitTec mais próximo (Priority: P1)

**Independent Test**: Com três PitTecs elegíveis (recusa, sem resposta, aceita), confirmar a ordem
e os estados mostrados ao cliente.

### Implementation

- [X] T015 [US2] Implementado `startDispatch`/`cancelSearch`/`getActiveDispatch` chamando as três
  RPCs correspondentes em `pitgo/Features/PitTec/Repository/PitTecRepository.swift`
- [X] T016 [US2] Transições de estado do cliente implementadas com guarda síncrona (`pendingAction`)
  em `pitgo/Features/PitTec/ViewModel/PitTecClientViewModel.swift`
- [ ] T017 [US2] **Parcial**: "procurando"/"aguardando"/"cancelada"/"sem PitTec" têm estado dedicado;
  "recusado"/"expirado" aparecem como um aviso sobreposto ao estado "procurando" via
  `snapshot.recentNotice` (`last_event`), não como estados distintos do card; "iniciando" e
  "reconectando" não têm um estado textual próprio
- [ ] T018 [US2] **bloqueado neste ambiente** (interação manual, três contas PitTec); adicionalmente
  depende do pagamento aprovado (achado #1) para `start_pittec_dispatch` não falhar

---

## Phase 6: User Story 3 - Acompanhar a chegada do PitTec (Priority: P1)

**Independent Test**: Aceitar uma chamada e simular mudanças válidas na posição do PitTec,
verificando marcadores, distância, percurso e tratamentos de posição antiga/rota indisponível.

### Implementation

- [ ] T019 [US3] **Não feito como `RoutingRepository`**: não há Edge Function real para chamar
  (achado #2) — `PitTecRepository.routeContext(appointmentID:)` lê as duas posições correntes
  (`get_pittec_route_context`) diretamente, sem `Task` dedicado/conflating (cada `applySnapshot`
  dispara uma nova leitura; sem coalescing explícito de requisições concorrentes)
- [X] T020 [US3] Fallback de distância haversine (`CLLocation.distance(from:)`) + linha tracejada
  (`PitGoMapView.routeLine`, novo — `MLNShapeSource`/`MLNLineStyleLayer`) implementado em
  `PitTecClientView.swift`/`PitTecIncomingRequestView.swift` — como não há rota real (achado #2),
  este é o único caminho exercitado, sempre rotulado como estimativa, nunca como rota real
- [ ] T021 [US3] **Não feito como extensão de `AppointmentTracking`**: decisão de manter o
  acompanhamento PitTec autocontido em `PitTecClientView`/`PitTecIncomingRequestView` (mapa +
  distância + ações), em vez de estender `AppointmentTrackingViewModel`/`Repository` (`009`/`013`),
  que não conhece rota/distância PitTec e cuja extensão arriscaria o fluxo de guincho móvel já
  funcional; o aviso de posição desatualizada após 30s não foi implementado (o mapa sempre mostra a
  última leitura sem marcar explicitamente "desatualizado" — gap real, FR-025 não coberto)
- [X] T022 [US3] "Cheguei"/"Concluir" implementados via `arrive`/`completePitTec` em
  `pitgo/Features/PitTec/Repository/PitTecRepository.swift`
- [ ] T023 [US3] **bloqueado neste ambiente** (interação manual)

---

## Phase 7: User Story 4 - Receber e responder a uma chamada PitTec (Priority: P1)

**Independent Test**: Enviar uma oportunidade a uma conta PitTec disponível, confirmando exibição
dos dados essenciais e exercitando aceite, recusa e expiração, inclusive em background/tela
bloqueada.

### Implementation

- [X] T024 [US4] Implementado `respondPitTec` chamando `respond_to_mobile_dispatch` (compartilhada
  com `013`, retorna o snapshot no formato PitTec) em
  `pitgo/Features/PitTec/Repository/PitTecRepository.swift`
- [X] T025 [US4] Implementado como `PitTecIncomingRequestViewModel` (não `PitTecProviderViewModel`)
  com countdown local (tick de 1s, corrigido nesta sessão para realmente recompor a UI — ver `014`),
  guarda de toque duplicado e transições Aceitar/Recusar/Cheguei/Concluir/Cancelar
- [X] T026 [US4] Criado `PitTecIncomingRequestView.swift` **como View nova e separada** (não uma
  extensão de `ProviderIncomingRequestView`, `013`) — o formato do snapshot PitTec (`offer`
  aproximado, sem nome/preço) é estruturalmente diferente do de guincho móvel; forçar as duas Views
  a compartilhar o mesmo corpo exigiria um tipo unificado artificial
- [ ] T027 [US4] **Não feito** — sem `UserNotifications` (ver T002/T006); a detecção de oferta
  pendente já existe (`ProviderDashboardViewModel.checkPitTecIncoming`, Realtime + poll no
  bootstrap) e abre a tela automaticamente **em primeiro plano**, mas não alerta em segundo plano/
  tela bloqueada como o FR-018A exige
- [ ] T028 [US4] **bloqueado neste ambiente** (interação manual, incluindo background/tela
  bloqueada, que exige um dispositivo físico real)

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T029 [P] Cancelamento (motivo obrigatório pós-aceite, sem motivo pré-aceite via
  `cancel_pittec_search` — achado real desta sessão, ver `PitTecClientViewModel.swift`) implementado
  reutilizando `DispatchCancellationSheet` (`013`)
- [X] T030 Executado `xcodebuild clean build` em simulador e `generic/platform=iOS` —
  **BUILD SUCCEEDED** nesta sessão
- [X] T031 Verificado (leitura) o schema/RPCs PitTec exaustivamente via `pg_get_functiondef` nesta
  sessão (ver achados no topo); Edge Function confirmada ausente
- [X] T032 Nenhum `print`/log adicionado nos arquivos tocados; `PitTecRepository.classify(_:)` só lê
  `.message` para bater contra o literal fechado `PAYMENT_REQUIRED`, mesma nota de `013`
- [ ] T033 **bloqueado neste ambiente** (interação manual, VoiceOver, retomada real)

---

## Dependencies & Execution Order

```text
Setup → Foundation → US5 → US1 → US2 → US3 → US4 → Polish
```

- **US5** entrega a modalidade que **US1** consome na descoberta.
- **US2** depende de **US1** (descoberta) para providers elegíveis.
- **US3** depende de **US2** (candidato/aceite) para acompanhamento.
- **US4** pode ser desenvolvida em paralelo a **US2**/**US3** (lado provider), convergindo no
  mesmo `PitTecRepository`.

### Parallel Opportunities

- Foundation: T003/T004/T005 em paralelo; T006 depende de T004.
- US3: T019/T020 em paralelo; T021/T022 convergem.
- US4: T024/T025 em paralelo antes de T026/T027.

## Notes

- Nenhuma migration ou Edge Function nova é criada — tudo já existe e é compartilhado com o
  Android.
- Nenhuma dependência de terceiros é adicionada; `UserNotifications` é framework do sistema.
- Nenhum push remoto (APNs) é implementado nesta feature.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
