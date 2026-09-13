---
description: "Dependency-ordered implementation tasks for Mercado Pago payments (Pix and saved card) — iOS"
---

# Tasks: Pagamento de serviços (Pix e cartão) — iOS

**Input**: Design documents from `specs/018-mercadopago-payments/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Testes automatizados são omitidos intencionalmente — nem a feature nem o usuário os
solicitaram, e a governança do projeto não exige. Cada story termina com uma tarefa de validação
manual ligada à seção correspondente de `quickstart.md`.

**Organization**: Tarefas agrupadas por user story (US1 Pix, US2 cadastro de cartão, US4 reembolso
automático, US3 pagar com cartão salvo — nessa ordem de prioridade/dependência) para que cada uma
possa ser implementada e validada como incremento independente.

> **ACHADOS REAIS DESTA SESSÃO (leia antes de revisar as tarefas abaixo)**:
>
> 1. **O backend compartilhado já estava implantado inteiramente** quando esta sessão começou —
>    `payments`/`saved_cards`, as cinco Edge Functions e a guarda de pagamento em
>    `start_pittec_dispatch` já existiam (presumivelmente publicados junto com o trabalho Android de
>    `018`). Nenhuma migration/Edge Function nova foi autorada aqui — confirmado lendo o
>    código-fonte real das cinco functions (`supabase functions download`) e via `pg_get_functiondef`
>    de cada RPC.
> 2. **O ponto de gate real de MOBILE_SEQUENTIAL contradiz `research.md §9` deste próprio spec.**
>    `research.md` argumenta que a guarda deveria ficar em `request_mobile_dispatch_candidate` (depois
>    de um candidato existir), não em `start_mobile_dispatch`. A inspeção direta da função REAL
>    mostra o oposto: a guarda está em `start_mobile_dispatch`
>    (`payments.request_id = p_search_id`), exatamente como o Android (`PaymentCheckoutViewModel.kt`,
>    que gera o `requestId` a partir da Home antes de qualquer busca existir).
>    `request_mobile_dispatch_candidate` continua **sem nenhuma guarda** — reservar um candidato
>    específico não exige pagamento além do já feito para iniciar a busca. Este client segue a
>    realidade verificada, documentada em `PaymentModels.swift`, não o texto do `research.md`.
> 3. **Pedi confirmação ao usuário** antes de alterar o backend compartilhado (usado em produção por
>    Android) e a resposta foi **não aplicar** — `request_mobile_dispatch_candidate` permanece sem
>    guarda de pagamento no backend. Isso não bloqueia o cliente iOS (que sempre paga antes de chamar
>    qualquer RPC de despacho pela UI), mas alguém chamando o RPC diretamente, fora do app, ainda
>    reservaria um candidato sem pagar — risco pré-existente, não introduzido nem fechado por esta
>    sessão.
> 4. **`list_home_services().minimum_price` é sempre 0 para PITTEC_AUTO_SEQUENTIAL** (a oferta do
>    prestador PitTec é `is_free = true`/preço zero por desenho, `016`) — confirmado com dados reais
>    de `provider_services`. O Android (`PaymentCheckoutViewModel.kt`) reaproveita
>    `service.minimumPrice` para os dois `dispatchKind` indistintamente, o que resultaria em
>    `amount = 0`/`InvalidService` contra os dados reais de PitTec hoje — **não replicado aqui**.
>    `PaymentPricing.pittecPlatformFee` (constante de produto, R$ 20 nesta entrega) é usada em vez
>    disso para PitTec; `minimum_price` do catálogo continua usado para MOBILE_SEQUENTIAL.
> 5. **`PitGoRoute.payment(requestID:dispatchKind:)` não foi criada.** Em vez de uma nova rota
>    empilhada (que exigiria adicionar o caso aos três `switch` exaustivos de
>    `PitGoRootView`/`ProfileView`), o checkout é apresentado como `.sheet` diretamente por
>    `ClientMobileDispatchView` (novo estado `.paymentRequired` no ViewModel, antes de
>    `start_mobile_dispatch`) e por `PitTecClientView` (ao tocar "Chamar PitTec", antes de
>    `start_pittec_dispatch`) — mesmo idioma já usado por `DispatchCancellationSheet` (`013`). Uma
>    nova rota `.paymentMethods` (Perfil → Formas de pagamento) foi adicionada normalmente, pois essa
>    tela é um destino real, não transitório.
> 6. **API real do SDK iOS (`mercadopago/sdk-ios` 1.0.0) confirmada lendo o código-fonte publicado no
>    GitHub** (não apenas documentação): produto SPM `CoreMethods` (reexporta `MPCore` via
>    `@_exported import`), `MercadoPagoSDK.shared.initialize(.init(publicKey:country: .BRA))`,
>    `CoreMethods().createToken(cardNumber:expirationDate:securityCode:cardHolderName:)`,
>    `CardNumberTextFieldView`/`ExpirationDateTextFieldView`/`SecurityCodeTextFieldView` (SwiftUI,
>    `UIViewRepresentable`). Pacote adicionado a `pitgo.xcodeproj` (SPM remoto, `upToNextMajorVersion`
>    a partir de `1.0.0`) e resolvido com sucesso (`xcodebuild -resolvePackageDependencies`).
> 7. **`get_payment_status` real devolve `{outcome, payment_id, status, method}`**, sem
>    `pix_qr_code`/`refund_status` como `contracts/payment-rpcs.md` descreve — `PaymentDTOs.swift`
>    segue o formato real.
> 8. **Nenhum trigger/cron server-side chama `mp-refund-payment` sozinho** — confirmado inspecionando
>    `pg_trigger`/`cron.job` reais. `cancel_mobile_appointment`/`cancel_pittec_search`/
>    `advance_pittec_dispatch` (ao alcançar `NO_PROVIDER`) já marcam `payments.status =
>    'REFUND_PENDING'`, mas é o **app** quem chama `mp-refund-payment` ao observar esse estado
>    (implementado em `ClientMobileDispatchViewModel`/`PitTecClientViewModel.checkRefund`).
> 9. **Sem uma `MERCADO_PAGO_PUBLIC_KEY` real nesta sessão** (nenhuma credencial de teste foi
>    fornecida para o projeto iOS) — `Config/Secrets.xcconfig` não recebeu a chave;
>    `ManagedMercadoPagoConfiguration.current` fica `nil`, e a UI trata isso como "cadastro de cartão
>    indisponível" em vez de travar. Pix não depende desta chave. Toda validação manual contra o
>    Mercado Pago real (T015/T022/T026/T029) fica bloqueada neste ambiente até uma chave de teste ser
>    configurada.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode rodar em paralelo — toca arquivos diferentes e não depende de tarefa não concluída
  desta lista.
- **[Story]**: Mapeia a tarefa para US1/US2/US3/US4 de `spec.md`.
- Cada tarefa nomeia o(s) arquivo(s) alvo exato(s).

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Wiring não sensível compartilhado por todas as fases seguintes.

- [X] T001 [P] `mercadopago/sdk-ios` adicionado via SPM (`XCRemoteSwiftPackageReference`/
  `XCSwiftPackageProductDependency` em `project.pbxproj`, produto `CoreMethods`,
  `upToNextMajorVersion` a partir de `1.0.0`; resolvido com sucesso via
  `xcodebuild -resolvePackageDependencies`). `mercadoPagoPublicKey` exposta via
  `Config/Shared.xcconfig` (default vazio) + `Info.plist` (`MERCADO_PAGO_PUBLIC_KEY`) +
  `pitgo/Core/Payment/Config/ManagedMercadoPagoConfiguration.swift` (`nil` sem chave, sem fallback
  de avaliação — ver achado #9). `Config/Secrets.xcconfig` **não** recebeu uma chave real (nenhuma
  foi fornecida nesta sessão para o projeto iOS). SDK inicializado em `pitgoApp.swift.init()`,
  condicionalmente.
- [X] T002 [P] Confirmado (achado #1): as cinco Edge Functions já estavam publicadas no projeto
  Supabase compartilhado antes desta sessão (`supabase functions download` trouxe o código-fonte
  real de todas). Este repositório não tem `supabase/config.toml`/`supabase/.env.example` (nenhuma
  spec anterior os criou) — nada foi adicionado para não introduzir um padrão novo sem necessidade
  real; os nomes das variáveis (`MP_ACCESS_TOKEN`, `MP_WEBHOOK_SECRET`) já estão documentados nos
  comentários das próprias functions e em `research.md`/`contracts/`.
- [ ] T003 [P] **Não feito** — o projeto não usa um Strings Catalog para as Views existentes
  (`013`/`015`/`016` também não criaram um); os textos de Pix/cartão salvo/"Formas de pagamento"
  foram escritos como literais `Text("...")`, mesma convenção já usada por 100% das outras Views do
  app.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Contrato de banco e modelo Swift compartilhado do qual toda story de pagamento depende.

**⚠️ CRITICAL**: Nenhuma story começa antes desta fase passar por `supabase db lint` (se a migração
ainda não foi publicada por outra plataforma) e o novo modelo Swift compilar.

- [X] T004 Confirmado via `information_schema.columns`/`pg_constraint`/`pg_class` reais: `payments`
  já existe com todas as colunas de `data-model.md`, `CHECK` constraints (não `enum` do Postgres,
  mas equivalente) para `status`/`method`/`dispatch_kind`, RLS **habilitada sem nenhuma política**
  (mais restritivo que "`client_id = auth.uid()` para `SELECT`" — na prática bloqueia até leitura
  direta via REST; todo acesso passa por RPC `SECURITY DEFINER` ou pela Service Role das Edge
  Functions). Nenhuma migração nova autorada (já existia).
- [X] T005 Confirmado via `pg_get_functiondef`: `get_payment_status`/`list_saved_cards`/
  `remove_saved_card` já existem — com uma divergência real do contrato documentada no achado #7
  (`get_payment_status` devolve `{outcome, payment_id, status, method}`, não o envelope mais rico
  descrito). `PaymentDTOs.swift` segue o formato real, não o do contrato.
- [ ] T006 **Feito apenas para PitTec** — `start_pittec_dispatch` já tinha a guarda `PAYMENT_REQUIRED`
  (confirmada via `pg_get_functiondef`). Para MOBILE_SEQUENTIAL, a guarda real está em
  `start_mobile_dispatch` (não em `request_mobile_dispatch_candidate`, ao contrário do que este
  spec e `contracts/payment-rpcs.md` descrevem — achado #2) **e já existia assim antes desta
  sessão**. `request_mobile_dispatch_candidate` continua sem guarda alguma; ofereci adicioná-la (no
  mesmo padrão de `start_pittec_dispatch`) e o usuário optou por **não alterar o backend
  compartilhado agora** (achado #3) — documentado, não esquecido.
- [X] T007 [P] Criado `PaymentDispatchKind`/`PaymentStatus`/`PaymentMethodKind`/`PaymentPricing` e os
  DTOs de Edge Function/RPC em `pitgo/Features/Payment/Model/PaymentModels.swift` e
  `pitgo/Features/Payment/Data/PaymentDTOs.swift`, seguindo os formatos REAIS confirmados (não os de
  `data-model.md`/`contracts/` onde divergem — achados #4/#7).

**Checkpoint**: backend já íntegro para PitTec; MOBILE_SEQUENTIAL gateado corretamente em
`start_mobile_dispatch` (real, verificado) mesmo sem a guarda adicional em
`request_mobile_dispatch_candidate` que só protegeria contra chamada direta fora do app; modelo de
pagamento compartilhado compila isoladamente e builds completos (simulador +
`generic/platform=iOS`) sucedem com ele integrado.

---

## Phase 3: User Story 1 - Pagar a solicitação de serviço via Pix (Priority: P1) 🎯 MVP

**Goal**: Cliente paga via Pix ao reservar um candidato MOBILE_SEQUENTIAL ou ao iniciar uma chamada
PitTec, e o despacho do prestador só ocorre depois da confirmação.

**Independent Test**: Gerar um Pix de teste, aprová-lo no sandbox do Mercado Pago e confirmar que o
despacho é liberado; gerar outro e deixá-lo expirar, confirmando que nenhum prestador é acionado.

### Implementation for User Story 1

- [X] T008 [P] [US1] Confirmado (achado #1): o branch Pix de `mp-create-payment` já estava
  implementado e implantado — lido o código-fonte real (`supabase functions download`), bate com o
  contrato (idempotency key = `request_id` + sufixo de tentativa, checagem de reuso, CPF do cliente,
  passthrough de `qr_code`/`qr_code_base64`).
- [X] T009 [P] [US1] Confirmado (achado #1/#8): `mp-webhook` já implementado e implantado —
  validação HMAC de `x-signature`, rebusca por `id` na API do Mercado Pago, atualização de
  `payments`. A publicação Realtime **não** acontece dentro do código da function — é um `TRIGGER`
  Postgres (`payment_status_broadcast` → `private.broadcast_payment_change()`) que dispara
  `realtime.send(..., 'CHANGED', 'payment:'||request_id, true)` a cada `INSERT`/`UPDATE` em
  `payments`, incluindo os updates que `mp-webhook` faz — resultado idêntico ao contrato, mecanismo
  diferente (confirmado via `pg_get_triggerdef`/`pg_get_functiondef`).
- [X] T010 [P] [US1] Implementado `PaymentRepository` (`createPayment`, `status(requestID:)` via RPC,
  `subscribe(requestID:onChanged:)`/`unsubscribe`/`disconnect` via canal privado
  `payment:<requestID>`, `refund(paymentID:)`) em
  `pitgo/Features/Payment/Repository/PaymentRepository.swift`, no mesmo padrão de canal/erro de
  `MobileDispatchRepository`/`PitTecRepository`. Inclui um `JSONDecoder` dedicado com estratégia de
  data ISO8601 tolerante a milissegundos (`Date.toISOString()` do lado da Edge Function) — o
  `JSONDecoder` padrão do `FunctionsClient` não decodifica essas datas.
- [X] T011 [US1] Implementado `PaymentCheckoutViewModel` (`@Observable`) com
  `PaymentCheckoutUiState` (`.loadingAmount`, `.invalidService`, `.selectingMethod`,
  `.creatingPayment`, `.awaitingPix`, `.awaitingCardConfirmation`, `.approved`, `.declined`,
  `.expired`, `.payerDocumentRequired`, `.sessionExpired`, `.failure` — superconjunto do descrito em
  `contracts/payment-realtime-ui.md`, cobrindo os erros reais das Edge Functions) em
  `pitgo/Features/Payment/ViewModel/PaymentCheckoutViewModel.swift`. Gera o próprio `requestID`
  (`UUID()`), reaproveitado pelo chamador após `.approved`.
- [X] T012 [US1] Implementado `PaymentCheckoutView` com o branch Pix (QR decodificado do Base64,
  copia-e-cola com feedback, `Text(timerInterval:)` para a expiração, "gerar novo código"/"trocar
  forma de pagamento") em `pitgo/Features/Payment/Views/PaymentCheckoutView.swift`.
- [X] T013 [US1] Conectado o fluxo MOBILE_SEQUENTIAL — **sem** `PitGoRoute.payment(...)` (achado #5):
  `ClientMobileDispatchViewModel` ganhou o estado `.paymentRequired(serviceID:)`, alcançado antes de
  `start_mobile_dispatch` (gate real, achado #2 — não em `request_mobile_dispatch_candidate`, que
  segue livre para "Solicitar este guincho"/"Próximo" como já era em `013`); `ClientMobileDispatchView`
  apresenta `PaymentCheckoutView` como `.sheet` nesse estado; em `.approved`,
  `beginPaidSearch(searchID:)` reaproveita o `requestID` do checkout como `p_search_id`. Cancelar o
  sheet sem aprovar chama `onBack()` sem tocar em nenhuma RPC de despacho (FR-013). Um
  `reservedPaidSearchID` evita cobrar de novo se "Tentar novamente" for tocado após falha de
  localização pós-aprovação. Arquivos: `PitGoRoute.swift` (sem mudança nesta trilha),
  `MobileDispatchModels.swift`, `ClientMobileDispatchViewModel.swift`,
  `ClientMobileDispatchView.swift`.
- [X] T014 [US1] Conectado o fluxo PitTec da mesma forma — sem rota nova: "Chamar PitTec" (dentro do
  estado `.discovering`, já gratuito por natureza já que `list_nearby_pittecs` não é gateada)
  apresenta `PaymentCheckoutView` como `.sheet` a partir de `PitTecClientView`; em `.approved`,
  `PitTecClientViewModel.callPitTec(requestID:)` (assinatura alterada — antes gerava `UUID()`
  sozinho) chama `start_pittec_dispatch` com o `requestID` já pago. Arquivos:
  `PitTecClientViewModel.swift`, `PitTecClientView.swift`.
- [ ] T015 [US1] **bloqueado neste ambiente** (achado #9 — sem `MERCADO_PAGO_PUBLIC_KEY`/sandbox do
  Mercado Pago configurados para o projeto iOS nesta sessão; exige interação manual com o painel de
  sandbox). Build (simulador e `generic/platform=iOS`) confirma que o fluxo compila e monta
  corretamente; a execução ponta a ponta contra o Mercado Pago real não foi possível aqui.

**Checkpoint**: fluxo completo implementado e compilando; despacho não ocorre sem `.approved`
(verificado no código — `beginPaidSearch`/`callPitTec` só são chamados a partir do callback
`onApproved`); validação ponta a ponta contra o Mercado Pago real fica pendente de credenciais.

---

## Phase 4: User Story 2 - Cadastrar um cartão como forma de pagamento (Priority: P2)

**Goal**: Cliente cadastra, lista e remove cartões de forma totalmente opcional numa área dedicada,
sem afetar nenhuma outra funcionalidade do app.

**Independent Test**: Cadastrar um cartão de teste válido e um de teste de recusa na área de formas
de pagamento; confirmar que só bandeira/últimos 4 dígitos ficam visíveis e que nada no app exige
esse cadastro.

### Implementation for User Story 2

- [X] T016 [P] [US2] Confirmado (achado #1): `mp-save-card` já implementado e implantado — cria ou
  reaproveita Customer por `client_id`, salva o `card_token` como Customer Card, devolve
  bandeira/últimos 4 (com tratamento de Customer duplicado por busca de e-mail).
- [X] T017 [P] [US2] Confirmado (achado #1): `mp-remove-card` já implementado e implantado — confere
  posse, remove o Customer Card upstream, chama `remove_saved_card` (usando o client autenticado,
  não a service role, para reforçar RLS na mesma camada de qualquer outra escrita).
- [X] T018 [P] [US2] Criado `SavedCard`/`SavedCardFailureReason` e `SavedCardRepository` (`list`,
  `save(cardToken:)`, `remove(id:)`) em
  `pitgo/Features/PaymentMethods/Model/SavedCardModels.swift`,
  `pitgo/Features/PaymentMethods/Data/SavedCardDTOs.swift` e
  `pitgo/Features/PaymentMethods/Repository/SavedCardRepository.swift`.
- [X] T019 [US2] Implementado `PaymentMethodsViewModel` com um `PaymentMethodsUiState` mais simples
  que o do contrato (`.loading`, `.content([SavedCard])`, `.failure`) — o estado "formulário aberto"
  vive como `@State` local da View (`isPresentingForm`), não no ViewModel, mesma separação já usada
  por outras Views deste app que não promovem estado puramente de apresentação para o ViewModel — em
  `pitgo/Features/PaymentMethods/ViewModel/PaymentMethodsViewModel.swift`.
- [X] T020 [US2] Implementado `PaymentMethodsView` com os campos seguros reais do SDK
  (`CardNumberTextFieldView`/`ExpirationDateTextFieldView`/`SecurityCodeTextFieldView`, módulo
  `CoreMethods` — API confirmada lendo o código-fonte do pacote 1.0.0 publicado no GitHub, achado
  #6) e listagem/remoção de cartões salvos, em
  `pitgo/Features/PaymentMethods/Views/PaymentMethodsView.swift`. O botão "Cadastrar cartão" só
  aparece quando `ManagedMercadoPagoConfiguration.current != nil` (achado #9).
- [X] T021 [US2] Adicionado o item "Formas de pagamento" ao Perfil (`paymentMethodsEntry`) e o caso
  `PitGoRoute.paymentMethods` (tratado em `ProfileView.swift`; `EmptyView()` nos dois outros
  `switch` exaustivos que não o usam — `PitGoRootView.swift`/`ProviderDashboardView.swift`).
- [ ] T022 [US2] **bloqueado neste ambiente** (achado #9 — mesma razão de T015).

**Checkpoint**: cartões podem ser cadastrados, listados e removidos independentemente do checkout;
nenhum fluxo existente exige esse cadastro; verificado por leitura de código e build, não por
execução manual contra o Mercado Pago real.

---

## Phase 5: User Story 4 - Reembolso automático quando o atendimento pago não se concretiza (Priority: P2)

**Goal**: Estorno automático total quando o cliente cancela antes da conclusão, ou quando a busca
PitTec termina sem prestador — com retry e fallback para suporte se o próprio estorno falhar.

**Independent Test**: Pagar uma solicitação, cancelar antes da conclusão (e, separadamente, esgotar
a busca PitTec) e confirmar o estorno automático; forçar falha do estorno e confirmar o aviso de
"reembolso em andamento" ao cliente.

### Implementation for User Story 4

- [X] T023 [P] [US4] Confirmado (achado #1): `mp-refund-payment` já implementado e implantado —
  chamada de estorno, `refund_attempts`, retry síncrono com o backoff de `research.md §7`
  (2s/8s/20s), marca `REFUNDED`/`REFUND_FAILED` após 3 tentativas.
- [X] T024 [US4] Confirmado (não autorado — já existia, achado #1): `cancel_mobile_appointment`,
  `cancel_pittec_search` e `private.advance_pittec_dispatch` (ao alcançar `NO_PROVIDER`) já marcam
  `payments.status = 'REFUND_PENDING'` dentro da própria transação (lido `pg_get_functiondef` de
  cada um). **Diferença real do contrato**: nenhum dos três chama `mp-refund-payment`/dispara
  `pg_notify`/`pg_net` sozinho — confirmado que não existe trigger nem `cron.job` para isso. Por
  isso, `ClientMobileDispatchViewModel.checkRefund(searchID:)` e
  `PitTecClientViewModel.checkRefund(searchID:)` (novos) chamam `get_payment_status` ao chegar num
  snapshot terminal `CANCELLED`/`EXHAUSTED` e, se `REFUND_PENDING`, chamam `mp-refund-payment` a
  partir do app — implementado no app porque não há automação server-side (achado #8), não como
  substituto de uma automação que existiria.
- [X] T025 [P] [US4] Exibido o feedback `REFUNDED`/`REFUND_FAILED` em
  `pitgo/Features/MobileDispatch/Views/ClientMobileDispatchView.swift` e
  `pitgo/Features/PitTec/Views/PitTecClientView.swift` (não em
  `AppointmentTrackingView.swift`: essa View é somente leitura de posição do prestador — não tem
  nenhuma ação de cancelamento própria; todo cancelamento real do guincho móvel, aceito ou não,
  acontece dentro de `ClientMobileDispatchView`, que é onde o feedback foi colocado).
- [ ] T026 [US4] **bloqueado neste ambiente** (achado #9 — mesma razão de T015; adicionalmente exige
  forçar falha de estorno no sandbox para o cenário `REFUND_FAILED`).

**Checkpoint**: cancelamentos pré-conclusão e buscas PitTec exauridas disparam a checagem/estorno
automaticamente no código (verificado por leitura); a execução ponta a ponta contra o Mercado Pago
real fica pendente de credenciais.

---

## Phase 6: User Story 3 - Pagar a solicitação de serviço com cartão salvo (Priority: P3)

**Goal**: Cliente com cartão já cadastrado escolhe esse cartão na etapa de pagamento em vez de Pix.

**Independent Test**: Com um cartão de teste já salvo, pagar uma solicitação escolhendo esse cartão
e confirmar aprovação e despacho; repetir com um cartão de teste de recusa.

### Implementation for User Story 3

- [X] T027 [US3] Confirmado (achado #1): o branch `SAVED_CARD` de `mp-create-payment` já implementado
  e implantado — cobra usando `card.mp_card_id` como `token` (com um `card_security_code_token`
  opcional para reautenticação de CVV, não coletado por este client — ver nota abaixo), mesma
  estratégia de idempotência do Pix.
- [X] T028 [US3] Estendido `PaymentCheckoutViewModel`/`PaymentCheckoutView`: `.selectingMethod` já
  carrega `savedCards: [SavedCard]` (buscados de `SavedCardRepository.list()` junto com o valor),
  exibidos como botões "Pagar com este cartão" ao lado do Pix; sem cartão salvo, a tela mostra só
  Pix (nenhum "Pix-only" explícito é necessário — a lista simplesmente fica vazia). **Simplificação
  deliberada**: nenhum campo de CVV é recoletado no momento do pagamento — `card_security_code_token`
  não é enviado, e o backend cai para `card.mp_card_id` como `token` (aceito pela própria Edge
  Function); o Android (`PaymentCheckoutViewModel.kt`) faz a mesma simplificação (`payWithSavedCard`
  não recebe CVV).
- [ ] T029 [US3] **bloqueado neste ambiente** (achado #9 — mesma razão de T015).

**Checkpoint**: as quatro user stories estão implementadas e integradas no código-fonte, com build
completo (simulador + `generic/platform=iOS`) confirmado; a validação end-to-end contra o Mercado
Pago real (as quatro tarefas de Cenário) fica pendente de uma `MERCADO_PAGO_PUBLIC_KEY`/credenciais
de sandbox reais para o projeto iOS.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Verificação final cruzando todas as stories.

- [X] T030 `xcodebuild -project pitgo.xcodeproj -scheme pitgo -destination 'generic/platform=iOS
  Simulator' build` e `-destination 'generic/platform=iOS' build` — **BUILD SUCCEEDED** nas duas,
  sem erros nem warnings novos atribuíveis a esta feature. `supabase db lint` não foi rodado (nenhuma
  migração nova foi criada — nada a lintar). `deno check` **não pôde ser executado** — não há `deno`
  instalado neste ambiente (`deno: command not found`); as cinco functions não foram alteradas
  (apenas lidas), então o risco é baixo, mas a verificação formal fica pendente.
