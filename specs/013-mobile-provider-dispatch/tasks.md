---
description: "Implementation tasks for mobile provider search and dispatch (iOS)"
---

# Tasks: Busca e despacho de prestadores móveis (iOS)

**Input**: Design documents from `specs/013-mobile-provider-dispatch/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Sem testes automatizados, conforme a governança do projeto.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

- [X] T001 Verificar com `supabase link` + inspeção direta via `supabase db query --linked` (mais
  profunda que `db diff`: `pg_get_functiondef` de cada uma das ~10 RPCs) que o schema de despacho, as
  RPCs e o Supabase Cron de expiração já estão aplicados no projeto compartilhado
  (`eetbrkznuqbdrnybnyhf`) — **achado crítico não documentado em `spec.md`/`contracts/`**:
  `start_mobile_dispatch` exige uma linha em `public.payments` com `request_id = p_search_id` e
  `status = 'APPROVED'` antes de aceitar a busca (`raise ... errcode = 'P0001', message =
  'PAYMENT_REQUIRED'` caso contrário) — dependência direta de `018-mercadopago-payments`, cujo
  fluxo de pagamento estava com problemas conhecidos (500 do Mercado Pago) numa sessão anterior
  deste mesmo projeto. Sem uma cobrança aprovada para o mesmo `search_id`, nenhuma busca inicia de
  ponta a ponta neste ambiente — classificado como `.paymentRequired` no client (ver
  `MobileDispatchRepository.classify`) em vez de ser escondido/ignorado. Também confirmados: formas
  de resposta reais (nu vs. `{outcome,snapshot}` vs. `{outcome}`) de cada RPC, ausência de RPC para
  cancelar uma busca antes de existir `appointment`, e que `publish_mobile_provider_location` roteia
  sozinho entre discovery/tracking de atendimento (sem precisar de `p_appointment_id`)
- [X] T002 [P] Adicionar SF Symbols/imagens de carro (padrão e selecionado) ao Strings Catalog/
  `Assets.xcassets` para `MapMarkerKind.mobileProvider` — **parcial**: implementado como um SF
  Symbol (`car.fill`) renderizado programaticamente em `PitGoMapView`'s `Coordinator` (novo suporte
  a `symbolName`/`viewFor annotation`), não como imagens dedicadas em `Assets.xcassets`; não há uma
  variante visual "selecionado" distinta

---

## Phase 2: Foundational (Blocking Prerequisites)

**⚠️ CRITICAL**: Nenhuma história começa antes desta fase estar concluída.

- [X] T003 [P] Expor `dispatchKind` no DTO/modelo de `ServiceCatalogRepository` (`009`) sem alterar
  os demais consumidores em `pitgo/Core/Catalog/Model/ServiceCatalogModels.swift` — **bug real
  corrigido nesta sessão**: `list_home_services()` retorna as colunas `(service_id, name,
  description, category_name, minimum_price, dispatch_kind)` (confirmado via
  `pg_get_functiondef`), mas `HomeServiceListing` esperava `service_name`/`service_description`/
  `category_id` (este último inexistente na RPC). Isso fazia TODA linha falhar a decodificação
  silenciosamente — a Home caía em `.failure` sempre que havia qualquer serviço cadastrado, e o
  `RequestServiceViewModel` (`010`) também sempre reportava `.invalid` pelo mesmo motivo. Corrigido
  junto com a adição de `dispatchKind`
- [X] T004 [P] Criar `MobileDispatchSnapshot`, `CandidateProposal`, `DispatchAppointment`,
  `ServiceSearchStatus`, `AppointmentStatus`, estados de tela cliente/provider e
  `PendingDispatchAction` em `pitgo/Features/MobileDispatch/Model/MobileDispatchModels.swift` —
  `CandidateOutcome` do contrato **não foi criado**: é um `enum` puramente interno de
  `private.dispatch_candidates.status` (inclusive com um valor diferente do documentado —
  `CLIENT_SKIPPED`, não `CLIENT_DISMISSED`) nunca serializado para o client (confirmado lendo
  `private.dispatch_snapshot`); adicioná-lo seria código morto
- [X] T005 Criar `MobileDispatchDTOs` (payload/resposta `Codable` das RPCs, incluindo
  `DispatchFlowResult`, que decodifica de modo uniforme os três formatos reais de resposta) em
  `pitgo/Features/MobileDispatch/Data/MobileDispatchDTOs.swift` — os nomes/formatos exatos vieram de
  `pg_get_functiondef` de cada RPC nesta sessão, não do texto prosaico do contrato (que descreve um
  envelope único `{outcome,snapshot}` que nem sempre é o que a função realmente devolve)
- [ ] T006 Generalizar `ProviderLocationTracker` (`009`) para `ProviderTrackingTarget` — **não feito
  como especificado; resolvido de outra forma**: `publish_mobile_provider_location` (confirmado via
  inspeção do código-fonte) já decide sozinho, no servidor, se a posição vai para a discovery pública
  ou para o tracking privado de um atendimento reservado (`target: DISCOVERY|APPOINTMENT` na
  resposta) — não recebe `p_appointment_id` como `publish_provider_location` (`009`) recebe. Como as
  duas RPCs continuam genuinamente distintas e o `009` (`ProviderLocationTracker`, usado por
  `ProviderTrackingView` durante um atendimento aceito) não precisou mudar, criei um tracker novo e
  independente (`ProviderDiscoveryTracker.swift`) só para a fase de disponibilidade, em vez de um
  enum de alvo dentro da classe existente — menor risco sobre código já funcional, mesmo resultado
  funcional
- [X] T007 [P] Adicionar rotas de despacho móvel em `pitgo/Core/Navigation/PitGoRoute.swift` —
  `.mobileDispatchNewSearch(serviceID:)`/`.mobileDispatchSearch(searchID:)` em vez de duas
  sobrecargas de `.mobileDispatch(...)` (Swift não permite dois casos de `enum` com o mesmo nome e
  assinaturas diferentes); `.providerRequest(appointmentID:)` como no contrato;
  `.providerAppointmentTracking(appointmentID:)` já existia desde `009`

**Checkpoint**: modelos, DTOs e rotas prontos; a generalização do tracker foi substituída por um
tracker de discovery dedicado pelo motivo acima — nenhuma história ficou bloqueada por isso.

---

## Phase 3: User Story 1 - Disponibilizar empresa móvel no mapa (Priority: P1) 🎯 MVP

**Independent Test**: Cadastrar uma empresa móvel, torná-la disponível, deslocar o dispositivo
autorizado e confirmar que sua posição elegível muda no mapa e é identificada visualmente como
veículo.

### Implementation for User Story 1

- [X] T008 [US1] Implementar `publishDiscoveryLocation`/`stopDiscoveryLocation` chamando
  `publish_mobile_provider_location`/`stop_mobile_provider_location` com `trackerInstanceID`/
  sequência crescente — em `pitgo/Features/MobileDispatch/Repository/MobileDispatchRepository.swift`
  (não em `ProviderLocationRepository.swift`, que permanece exclusivo do tracking de atendimento de
  `009`, ver T006)
- [X] T009 [US1] Conectar o toggle "Disponível" do `ProviderDashboardView` ao início/parada do
  `ProviderDiscoveryTracker`, reavaliado após qualquer mudança de modalidade/disponibilidade
  (`syncTracker()`), em
  `pitgo/Features/ProviderDashboard/ViewModel/ProviderDashboardViewModel.swift`
- [X] T010 [US1] Adicionar um ícone de carro distinto do pino padrão — **implementado em**
  `pitgo/Core/UI/PitGoMapView.swift` (`symbolName` por anotação + `mapView(_:viewFor:)` retornando
  um `MLNAnnotationView` customizado), não em `MapSurfaceModels`/`ProviderMapStyleCoordinator`
  (nenhum dos dois existe — `010` manteve `PitGoMapView` em vez de migrar para `MapLibreMapHost`
  com `MLNShapeSource`, mesma decisão de escopo já registrada em `010`); usado em
  `ServiceMapView.swift` (providers móveis na descoberta) e `ClientMobileDispatchView.swift`
  (candidato da proposta)
- [ ] T011 [US1] Executar os cenários de disponibilidade/posição/ícone descritos em
  `specs/013-mobile-provider-dispatch/quickstart.md §3` — **bloqueado neste ambiente** (dispositivo/
  simulador interativo com deslocamento real)

**Checkpoint**: empresa móvel publica posição (`ProviderDiscoveryTracker`) e aparece identificada por
um ícone de carro distinto no mapa de descoberta.

---

## Phase 4: User Story 2 - Encontrar e comparar guinchos próximos (Priority: P1)

**Independent Test**: Disponibilizar ao menos três guinchos móveis com posições e preços
diferentes, iniciar a busca pelo card de guincho e confirmar que o primeiro resultado é o elegível
mais próximo e que "Próximo" apresenta outra opção sem repetir a anterior.

### Implementation for User Story 2

- [X] T012 [US2] Implementar `startSearch`, `getActiveDispatch`, `nextCandidate` chamando
  `start_mobile_dispatch`/`get_my_active_mobile_dispatch`/`next_mobile_dispatch_candidate` via um
  decodificador único (`DispatchFlowResult`) em
  `pitgo/Features/MobileDispatch/Repository/MobileDispatchRepository.swift`
- [X] T013 [US2] Implementar `ClientMobileDispatchViewModel` com proteção por `revision` contra
  respostas antigas, fix one-shot do cliente via `CoreLocation` (`009`) e transições de estado
  guiadas pelo `status`/`allowedActions` do snapshot em
  `pitgo/Features/MobileDispatch/ViewModel/ClientMobileDispatchViewModel.swift` — também serve o
  caminho de retomada (`serviceID` opcional; `nil` = resolver a busca ativa da sessão sem tentar
  iniciar uma nova)
- [X] T014 [US2] Criar `ClientMobileDispatchView` com estado/proposta textual, ações "Solicitar"/
  "Próximo" e estado vazio em `pitgo/Features/MobileDispatch/Views/ClientMobileDispatchView.swift` —
  usa `PitGoMapView` (`009`) com o ícone de carro novo (T010) em vez de `MapLibreMapHost`, que não
  existe (ver T010)
- [X] T015 [US2] Conectar o card de guincho da Home a
  `PitGoRoute.mobileDispatchNewSearch(serviceID:)` via `dispatchKind`, preservando `Home→ServiceMap`
  para `.browse`, em `pitgo/Features/Home/Views/HomeView.swift` e
  `pitgo/Core/Navigation/PitGoRootView.swift` (`handleServiceTap`, não em `HomeViewModel` — a
  decisão de rota é navegação, não estado de tela)
- [ ] T016 [US2] Executar os cenários de busca, comparação, expansão de raio e estado vazio
  descritos em `specs/013-mobile-provider-dispatch/quickstart.md §4` — **bloqueado neste ambiente**;
  adicionalmente, um teste de ponta a ponta real exigiria um pagamento `APPROVED` prévio para o
  `search_id` (T001) — não disponível nesta sessão

**Checkpoint**: cliente encontra e compara guinchos móveis por proximidade (build verificado; fluxo
completo ponta a ponta depende de um pagamento aprovado, ver T001).

---

## Phase 5: User Story 3 - Acompanhar e retomar o estado da solicitação (Priority: P1)

**Independent Test**: Iniciar uma busca, avançar por propostas e fechar o app em cada estado
persistido; ao entrar novamente com a mesma conta, confirmar que a tela e o último estado válido
são restaurados.

### Implementation for User Story 3

- [X] T017 [US3] Implementar `requestCandidate`, `respond`, `startAppointment`, `cancelAppointment`,
  `completeAppointment` chamando as RPCs correspondentes em
  `pitgo/Features/MobileDispatch/Repository/MobileDispatchRepository.swift` — `getPendingRequest`
  não é um método próprio: `get_my_pending_mobile_dispatch()` é um alias SQL exato de
  `get_my_active_mobile_dispatch()` (confirmado via `pg_get_functiondef` — o corpo é literalmente
  `select public.get_my_active_mobile_dispatch()`), então `getActiveDispatch()` serve as duas pontas
- [X] T018 [US3] Implementar assinatura privada `mobile-dispatch:<searchID>`/
  `provider-dispatch:<providerID>` (setAuth → subscribe → um snapshot novo a cada evento → remoção
  em `Task` desacoplada) em
  `pitgo/Features/MobileDispatch/Repository/MobileDispatchRepository.swift` — o merge por revisão
  acontece no ViewModel (`applySnapshot`), não no Repository, mesma separação de `009`/`010`
- [X] T019 [US3] Implementar `ProviderIncomingRequestViewModel` com countdown local não autoritativo
  a partir de `responseDeadline`, guarda de toque duplicado (`pendingAction`) e transições Aceitar/
  Recusar/Iniciar/Concluir/Cancelar em
  `pitgo/Features/MobileDispatch/ViewModel/ProviderIncomingRequestViewModel.swift`
- [X] T020 [US3] Criar `ProviderIncomingRequestView` com preço/serviço/deadline e ações Aceitar/
  Recusar (e Iniciar/Concluir/Cancelar quando reservado) em
  `pitgo/Features/MobileDispatch/Views/ProviderIncomingRequestView.swift`
- [X] T021 [US3] Criar `.sheet` de cancelamento com motivo obrigatório (`TextEditor`), erro inline,
  reutilizado por `ClientMobileDispatchView`/`ProviderIncomingRequestView` em
  `pitgo/Features/MobileDispatch/Views/DispatchCancellationSheet.swift` — distinção de autor
  cliente/provider é implícita (cada View só abre o sheet no seu próprio contexto; o servidor deriva
  `cancelled_by` da sessão, nunca de um parâmetro do client)
- [X] T022 [US3] Implementar `DispatchResumeCoordinator` traduzindo `get_my_active_mobile_dispatch`
  em um destino tipado (`.clientSearch`/`.clientTracking`/`.providerIncoming`/`.providerTracking`/
  `.none`) em `pitgo/Features/MobileDispatch/Coordinator/DispatchResumeCoordinator.swift` — quem já
  sabe o papel da sessão (cliente vs. provider) chama o método correspondente; o coordinator não
  decide papel sozinho
- [X] T023 [US3] Integrar ao `PitGoRootView`: lado cliente usa `resolveForClient()` num `.task` de
  `ClientMainTabView` (só quando `homePath` está vazio, para não roubar navegação); lado provider
  **não usa `resolveForProvider()` diretamente** — `ProviderDashboardViewModel` já fazia uma consulta
  de `getActiveDispatch()` continuamente reativa (bootstrap + Realtime) para detectar solicitação
  pendente, e essa mesma consulta foi estendida para também detectar `ACCEPTED`/`IN_PROGRESS`
  (`resumedTrackingAppointmentID`) e navegar para `.providerAppointmentTracking` — evita duplicar a
  mesma leitura numa chamada de coordinator separada só para o instante do bootstrap.
  `dispatchRepository.disconnectAll()`/`discoveryTracker.stop()` são chamados em `tearDown()`
  (`.onDisappear` da raiz do dashboard), nunca ao empurrar uma rota filha na mesma `NavigationStack`
- [ ] T024 [US3] Executar os cenários de aceite/recusa/expiração/cancelamento/retomada descritos em
  `specs/013-mobile-provider-dispatch/quickstart.md §5-§7` — **bloqueado neste ambiente** (exige duas
  contas reais — cliente e provider — interagindo simultaneamente em dispositivos/simuladores, além
  do pagamento aprovado de T001 para o lado cliente)

**Checkpoint**: fluxo completo de decisão e retomada implementado e compilando para cliente e
provider; validação end-to-end depende de pagamento aprovado (T001) e de interação manual com duas
contas (T024).

---

## Phase 6: User Story 4 - Controlar disponibilidade e publicação da empresa móvel (Priority: P2)

**Independent Test**: Alternar a disponibilidade de uma empresa móvel e encerrar/trocar a sessão,
confirmando que o indicador acompanha o estado e que a empresa deixa de participar de novas buscas
quando inelegível.

### Implementation for User Story 4

- [X] T025 [US4] Implementar transições `.stopped|.starting|.active|.degraded|.stopping` reagindo a
  perda de permissão/sessão/disponibilidade — reaproveitado o `enum ProviderTrackingState` já
  existente de `009` (nomes `.active(lastPublishedAt:)`/`.stopped` sem associated reason, em vez de
  `.publishing`/`.stopped(reason:)` do data-model.md) para não arriscar os consumidores já
  existentes de `009`/`ProviderTrackingView`; implementado em
  `pitgo/Features/MobileDispatch/ProviderDiscoveryTracker.swift` (`start()`/`apply(_:)`)
- [X] T026 [US4] Renderizar os estados de publicação no `ProviderDashboardView` com indicação
  persistente e compreensível (texto + ícone + cor, sem notificação manual) em
  `pitgo/Features/ProviderDashboard/Views/ProviderDashboardView.swift`
  (`discoveryStatusSection`) — substitui a antiga entrada manual de `appointmentID` (documentada
  como placeholder em `009`) por navegação automática real
- [X] T027 [US4] Coordenar parada best-effort e retomada automática — `syncTracker()` em
  `ProviderDashboardViewModel` reavalia `active && available && locationMode == .mobile` após toda
  mudança de modalidade/disponibilidade e após `retry()`, iniciando/parando o
  `ProviderDiscoveryTracker`; a retomada automática pós-atendimento (FR-019C) é responsabilidade do
  servidor (`private.apply_pending_provider_mode`, já confirmado nas RPCs de resposta/cancelamento/
  conclusão) — o client só precisa continuar publicando, o que já faz enquanto "Disponível"
  permanecer ligado
- [ ] T028 [US4] Executar os cenários de disponibilidade/indisponibilidade/sessão descritos em
  `specs/013-mobile-provider-dispatch/quickstart.md §3` e `§9` — **bloqueado neste ambiente**

**Checkpoint**: disponibilidade e privacidade de localização são explícitas e reversíveis
(implementado e compilando); validação de comportamento em segundo plano real fica para T028.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T029 [P] Executar `xcodebuild clean build` em simulador e `generic/platform=iOS` — ambos com
  **BUILD SUCCEEDED** nesta sessão, após todas as mudanças de T003-T027
- [X] T030 [P] Verificar (leitura) novamente o schema/RPCs/Cron compartilhados — feito de forma
  ainda mais completa que `db diff` (T001): código-fonte completo de todas as ~10 RPCs, ACLs,
  `SECURITY DEFINER`/`search_path`, e a dependência de pagamento inspecionados via
  `pg_get_functiondef`/`information_schema` nesta sessão
- [X] T031 Auditar logs/mensagens para ausência de token, `Error` bruto, coordenada de terceiros ou
  detalhe SQL em `pitgo/Features/MobileDispatch/Repository/MobileDispatchRepository.swift` e
  `pitgo/Features/MobileDispatch/ProviderDiscoveryTracker.swift` — nenhum `print`/log adicionado;
  `classify(_:)` só lê `postgrestError.message` para bater contra o literal fechado
  `"PAYMENT_REQUIRED"`, nunca repassando a string adiante (ver nota em
  `MobileDispatchRepository.swift`); `ProviderLocationRepository.swift` (`009`) não foi alterado
- [ ] T032 Revisar Dynamic Type grande, landscape, VoiceOver, alvos de toque e representação
  textual equivalente ao mapa em `ClientMobileDispatchView` e `ProviderIncomingRequestView` —
  **parcial**: alvos `>=44×44pt`/CTA `>=56pt` e texto equivalente ao mapa (o card de proposta já
  contém toda informação, o mapa é `accessibilityHidden`) foram seguidos por construção; não houve
  uma auditoria dedicada em dispositivo com Dynamic Type grande/landscape/VoiceOver real
- [ ] T033 Executar a matriz manual completa de concorrência, resposta perdida, retomada e
  segurança descrita em `specs/013-mobile-provider-dispatch/quickstart.md §8-§10` — **bloqueado
  neste ambiente**: exige duas contas reais interagindo simultaneamente e, para o caminho completo
  do cliente, um pagamento `APPROVED` prévio (T001)

---

## Dependencies & Execution Order

```text
Setup → Foundation → US1 (MVP) → US2 → US3 → US4 → Polish
```

- **US1**: entrega a base de publicação/mapa; independe de US2-US4 para seu teste próprio.
- **US2**: depende de US1 para providers móveis aparecerem elegíveis nas buscas.
- **US3**: depende de US2 (candidato/proposta) para decisão/retomada.
- **US4**: refina disponibilidade sobre US1/US3.

### Parallel Opportunities

- Setup: T001/T002 em paralelo.
- Foundation: T003/T004/T007 em paralelo; T005 depende de T004; T006 é independente.
- US2: T012 e T013 convergem para T014; T015 pode avançar em paralelo.
- US3: T017/T018 em paralelo; T019→T020→T021 convergem; T022/T023 fecham a retomada.
- US4: T025/T026 em paralelo; T027 integra.

## Notes

- Nenhuma migration, RPC ou job novo é criado — tudo já existe e é compartilhado com o Android.
- Nenhuma dependência nova é adicionada.
- Nenhum teste automatizado é criado; build e `quickstart.md` são os gates de qualidade.
- Commits pequenos por tarefa/grupo lógico.
