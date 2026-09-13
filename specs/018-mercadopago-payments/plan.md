# Implementation Plan: Pagamento de serviços (Pix e cartão) — iOS

**Branch**: `018-mercadopago-payments` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/018-mercadopago-payments/spec.md`

## Summary

Adicionar pagamento via Pix e cartão salvo (Mercado Pago) ao client iOS, como etapa que passa a
gatear o despacho do prestador tanto no fluxo padrão (busca sequencial MOBILE_SEQUENTIAL, `013`)
quanto na chamada PitTec sob demanda (`015`). O cliente cadastra cartões de forma totalmente
opcional numa área dedicada de formas de pagamento (Perfil); a etapa de pagamento da solicitação só
oferece Pix e cartões já cadastrados, nunca cadastro inline. O Access Token do Mercado Pago fica só
em Supabase Secrets, nunca no app; o tokenizador de cartão roda no app via o SDK nativo iOS do
Mercado Pago (`mercadopago/sdk-ios`, módulo CoreMethods), e a cobrança/estorno passam pelas mesmas
Edge Functions e tabelas Postgres já compartilhadas com o Android (criadas uma única vez).

Diferente do desenho Android, o ponto exato em que o pagamento passa a ser exigido no fluxo
MOBILE_SEQUENTIAL é `request_mobile_dispatch_candidate` (a ação "Solicitar este guincho" sobre uma
proposta já apresentada com preço exato), não `start_mobile_dispatch` — porque o contrato real e
compartilhado desse fluxo (`013`) não expõe nenhum preço de catálogo antes de uma proposta existir
(cada provider define seu próprio preço, `016`). No fluxo PitTec, o gate permanece em
`start_pittec_dispatch`, cobrando uma tarifa fixa de plataforma (não uma estimativa por distância,
que o contrato real de `015` não permite calcular no client antes do aceite). Ver
[research.md §9-10](research.md) para a justificativa completa; nenhum requisito funcional de
`spec.md` muda por causa disso.

## Technical Context

**Language/Version**: Swift 6, modo de concorrência estrita

**Primary Dependencies**: `supabase-swift` (`Auth`/`PostgREST`/`Functions`/`Realtime`, já
habilitados); uma dependência nova e justificada: **`mercadopago/sdk-ios`** (Swift Package Manager),
módulo CoreMethods, para tokenização de cartão isolada do escopo PCI, sem alternativa
nativa/Apple/HealthKit-like para esse propósito. Nenhuma biblioteca de QR Code é necessária — a API
de Pagamentos do Mercado Pago já devolve o QR Pix pronto em Base64 (research.md §3), decodificado
com `Data(base64Encoded:)`/`UIImage` nativos.

**Storage**: Supabase PostgreSQL com RLS/Realtime (backend compartilhado); duas tabelas novas
(`payments`, `saved_cards`), criadas uma única vez e reaproveitadas por Android e iOS; nenhum dado
sensível de cartão é persistido no app nem no backend, apenas identificadores reutilizáveis
retornados pelo Mercado Pago

**Testing**: sem testes automatizados, conforme a governança do projeto; verificação (leitura) do
schema/Edge Functions compartilhados, build via `xcodebuild`, validação manual orientada por
cenários (sandbox do Mercado Pago) em `quickstart.md`

**Target Platform**: iOS 17+, iPhone e iPad

**Project Type**: aplicativo iOS nativo de alvo único com backend Supabase compartilhado

**Performance Goals**: confirmação de pagamento (Pix ou cartão) refletida na UI em poucos segundos
(SC-005); fluxo Pix completo em até 2 minutos (SC-001); estorno automático concluído ou escalado
para suporte sem exigir ação do cliente (SC-007)

**Constraints**: Access Token e demais segredos do Mercado Pago só em Supabase Secrets, nunca no
bundle iOS; Public Key do Mercado Pago só via `Config/Secrets.xcconfig`/Build Setting/`Info.plist`
(`004`/`010`); nenhuma cobrança duplicada por solicitação (idempotência por `request_id`); nenhum
número completo de cartão, CVV ou validade persistido; despacho (MOBILE_SEQUENTIAL e PitTec)
bloqueado enquanto o pagamento não estiver aprovado, no ponto de gate correto de cada fluxo
(research.md §9-10); cadastro de cartão restrito à área dedicada de formas de pagamento, sem
cadastro inline no checkout (FR-019); webhook público deve validar a origem da notificação e sempre
reconsultar o pagamento na API do Mercado Pago antes de confiar no status

**Scale/Scope**: 2 tabelas novas, 5 Edge Functions novas (`mp-create-payment`, `mp-save-card`,
`mp-remove-card`, `mp-webhook`, `mp-refund-payment`) — todas compartilhadas, criadas uma única vez —,
guarda de pagamento adicionada a `request_mobile_dispatch_candidate` e a `start_pittec_dispatch`,
guarda de estorno adicionada a `cancel_mobile_appointment`/`cancel_pittec_search`/
`advance_pittec_dispatch`, duas features iOS novas (`Features/Payment`, `Features/PaymentMethods`) e
extensões pontuais em `Features/MobileDispatch`, `Features/PitTec`, `Features/AppointmentTracking` e
`Features/Profile`

## Constitution Check

*GATE inicial e pós-design: aprovado sem exceções.*

- **Simplicidade/YAGNI — PASS**: reutiliza `Auth`/`PostgREST`/`Functions`/`Realtime` já habilitados;
  nenhuma fila externa, painel administrativo ou split de pagamento a prestadores. `CoreMethods` do
  SDK do Mercado Pago é a única dependência nova, com uso restrito ao formulário de tokenização.
- **iOS nativo/MVVM — PASS**: Views SwiftUI stateless; `PaymentCheckoutViewModel`/
  `PaymentMethodsViewModel` (`@Observable`) expõem estado e eventos; `PaymentRepository`/
  `SavedCardRepository` isolam Supabase/SDK do Mercado Pago.
- **Estado/UX — PASS**: `PaymentCheckoutUiState`/`PaymentMethodsUiState` são `enum`s explícitos e
  mutuamente exclusivos; toda informação/ação tem representação textual, sem depender só de cor.
- **Dados/segurança — PASS**: cobrança/estorno ficam em RPCs `SECURITY DEFINER` e Edge Functions
  autenticadas; Access Token nunca sai do backend; `saved_cards` guarda só bandeira/últimos dígitos/
  id reutilizável; RLS restringe cada tabela ao cliente dono.
- **Qualidade proporcional — PASS**: reutiliza Realtime/`DispatchResumeCoordinator`/repositórios já
  existentes; nenhuma suíte de testes automatizada criada sem solicitação; `quickstart.md` cobre a
  matriz manual ponta a ponta via sandbox.

Não há violação constitucional a justificar.

## Design Decisions

1. **Backend criado uma única vez, compartilhado com o Android**: `payments`/`saved_cards`, as cinco
   Edge Functions e as guardas de RPC pertencem ao projeto Supabase compartilhado; esta feature iOS
   não autora nenhum schema novo além do que a primeira plataforma a implementar já publica
   (research.md §0).
2. **Gate de pagamento em `request_mobile_dispatch_candidate`, não em `start_mobile_dispatch`**:
   divergência justificada do desenho Android — o preço de MOBILE_SEQUENTIAL só existe por proposta
   de candidato, nunca por catálogo (research.md §9). Buscar/folhear candidatos continua gratuito.
3. **Gate de pagamento em `start_pittec_dispatch` com tarifa fixa de plataforma**: idêntico ao
   Android em termos de ponto de gate, mas o valor é uma constante de produto, não uma estimativa
   por distância — o contrato real de `015` não expõe distância ao cliente antes do aceite
   (research.md §10).
4. **Tokenização de cartão só no cliente**: o SDK nativo iOS do Mercado Pago (CoreMethods) gera o
   token do cartão dentro do app; o app nunca envia PAN/CVV ao backend do PitGo, só o token de curta
   duração.
5. **Cartão salvo via Customer + Customer Card do Mercado Pago**: `mp-save-card` cria (ou
   reaproveita) um Customer do Mercado Pago vinculado ao `client_id` do PitGo e salva o token como
   Customer Card, retornando um `mp_card_id` reutilizável — mecanismo suportado pelo próprio Mercado
   Pago, idêntico ao Android por ser a mesma Edge Function compartilhada.
6. **Cobrança e estorno concentrados em Edge Functions dedicadas**: `mp-create-payment` e
   `mp-refund-payment` são os únicos pontos que guardam/usam o Access Token; RPCs Postgres só leem e
   escrevem o resultado já processado.
7. **Webhook nunca confia no corpo recebido**: `mp-webhook` sempre busca o pagamento pelo `id` na
   API do Mercado Pago antes de atualizar `payments`, e usa `request_id` (`external_reference`) para
   religar ao despacho correspondente — publica no canal `payment:<request_id>` que o app iOS
   assina via `supabase-swift` Realtime.
8. **Idempotência por solicitação**: `mp-create-payment` usa o `request_id` como chave de
   idempotência ao chamar a API do Mercado Pago, atendendo FR-011/SC-006 sem lógica extra no app.
9. **Estorno automático dirigido por evento, não por polling**: os próprios RPCs de cancelamento
   (`cancel_mobile_appointment`, `cancel_pittec_search`, `advance_pittec_dispatch`) enfileiram o
   estorno quando o pagamento já estava aprovado e o atendimento não foi concluído (FR-015/FR-017);
   `mp-refund-payment` aplica até 3 tentativas automáticas antes de marcar `REFUND_FAILED` para
   acompanhamento manual (FR-018).
10. **Sem cadastro inline no checkout**: a etapa de pagamento da solicitação lê apenas os cartões já
    salvos; o fluxo de cadastro fica isolado em `Features/PaymentMethods`, reduzindo estados e telas
    do checkout (decisão do usuário, ver Clarifications em spec.md).
11. **Nova rota de pagamento compartilhada**: `PitGoRoute.payment(requestID:dispatchKind:)` fica
    entre a decisão do cliente (tocar "Solicitar este guincho" ou "Chamar PitTec") e a RPC de
    despacho correspondente; ao aprovar, o `PaymentCheckoutViewModel` invoca
    `request_mobile_dispatch_candidate`/`start_pittec_dispatch` com o mesmo `request_id` já pago, em
    vez de a UI de proposta/Home chamar essas RPCs diretamente (`payment-realtime-ui.md`).

Detalhes e alternativas estão registrados em [research.md](research.md).

## Project Structure

### Documentation (this feature)

```text
specs/018-mercadopago-payments/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── mercadopago-edge-functions.md
│   ├── payment-rpcs.md
│   └── payment-realtime-ui.md
└── tasks.md                         # criado posteriormente por $speckit-tasks
```

### Source Code (repository root)

```text
pitgo/
├── Config/Secrets.xcconfig                          # + MERCADO_PAGO_PUBLIC_KEY (004/010)
├── Core/
│   ├── Account/Model/AccountContext.swift            # AccountSnapshot.profile.cpf reaproveitado
│   ├── Catalog/{Model,Repository}/                   # inalterado — nenhum preço de catálogo novo
│   ├── Navigation/{PitGoRoute.swift, PitGoRootView.swift}   # + .payment(requestID:dispatchKind:)
│   └── Network/SupabaseClientProvider.swift           # Functions já instalado (009/015)
└── Features/
    ├── Payment/                          # NOVO: checkout (Pix + cartão salvo) da solicitação
    │   ├── Model/PaymentModels.swift
    │   ├── Data/PaymentDTOs.swift
    │   ├── Repository/PaymentRepository.swift
    │   ├── ViewModel/PaymentCheckoutViewModel.swift
    │   └── Views/PaymentCheckoutView.swift
    ├── PaymentMethods/                   # NOVO: cadastro/lista/remoção de cartões (área dedicada)
    │   ├── Model/SavedCardModels.swift
    │   ├── Repository/SavedCardRepository.swift
    │   ├── ViewModel/PaymentMethodsViewModel.swift
    │   └── Views/PaymentMethodsView.swift
    ├── MobileDispatch/                   # request_mobile_dispatch_candidate passa por Payment antes
    │   ├── Model/MobileDispatchModels.swift   # + caso de falha PAYMENT_REQUIRED
    │   └── Views/ClientMobileDispatchView.swift  # "Solicitar" navega para .payment(...) primeiro
    ├── PitTec/                            # start_pittec_dispatch passa por Payment antes
    │   ├── Model/PitTecModels.swift        # + caso de falha PAYMENT_REQUIRED
    │   └── Views/PitTecView.swift          # "Chamar PitTec" navega para .payment(...) primeiro
    ├── AppointmentTracking/Views/AppointmentTrackingView.swift  # feedback de estorno (REFUNDED/REFUND_FAILED)
    └── Profile/Views/ProfileView.swift     # novo item "Formas de pagamento" abrindo PaymentMethods

# Nenhuma migration/Edge Function nova autorada por este repositório — apenas consumidas,
# compartilhadas com o Android (ver research.md §0).
```

**Structure Decision**: mantém o alvo único e a organização feature-first já adotada.
`Features/Payment` concentra o checkout da solicitação; `Features/PaymentMethods` concentra o
cadastro opcional de cartão como área independente (decisão do usuário). `MobileDispatch` e `PitTec`
recebem apenas o redirecionamento de navegação para a nova rota de pagamento antes de suas RPCs de
reserva/início, sem duplicar o estado de despacho já existente.

## Complexity Tracking

Nenhuma violação constitucional foi identificada; a única dependência nova (`mercadopago/sdk-ios`) é
necessária e sem alternativa nativa para tokenização PCI-compliant.