- [X] T031 Cenário 5 (paridade de escopo/gate) verificado por leitura de código, não por execução
  manual (achado #9): "Próximo"/"Solicitar este guincho" sobre um candidato já reservado não
  reabrem o checkout (só `start_mobile_dispatch`, no início da busca, é gateado); o mesmo vale para
  PitTec ("Chamar PitTec" sempre paga antes de `start_pittec_dispatch`, usando a tarifa fixa, nunca
  uma estimativa por distância). Revisão de código confirmada: `grep -rn "Logger\|print("` em todos
  os arquivos novos de `Features/Payment`/`Features/PaymentMethods`/`Core/Payment` não retornou
  nenhuma ocorrência — nenhum PAN, CVV, token ou Access Token é logado (não há nenhum log ali).
- [ ] T032 **Parcialmente bloqueado**: os segredos server-side (`MP_ACCESS_TOKEN`/`MP_WEBHOOK_SECRET`)
  não foram reverificados nesta sessão (`supabase secrets list` só devolve hashes, não confirma
  validade) — mas as cinco Edge Functions já respondem em produção (achado #1), então
  presumivelmente já configurados por quem publicou o backend. O item que falta de fato para uma
  build iOS totalmente funcional é `MERCADO_PAGO_PUBLIC_KEY` em `Config/Secrets.xcconfig` — sem
  ela, o cadastro de cartão fica desabilitado na UI (Pix continua funcional). Não marco esta tarefa
  como concluída porque o rollout real depende dessa chave, que está fora do alcance desta sessão.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Sem dependências — pode começar imediatamente.
- **Foundational (Phase 2)**: Depende do Setup — BLOQUEIA toda user story.
- **User Story 1 (Phase 3)**: Depende só do Foundational. Este é o MVP.
- **User Story 2 (Phase 4)**: Depende só do Foundational; independente do código de US1, mas
  ordenada depois aqui porque P1 tem prioridade sobre P2.
- **User Story 4 (Phase 5)**: Depende do Foundational (T006) e precisa de ao menos um pagamento
  aprovado existente para ser testada de forma significativa — implementada depois de US1.
- **User Story 3 (Phase 6)**: Depende de US2 (precisa de um cartão salvo, T018) e reaproveita a UI/
  Edge Function de checkout de US1 (T012, T008) — a única story que não é independente do código de
  outra story.
- **Polish (Phase 7)**: Depende das quatro stories completas.

### Within Each User Story

- Edge Functions antes de repositórios antes de ViewModels antes de UI antes de wiring/integração
  antes da tarefa de validação manual.

### Parallel Opportunities

- Toda a Phase 1 (T001-T003) pode rodar em paralelo.
- T004→T005→T006 são sequenciais (mesmo arquivo de migração); T007 pode rodar em paralelo com as
  três.
- Dentro de US1: T008 e T009 (arquivos de Edge Function diferentes) podem rodar em paralelo; T010
  pode rodar em paralelo com ambas assim que T007 estiver pronta.
- Dentro de US2: T016, T017 e T018 podem rodar em paralelo.
- Dentro de US4: T023 pode rodar em paralelo com T024/T025.

---

## Parallel Execution Examples

### Foundational

```bash
Task: "Criar o modelo de domínio compartilhado Payment em pitgo/Features/Payment/Model/PaymentModels.swift"
# ...enquanto, separadamente:
Task: "Confirmar/criar a tabela payments, enums, índices e RLS na migração compartilhada"
```

### User Story 1

```bash
Task: "Implementar o branch Pix de mp-create-payment em supabase/functions/mp-create-payment/index.ts"
Task: "Implementar mp-webhook em supabase/functions/mp-webhook/index.ts"
```

### User Story 2

```bash
Task: "Implementar mp-save-card em supabase/functions/mp-save-card/index.ts"
Task: "Implementar mp-remove-card em supabase/functions/mp-remove-card/index.ts"
Task: "Criar SavedCard model e SavedCardRepository em pitgo/Features/PaymentMethods/"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Completar Phase 1 (Setup) e Phase 2 (Foundational).
2. Completar Phase 3 (US1 — Pix). Isso sozinho já permite que clientes paguem e sejam despachados
   em ambos os fluxos.
3. **PARAR e VALIDAR** com o Cenário 1 de `quickstart.md` antes de continuar.

### Incremental Delivery

1. Setup + Foundational → base pronta.
2. US1 (Pix) → validar → build/demo (MVP).
3. US2 (cadastro de cartão) → validar → build/demo.
4. US4 (reembolso automático) → validar → build/demo.
5. US3 (pagar com cartão salvo, depende de US2) → validar → build/demo.
6. Polish.

---

## Notes

- [P] tarefas tocam arquivos diferentes e não têm dependência pendente nesta lista.
- Nenhuma tarefa grava Access Token, PAN ou CVV em código, log ou migração.
- A migração é forward-only e compartilhada: T004/T005/T006/T024 editam o mesmo arquivo, nunca uma
  migração já aplicada — se outra plataforma já a publicou primeiro, estas tarefas se tornam
  verificação de leitura, não nova autoria.
- Faça commit após cada tarefa ou grupo lógico; pare em qualquer checkpoint para validar a story
  isoladamente antes de seguir para a próxima.
